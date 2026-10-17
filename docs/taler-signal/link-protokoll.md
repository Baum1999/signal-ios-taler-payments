# Link-Protokoll Signal <-> Taler

Stand: 2026-09-29. Verbindlich für Android und iOS. Keine App-zu-App-IPC:
Signal und Taler reden ausschließlich über Links (Eiserne Regel 2).

Legende der Markierungen: **[Ist Android]** = im Code von `gnu-fork` geprüft.
**[Neu]** = im Vertrag festgelegt, auf Android noch nicht vorhanden (siehe
`android-nachzieh-liste.md`). **[Offen]** = nicht entschieden oder nicht
geprüft.

## 1. Überblick

| Link | Richtung | Zweck | Auf Android |
|---|---|---|---|
| `compose-send` | Signal -> Taler | Zahlung erstellen (Senden oder Anfordern) | vorhanden |
| `compose-refund` | Signal -> Taler | Rückerstattung erstellen | vorhanden |
| `compose-abort` | Signal -> Taler | eigene offene Zahlungen abbrechen (Gap A) | **[Neu]** |
| Aktionslink `pay-push` / `pay-pull` | Signal -> Taler | Annehmen (fremde URI), Abbrechen (eigene URI) | vorhanden, aber als `taler://` |
| Rücksprung, status-Variante | Taler -> Signal | Ergebnis von compose-send, compose-refund und Aktionslink | vorhanden |
| Rücksprung, result-Variante | Taler -> Signal | Ergebnis pro URI von compose-abort | **[Neu]** |

## 2. Gemeinsame Regeln

### 2.1 Schemes je Plattform

| | Signal -> Taler | Taler -> Signal |
|---|---|---|
| Android | `talerlink://` für compose-*; `taler://` für Aktionslinks. Immer **explizit adressiert**: `Intent.ACTION_VIEW` plus `setPackage(de.lenkenhoff.talerfuersignal.fdroid)`, bei `talerlink://` zusätzlich `setClassName(..., "net.taler.wallet.main.MainActivity")` [Ist Android: `TalerSendActions.kt:53-56`, `TalerRefundActions.kt:65-68`, `TalerAcceptRejectActions.kt:35-37`] | `sgnl://taler-return`, explizit an das per Signing-Cert verifizierte Package [Ist Android: `ReturnIntentSender.kt:63-99`] |
| iOS | `talerlink://` für **alle** Links, auch Annehmen und Abbrechen (`talerlink://pay-push/...`). iOS kennt kein `setPackage`, und Upstream-GNU-Taler registriert ebenfalls `taler://`; welche App iOS bei doppelt registriertem Scheme öffnet, ist nicht deterministisch (siehe `entscheidungen.md` E2) | `sgnl://taler-return`, geöffnet per `UIApplication.open` |

Konsequenz für Taler-Android [Neu]: Damit ein iOS-first-Vertrag später auf
Android ohne Umbau gilt, soll Taler-Android `talerlink://pay-push/...` und
`talerlink://pay-pull/...` ebenfalls annehmen (N1 der Nachzieh-Liste). Heute
kennt der Manifest-Filter `talerlink` gar nicht (`AndroidManifest.xml:76-85`
listet nur `taler`, `ext+taler`, `payto`); die compose-Links funktionieren
nur, weil Signal sie per `setClassName` direkt an die Activity schickt und
`MainActivity` sie selbst zerlegt (`MainActivity.kt:437-442`).

Der Rücksprung-Wert `returnUri` ist auf beiden Plattformen exakt
`sgnl://taler-return` (ohne Query, ohne Pfad, ohne Fragment).

### 2.2 Kodierung (Pflicht für alle Sender)

1. Jeder Parameterwert wird **streng prozent-kodiert**: nur die
   RFC-3986-unreserved-Zeichen `A-Z a-z 0-9 - . _ ~` bleiben roh, alles andere
   wird als `%XX` (UTF-8, Hex in Großbuchstaben) kodiert. Insbesondere `+ & = / : ? # % |`
   und Leerzeichen. Leerzeichen ist `%20`, **nie** `+`.
   Grund: Die Werte sind selbst URIs (`talerUri`, `originalUri`, `uri`,
   `returnUri`) oder JSON (`talerPaymentData`). Android dekodiert `+` in
   Query-Werten zu Leerzeichen (`Uri.getQueryParameter`, `URLDecoder`), also
   würde ein rohes `+` (z. B. in `taler+http://`) still verfälscht.
2. **Wiederholte Parameter statt Trennzeichen.** Mehrere URIs stehen als
   `uri=...&uri=...`, mehrere Ergebnisse als `result=...&result=...`. Nie
   Komma-getrennt (URIs können Kommas enthalten). Die Reihenfolge wiederholter
   Parameter bleibt erhalten und ist bedeutsam.
3. **`result` wird am ersten `|` geteilt:** links die URI, rechts der Status.
   Fehlt das `|` oder ist der Status unbekannt, wird nur dieser Eintrag
   verworfen, nicht der ganze Rücksprung.
4. Namen sind case-sensitiv und exakt wie in den Tabellen. Sie werden nie
   umbenannt (README, Versionierung).
5. Die Reihenfolge **verschiedener** Parameter ist für Empfänger unerheblich.
   Sender halten die in den Tabellen genannte Reihenfolge ein (stabile Tests,
   Diff-Lesbarkeit). Android baut compose-send mit `memberCount` als letztem
   Parameter (`TalerSendActions.kt:37-51`).

### 2.3 Lesen beim Empfänger

- Unbekannte Parameter werden ignoriert.
- Kommt ein nicht wiederholbarer Parameter mehrfach vor, gilt der **erste**
  Wert (Verhalten von `Uri.getQueryParameter`). Sender erzeugen nie
  Duplikate. Abweichung Android: `ReturnCallbackParams.extract` nimmt den
  letzten Wert (`ReturnCallbackParams.kt:33-39`, `toMap()`), siehe N9.
- Pflichtparameter fehlt oder ist leer: Link wird verworfen (Details je Link).
  Android akzeptiert leere Strings bei compose-* (`MainActivity.kt:471-472`,
  prüft nur auf null), siehe N9.
- Zahlen: nicht parsbar -> Standardwert (siehe Tabellen), nie Absturz.

### 2.4 correlationId

- Wird von Signal pro Vorgang neu erzeugt: UUID, Kleinbuchstaben
  (`UUID.randomUUID().toString()`).
- Signal legt in `TalerCorrelationStore` einen Eintrag an: Intent
  (`CorrelationIntent`, siehe `datenmodell.md`), Thread, ggf. URI(s) und
  Zitat-Referenz. TTL **15 Minuten** ab Anlage, **single-use** (`take` entfernt
  immer, auch abgelaufene), nur im Speicher, nicht über Neustarts. [Ist
  Android: `TalerCorrelationStore.kt:44-83`]
- Taler kennt die correlationId nur als Zuordnungs-Token und schickt sie
  unverändert zurück. Kein Taler-seitiger Zustand hängt an ihrer Bedeutung.
- Bekannte Grenze [Ist Android]: Bei SEND und REFUND committet Taler die
  Zahlung **vor** dem Rücksprung. Geht der Store-Eintrag vorher verloren
  (Prozess-Tod, TTL überschritten), existiert eine bezahlte Überweisung ohne
  Nachricht in Signal (`TalerCorrelationStore.kt:23-38`, als "bekannte,
  akzeptierte Einschränkung" dokumentiert). iOS teilt diese Grenze. [Offen:
  persistenter Store für SEND/REFUND]

### 2.5 Rücksprung-Adressierung und Vertrauen

iOS kann nicht prüfen, welche App ein Scheme registriert hat, und kennt keine
Cert-Prüfung. Android prüft **auf der Taler-Seite**, an wen der Rücksprung geht
(Signing-Cert-Allowlist `AllowedCallers`, `ReturnIntentSender.kt:63-76`).
Signal-Android prüft den Absender des Rücksprungs **nicht**
(`TalerReturnActivity.kt` enthält keine Aufrufer-Prüfung; das Zielbild 4.11
behauptet das Gegenteil, siehe N8). Für beide Plattformen trägt deshalb
ausschließlich diese Kette:

1. Taler öffnet nur `sgnl://taler-return` (Scheme und Host geprüft).
2. Signal akzeptiert nur eine bekannte, nicht abgelaufene, einmal verwendbare
   `correlationId` (ohne HMAC, siehe `entscheidungen.md` E3).
3. Signal **vertraut keinem Wert des Rücksprungs**. Betrag und Status kommen
   nie aus dem Link, sondern aus der erneuten Prüfung (Contract-Entschlüsselung,
   Exchange-Status). Jede mitgelieferte URI wird geprüft (Abschnitt 6).

Ein gefälschter Rücksprung kann daher höchstens eine syntaktisch gültige,
aber fremde URI in genau den Chat schicken, den der Nutzer selbst für "Senden"
geöffnet hatte, und das nur innerhalb der 15 Minuten und einmal.

### 2.6 Sicherheitsregeln für alle Links

- **Inhaberpapier:** Jede `pay-push`/`pay-pull`-URI ist ein Inhaberpapier.
  Sie wird nie geloggt, auch nicht gekürzt (Logs: höchstens
  `TalerCorrelation.shortHash(uri)`: SHA-256, erste 12 Hex-Zeichen, beide
  Plattformen identisch), nicht in Fehlermeldungen, Crash-Reports oder
  Analytics. Das gilt auch für die vollständige Link-URL.
- **Ziel-Validierung beim Rücksprung (Taler):** Scheme `sgnl` und
  Host `taler-return` sind Pflicht. iOS prüft zusätzlich: kein User/Passwort,
  kein Port, leerer Pfad. Andere Ziele (z. B. `sgnl://linkdevice`) lösen keinen
  Rücksprung aus (kein Redirect-Gadget).
- **Query-Neuaufbau beim Rücksprung (Taler):** Die Query wird immer komplett
  verworfen und neu aufgebaut. Eine im `returnUri` mitgeschickte Query mit
  gleichnamigen Parametern könnte sonst die legitimen Werte überdecken
  (erster Wert gewinnt). [Ist Android: `ReturnIntentSender.kt:79-94`,
  `clearQuery()`]
- **Keine Geldbewegung durch Signal:** Kein Link löst in Signal eine
  Bestätigung aus. Bestätigt wird nur in der Taler-UI durch den Nutzer.
- **Metadaten sind Anzeigehilfe:** Werte aus Links (`recipientHint`,
  `memberCount`, `senderAppName`) sind untrusted und dürfen nur angezeigt, nie
  für Entscheidungen über Geld genutzt werden.

## 3. compose-send

Signal bittet Taler, eine Zahlung zu erstellen. Betrag, Währung und Zweck
fragt **Taler** ab; Signal kennt keine Beträge. Ob gesendet oder angefordert
wird, wählt der Nutzer in Taler per Umschalter (`direction` ist nur die
Anfangsstellung).

**Scheme:** Android `talerlink://compose-send` (explizit an `MainActivity`),
iOS `talerlink://compose-send`.

| Parameter | Pflicht | Typ | Werte / Standard | Kodierung |
|---|---|---|---|---|
| `recipientHint` | nein | String | Anzeigename des Chats. Fehlt er: kein Hinweis. Nur Anzeige | streng prozent-kodiert |
| `senderAppName` | nein | String | Anzeigename der sendenden Messenger-App, z. B. `Signal`. Kein fester Enum/Liste - jeder Absender setzt seinen eigenen Namen. Fehlt er: kein Zweck-Vorschlag. Taler nutzt ihn ausschließlich als Vorschlagstext fürs Zweck-Feld (`"send via <Name>"`, mit `recipientHint` zusätzlich `": <Hint>"`), weiterhin frei editierbar | streng prozent-kodiert |
| `isGroup` | nein | Bool | `true` oder `false`. Empfänger: nur `true` (Android: groß/klein egal, `String?.toBoolean()`) ist wahr, sonst `false` | roh |
| `direction` | nein | Enum | `PAY_PUSH` (Senden) oder `PAY_PULL` (Anfordern). Fehlt oder unbekannt: `PAY_PUSH`. Signal sendet immer `PAY_PUSH` | roh |
| `disappearingMessagesSeconds` | nein | Ganzzahl >= 0 | Verschwinde-Timer des Chats in Sekunden, `0` = aus. Nicht parsbar: `0` | Dezimalziffern |
| `correlationId` | ja | UUID | siehe 2.4 | roh (nur `0-9a-f-`) |
| `returnUri` | ja | URI | immer `sgnl://taler-return` | streng prozent-kodiert |
| `memberCount` | nur wenn `isGroup=true` | Ganzzahl >= 0 | Zahl der Gruppenmitglieder laut Signal. Fehlt oder nicht parsbar: `0`. Nur Hinweis, Taler verlässt sich nicht darauf | Dezimalziffern |

Sender-Reihenfolge: `recipientHint`, `senderAppName`, `isGroup`, `direction`,
`disappearingMessagesSeconds`, `correlationId`, `returnUri`, dann (nur
Gruppe) `memberCount`. [Ist Android: `TalerSendActions.kt:37-51`]

Beispiel (1:1-Chat, Umbrüche nur zur Lesbarkeit):

```
talerlink://compose-send?recipientHint=Anna%20M%C3%BCller&isGroup=false
  &direction=PAY_PUSH&disappearingMessagesSeconds=0
  &correlationId=6f1c2a34-8b1e-4d7a-9c55-0e8f3b2a1d90
  &returnUri=sgnl%3A%2F%2Ftaler-return
```

Gruppe (`isGroup=true`, `memberCount=5`, `disappearingMessagesSeconds=86400`)
hängt `&memberCount=5` an.

**Rückgabe:** status-Variante (Abschnitt 8) mit `status=ready` plus `talerUri`
und `talerPaymentData` (bei Einzelzahlung genau eine URI im JSON, bei
Gruppen-Split N). `status=cancelled`, wenn der Nutzer Taler verlässt, bevor
die Zahlung erstellt wurde. Taler committet die Zahlung vor dem Rücksprung.

### Fehlerfälle compose-send

| Fall | Taler | Signal |
|---|---|---|
| `correlationId` oder `returnUri` fehlt | Link wird still verworfen, keine UI, **kein** Rücksprung (Taler könnte nirgends hin). [Ist Android: `MainActivity.kt:471-472`] | Store-Eintrag läuft nach 15 min ab |
| `returnUri` hat falsches Scheme/Host | Link wird angenommen, die Zahlung kann erstellt werden, aber es gibt **keinen** Rücksprung (`fire` liefert false) [Ist Android: `ReturnIntentSender.kt:61`]. [Offen: Soll Taler den Link schon beim Öffnen verwerfen? Der Nutzer hätte sonst eine Zahlung ohne Signal-Nachricht] | nichts |
| `direction` fehlt/unbekannt | Standard `PAY_PUSH` | - |
| `direction` = anderer Wert (z. B. `WITHDRAW`) | Vertrag: wie unbekannt (`PAY_PUSH`). Android akzeptiert heute jeden `TalerUriKind`-Namen (`MainActivity.kt:473-476`), siehe N9 | - |
| Kein Guthaben in Taler | Taler zeigt Fehler und ruft beim Verlassen `cancelled` zurück | nichts gesendet |
| Kaltstart über den Link | Taler wartet, bis wallet-core bereit ist, bevor die UI Beträge verarbeitet. Android: reaktives Laden der Salden [Ist Android: `ComposeSendScreen.kt`, Kommentar und Code ab Zeile 225]; iOS: `backendState == .ready` abwarten | - |
| Zweiter compose-send während der erste offen ist | Der ältere Screen wird ersetzt, ohne `cancelled` zu feuern [Ist Android: `MainActivity.kt:381-420`]; iOS: gleiches Verhalten anstreben | ältere correlationId bleibt ungenutzt bis TTL |
| Taler nicht installiert | - | Android: Menüeintrag nur sichtbar, wenn Taler installiert **und** Cert stimmt (`AttachmentKeyboardFragment.kt:158`); `startActivity` in `runCatching`, stiller Abbruch ohne Toast (`TalerSendActions.kt:62`). iOS: Eintrag nur, wenn `canOpenURL(talerlink://)`; `open` schlägt fehl -> nichts senden |
| Kein Rücksprung (Nutzer wechselt weg, Prozess beendet) | Taler kann bereits committet haben | Es wird nichts gesendet. Bekannte Grenze, siehe 2.4 |

**Signal-Regeln beim Empfang des Rücksprungs (SEND):**

1. `status` muss `ready` sein, sonst wird nichts gesendet.
2. Bevorzugt `talerPaymentData` (JSON, Abschnitt `datenmodell.md`). Wird es
   nicht geparst oder ist die `uri`-Liste leer, gilt `talerUri` als
   Rückfall (ältere Taler-Versionen).
3. Jede URI muss `TalerUriDetector.isExactlyOneUri` bestehen (der ganze
   String ist genau eine URI) **und** von `TalerUriParser.classify` als
   `PAY_PUSH` oder `PAY_PULL` erkannt werden. Schlägt eine URI fehl, wird
   **nichts** gesendet (kein Teilversand). Android prüft im JSON-Pfad nur
   `classify != null` und lässt auch `PAY`, `WITHDRAW`, `REFUND` durch
   (`TalerReturnActivity.kt:270` gegen `:224-225`), siehe N5.
4. Nur in 1:1-Chats und Gruppen, nicht in "Notiz an mich". [Ist Android:
   `TalerReturnActivity.kt:222`, `:259`]
5. Body: `legacyText`, Leerzeile, URIs durch Leerzeile getrennt; dazu das
   Proto-Feld 9000 (`datenmodell.md`). Ohne JSON (Rückfall): lokalisierter
   Text "Payment sent: <Art> (<URI>)" bzw. "Payment requested: ..." plus Feld
   9000 mit der einen URI. `expiresIn` = Verschwinde-Timer des Chats.
6. Danach öffnet Signal den Chat (auch bei `cancelled`, solange die
   correlationId gültig war). [Ist Android: `TalerReturnActivity.kt:145-169`]

## 4. compose-refund

Signal bittet Taler, eine Rückerstattung für eine **empfangene, angenommene**
Zahlung zu erstellen. `originalUri` ist die einzige Angabe. Taler löst daraus
selbst die empfangene Transaktion auf und füllt Betrag und Zweck vor. Signal
erfindet keinen Betrag.

**Scheme:** wie compose-send.

| Parameter | Pflicht | Typ | Werte | Kodierung |
|---|---|---|---|---|
| `originalUri` | ja | URI | die ursprüngliche `taler://pay-push/...`-URI der Zahlung | streng prozent-kodiert |
| `correlationId` | ja | UUID | 2.4 | roh |
| `returnUri` | ja | URI | `sgnl://taler-return` | streng prozent-kodiert |

Reihenfolge: `originalUri`, `correlationId`, `returnUri`. [Ist Android:
`TalerRefundActions.kt:57-63`]

Beispiel:

```
talerlink://compose-refund?originalUri=taler%3A%2F%2Fpay-push%2Fexchange.example.org%2F7Q4XK2
  &correlationId=0b6c9f52-31d8-4a0f-8a3e-6d2c5e7f9a11
  &returnUri=sgnl%3A%2F%2Ftaler-return
```

**Gate in Signal:** Der Menüpunkt erscheint nur bei `status == ANGENOMMEN` und
`!isOwnPayment`; bei Gruppenkarten nur für Anteile, die dieser Nutzer selbst
beansprucht hat. [Ist Android: `TalerCardActionGate.kt:showRefund`]

**Rückgabe:** `status=ready` plus `talerUri` (die Rückerstattungs-URI). Taler-Android
sendet **kein** `talerPaymentData` (`ComposeRefundScreen.kt:124`); Signal
akzeptiert beides. `cancelled` beim Verlassen ohne Erstellung.

**Signal-Regeln:** Kein automatisches Senden. Die URI wird als **Entwurf**
vorbereitet: Text "Refund: <Zweck>" (mit `legacyText`, sonst mit der URI),
Leerzeile, URI(s). Stammt der Vorgang aus dem Long-Press-Menü der Karte
(Zitat-Referenz im Store-Eintrag), wird der Entwurf als **Zitat-Antwort** auf
die Originalnachricht angelegt. [Ist Android: `TalerReturnActivity.kt:120-166`]
Für die URI-Prüfung gilt Abschnitt 6, wobei im Entwurfspfad nur die
"genau eine URI"-Prüfung greift (kein `classify`), weil nichts automatisch
gesendet wird.

### Fehlerfälle compose-refund

| Fall | Verhalten |
|---|---|
| `originalUri`, `correlationId` oder `returnUri` fehlt | Taler verwirft still, kein Rücksprung [Ist Android: `MainActivity.kt:489-491`] |
| `originalUri` nicht auf eine Transaktion auflösbar | Taler zeigt einen Fehler; beim Verlassen `cancelled` |
| Schon erstattet | Taler warnt (dauerhafter Speicher `SentRefundStore`), Nutzer kann verwerfen und neu erstellen |
| Taler nicht installiert, kein Rücksprung, Store-Eintrag abgelaufen | wie compose-send |

## 5. compose-abort [Neu, Gap A]

Beim **"Für alle löschen"** einer Nachricht mit eigenen, noch offenen
`pay-push`-Zahlungen bittet Signal Taler, diese tatsächlich abzubrechen. Auf
Android existiert das noch nicht (heute wird nur lokal `LOKAL_ABGEBROCHEN`
gesetzt, `TalerAcceptRejectActions.kt:115-125`). iOS baut es zuerst.

**Auslöser und Berechtigung:** nur "Für alle löschen" (nicht "Für mich
löschen"). Betroffen sind nur URIs, für die das Gate `showCancel` gilt:
`status == OFFEN && uriKind == PAY_PUSH && isOwnPayment`. Ist die Liste leer,
passiert nichts.

**Scheme:** wie compose-send. Auf Android explizit an `MainActivity`.

| Parameter | Pflicht | Typ | Werte | Kodierung |
|---|---|---|---|---|
| `uri` | ja, mindestens einmal | URI, **wiederholt** | eine abzubrechende `taler://pay-push/...`-URI pro Parameter, Reihenfolge erhalten | streng prozent-kodiert |
| `correlationId` | ja | UUID | 2.4, `CorrelationIntent = ABORT` mit der `uris`-Liste | roh |
| `returnUri` | ja | URI | `sgnl://taler-return` | streng prozent-kodiert |

Reihenfolge: alle `uri`, dann `correlationId`, `returnUri`.

Beispiel (zwei URIs eines Gruppen-Splits):

```
talerlink://compose-abort?uri=taler%3A%2F%2Fpay-push%2Fexchange.example.org%2FAAAA
  &uri=taler%3A%2F%2Fpay-push%2Fexchange.example.org%2FBBBB
  &correlationId=91d3e0aa-5c47-4b6e-a8d2-7f10c3b9e455
  &returnUri=sgnl%3A%2F%2Ftaler-return
```

Hinweis: Die ältere Spec (`2026-09-17-...-design.md`) nennt `uris=` kommagetrennt
und `results=<uri>:<status>`. Das ist überholt. Der Implementierungsplan
(`2026-09-28-taler-payment-delete-abort.md`, Zeilen 16-17) und das Zielbild
6.2 legen wiederholtes `uri` und `result=<uri>|<status>` fest, so gilt es hier.

**Taler-Verhalten:**

1. Alle `uri` lesen. Jede muss mit `taler://pay-push/` oder
   `taler://pay-pull/` beginnen (case-insensitiv, so parst es Paket T1);
   sonst wird sie verworfen. Signal sendet nur `pay-push` (Gate `showCancel`). Bleibt keine
   übrig: Link verwerfen, kein Rücksprung.
2. Jede URI auf die **eigene** laufende Transaktion abbilden
   (`OwnUriTracker`-Äquivalent). Eine URI, die Taler nicht als eigene kennt,
   erhält `declined` (Entscheidung 2026-09-29, iOS T5: jede Eingangs-URI bekommt
   genau ein Ergebnis; `declined` erzwingt in Signal keinen Status, nur einen Refresh).
   [Offen: ob auf Android `OwnUriTracker.transactionIdFor` für extern
   hereinkommende URIs ausreicht, Verifikationspunkt 2 der Spec]
3. **Eine** Sammelbestätigung ("Zahlung stornieren?" bzw. "N offene Anteile
   stornieren?"), nicht N Einzeldialoge.
4. Bei Bestätigung `abortTransaction` pro Transaktion. Ergebnis pro URI:
   `aborted`, `already_claimed` (Empfänger hat schon angenommen), `expired`.
   Bei Ablehnung des Dialogs `declined` für alle URIs dieser Anfrage.
5. Rücksprung (Abschnitt 9). Schließt der Nutzer den Dialog ohne Entscheidung
   (z. B. Wischen), sendet Taler `declined` für alle URIs (Entscheidung
   2026-09-29, iOS T5). Bereits abgeschlossene/abgelaufene/abgebrochene
   Transaktionen werden nicht erneut abgebrochen, sondern direkt gemappt
   (`already_claimed`/`expired`/`aborted`). Nur wenn Taler gar nicht
   zurückkehrt (App beendet), bleibt Signal bei `OFFEN`.

### Fehlerfälle compose-abort

| Fall | Verhalten |
|---|---|
| Taler nicht installiert / Öffnen scheitert | Fallback in Signal: lokal `LOKAL_ABGEBROCHEN` plus lokale Statuszeile (heutiges Verhalten, regressiert nie darunter) |
| Kein Rücksprung (App beendet, Nutzer wechselt weg) | Status bleibt `OFFEN` (Zielbild 6.2). **Widerspruch:** die Spec (Abschnitt "Fallback") setzt in diesem Fall ebenfalls `LOKAL_ABGEBROCHEN`. Vertrag folgt dem Zielbild. [Offen: Nutzer entscheidet] |
| correlationId abgelaufen oder unbekannt | Rücksprung wird verworfen, kein Status-Update |
| `result` mit URI, die nicht in `uris` des Store-Eintrags steht | Eintrag wird verworfen (Ziel-Validierung) |
| `result` mit unbekanntem Status / ohne `|` | nur dieser Eintrag verworfen |
| URI enthält ein rohes `|` | [Offen] Taler-URIs enthalten normalerweise keins (Crockford-Base32 im Pfad); bei Teilung am ersten `|` würde ein solcher Eintrag verworfen. Signal soll solche URIs nicht in `uri` aufnehmen |
| Mehrere Abbruch-Links parallel | jeder hat eine eigene correlationId; Taler bearbeitet je Link einen Dialog |

## 6. Aktionslink: Annehmen und Abbrechen

Ein Aktionslink ist die **normale Zahlungs-URI** plus zwei Kontext-Parameter.
Derselbe Link wird für zwei Zwecke benutzt; Taler unterscheidet danach, ob
die URI eine **eigene** ist:

| Zweck | URI ist | Taler-Verhalten |
|---|---|---|
| Annehmen (Empfänger) | fremd | Annehmen-Bildschirm (`preparePeerPushCredit` bzw. `preparePeerPullDebit`); Nutzer bestätigt |
| Abbrechen (Absender) | eigen (in Taler erzeugt, `OwnUriTracker`) | direkt zur eigenen Transaktion (mit dortigem "Abbrechen"), **nicht** Annehmen. Sonst würde die eigene Zahlung an sich selbst angenommen [Ist Android: `HandleUriScreen.kt:143-165`] |

**Scheme:**

- Android: `taler://pay-push/<rest>?correlationId=...&returnUri=...`, explizit
  per `setPackage` an Taler (kein `setClassName`).
- iOS: `talerlink://pay-push/<rest>?correlationId=...&returnUri=...` (Scheme
  `taler` durch `talerlink` ersetzt, Pfad unverändert). Für `pay-pull` analog.
  Groß/Kleinschreibung des Schemes egal (`TALER://` möglich).
- Taler-Android [Neu]: soll auch `talerlink://pay-push|pay-pull/...`
  annehmen (N1); Taler-iOS nimmt es (Paket T1).

| Parameter | Pflicht | Typ | Werte | Kodierung |
|---|---|---|---|---|
| Pfad `pay-push/<rest>` bzw. `pay-pull/<rest>` | ja | URI-Pfad | die Originalzahlungs-URI, unverändert | wie Original |
| `correlationId` | ja (für Rücksprung) | UUID | 2.4, `CorrelationIntent = ACCEPT_OR_CANCEL` | percent-kodiert |
| `returnUri` | ja (für Rücksprung) | URI | `sgnl://taler-return` | streng prozent-kodiert |

Anhängen: Enthält die URI bereits ein `?`, wird mit `&` angehängt, sonst mit
`?`. [Ist Android: `TalerAcceptRejectActions.kt:32-33`]

Beispiel iOS:

```
talerlink://pay-push/exchange.example.org/7Q4XK2
  ?correlationId=7a5e1d30-2b9c-4f88-91d6-c3a04e8b2f17
  &returnUri=sgnl%3A%2F%2Ftaler-return
```

Beispiel Android (gleiche Zahlung): `taler://pay-push/exchange.example.org/7Q4XK2?correlationId=...&returnUri=...`

**Taler-Verhalten:**

- `correlationId` und `returnUri` werden gelesen und **danach die gesamte Query
  entfernt**, bevor die URI an wallet-core geht (wallet-core kennt sie nicht).
  Bei `talerlink` wird zusätzlich das Scheme auf `taler` zurückgesetzt. Nur die
  bereinigte URI wird weitergereicht, nie die Original-URL. Unbekannte
  Query-Parameter werden ebenfalls entfernt. [Ist Android:
  `ReturnCallbackParams.stripQuery`, `HandleUriScreen.kt:125-129` (pay-pull), `:139-143` (pay-push)]
- Fehlt `correlationId` oder `returnUri` (oder ist leer): die URI wird
  normal verarbeitet, aber es gibt keinen Rücksprung. [Ist Android:
  `ReturnCallbackParams.extract` liefert dann null]
- Rücksprung: status-Variante ohne `talerUri`/`talerPaymentData`. Annehmen:
  `ready` nach erfolgreicher Annahme, `cancelled` beim Verlassen ohne Annahme.
  Abbrechen: Taler ruft beim Verlassen der Transaktionsansicht `ready` auf,
  **unabhängig** davon, ob abgebrochen wurde (`TransactionDetailScreen.kt:141-149`).
  Der `status` ist bei diesem Intent deshalb nur ein Trigger, keine Aussage.

**Signal-Verhalten beim Rücksprung (ACCEPT_OR_CANCEL):** `status` wird
ignoriert. Es wird nur ein sofortiger Re-Check (Fast-Poll) der `uri` aus dem
Store-Eintrag angestoßen; der neue Status kommt aus Contract/Exchange, nicht
aus dem Link. [Ist Android: `TalerReturnActivity.kt:69-71`]

**Welche Aktionslinks Signal sendet:** Gate `TalerCardActionGate`:

| Aktion | Bedingung |
|---|---|
| Annehmen | `OFFEN && PAY_PUSH && !isOwnPayment` (Karte) |
| Abbrechen | `OFFEN && PAY_PUSH && isOwnPayment` (Long-Press-Menü) |

`pay-pull` ist im Vertrag und in Taler vorgesehen, wird aber von Signal-Android
heute nicht gesendet (`TalerCardActionGate.kt`: Annehmen nur für `PAY_PUSH`).
[Offen: Soll Signal pay-pull-Aktionslinks senden?]

### Fehlerfälle Aktionslink

| Fall | Verhalten |
|---|---|
| Taler nicht installiert | Android: `startActivity` **ohne** `runCatching` (`TalerAcceptRejectActions.kt:38`, `:84`) und Annehmen ist nicht an die Installation gekoppelt: `ActivityNotFoundException` möglich (nicht zur Laufzeit geprüft), siehe N2. Vertrag: Öffnen fängt Fehler ab, kein Absturz, kein Statuswechsel. iOS: `open` schlägt fehl -> Hinweis, kein Statuswechsel |
| Abgelaufene correlationId beim Rücksprung | verworfen, aber der reguläre Poll übernimmt den Zustand trotzdem irgendwann |
| Kein Rücksprung | Status wird vom regulären Polling nachgezogen (20 s Vordergrund, Backoff) |
| URI ist weder pay-push noch pay-pull | Signal sendet keinen Aktionslink; iOS `TalerLinks.actionLink` liefert `nil` |

## 7. Ablaufübersicht

```
Signal                                  Taler
  |  Store.put(correlationId, intent)     |
  |------ talerlink://compose-* -------->|  parse, Nutzer bestätigt
  |------ [taler|talerlink]://pay-*?... ->|  Query lesen, entfernen, bereinigte URI verarbeiten
  |<----- sgnl://taler-return ---|  Query neu aufgebaut, Ziel validiert
  Store.take(correlationId) (single-use)
  Re-Check gegen Exchange / Nachricht senden / Entwurf / Status übernehmen
```

## 8. Rücksprung, status-Variante

Für `compose-send`, `compose-refund` und Aktionslinks (Annehmen/Abbrechen).

`sgnl://taler-return?correlationId=<id>&status=<ready|cancelled>[&talerUri=<uri>][&talerPaymentData=<json>]`

**Scheme:** beide Plattformen `sgnl`, Host `taler-return`, kein Pfad.
Android: Activity `TalerReturnActivity`, exportiert, Intent-Filter
`VIEW` mit `scheme=sgnl`, `host=taler-return`. iOS: URL-Scheme
`sgnl` in der `Info.plist` von Signal, Behandlung in `AppDelegate`/`UrlOpener`.

| Parameter | Pflicht | Typ | Werte | Kodierung |
|---|---|---|---|---|
| `correlationId` | ja | UUID | Echo der gesendeten ID | roh |
| `status` | nein | Enum | `ready` oder `cancelled`; alles andere wird wie fehlend behandelt | roh |
| `talerUri` | nur bei `ready` und compose-send/-refund | URI | die neu erzeugte Zahlungs-URI (bei Gruppen-Split: die erste) | streng prozent-kodiert |
| `talerPaymentData` | nur bei `ready` und compose-send | JSON-String | siehe `datenmodell.md` | streng prozent-kodiert (das JSON enthält `"`, `{`, `:`, `/`, Leerzeichen) |

Welche Parameter wann gesendet werden (Ist Android):

| Auslöser (Intent im Store) | `status` | `talerUri` | `talerPaymentData` |
|---|---|---|---|
| SEND | `ready` / `cancelled` | ja, bei `ready` | ja, bei `ready` (`ComposeSendScreen.kt:337`, `:389`, `:506`, `:534`) |
| REFUND | `ready` / `cancelled` | ja, bei `ready` | nein (`ComposeRefundScreen.kt:124`) |
| ACCEPT_OR_CANCEL | `ready` / `cancelled` | nein | nein |

**Signal-Regeln (Empfänger):**

1. Nur `scheme == sgnl` und `host == taler-return`; sonst ignorieren.
   Auf Android ist die Activity exportiert: ein expliziter Intent einer
   fremden App umgeht den Manifest-Filter und trägt eine beliebige Daten-URI.
   Deshalb erst prüfen, ob die URI hierarchisch ist (`isHierarchical`), bevor
   Parameter gelesen werden; "immer beenden, nie sichtbar abstürzen".
2. `correlationId` fehlt oder Store kennt sie nicht (unbekannt, abgelaufen,
   schon benutzt): **still verwerfen**, keine Fehlermeldung, kein Chat-Wechsel,
   keine URI im Log. Nur eine neutrale Warnzeile ohne Wert.
3. `take` ist single-use: ein zweiter Rücksprung mit derselben ID findet nichts.
4. Welche Parameter zählen, bestimmt der **Intent des Store-Eintrags**, nicht
   der Link (ein ACCEPT-Eintrag ignoriert `talerUri`, ein SEND-Eintrag
   ignoriert `result`).
5. `talerUri` und `talerPaymentData` werden nur bei `status == ready`
   gelesen. Bei `cancelled` werden sie ignoriert, auch wenn vorhanden.
6. Zeichenketten aus dem Link sind **angreiferkontrolliert**. `status` wird nie
   angezeigt. Jede URI wird nach Regel 3 aus Abschnitt 3 geprüft, Beträge und
   Status kommen aus der eigenen Prüfung.

**Taler-Regeln (Sender):**

1. `returnUri` prüfen (2.6): Scheme `sgnl`, Host `taler-return`. Sonst
   **kein** Rücksprung.
2. Query komplett neu aufbauen: `correlationId`, `status`, dann optional
   `talerUri`, `talerPaymentData` (Android: `ReturnIntentSender.kt:88-94`).
3. Genau **ein** Rücksprung pro Vorgang (Guard `fired`). Beim Verlassen ohne
   Ergebnis `cancelled`, außer der Screen wird nur durch eine neue Instanz
   ersetzt oder wechselt auf eine Zwischenseite (z. B. TOS-Prüfung).
4. Android verifiziert zusätzlich per `PackageManager`, welche App
   `sgnl://taler-return` registriert hat, und prüft deren
   Signing-Cert (SHA-256, genau ein Signer) gegen `AllowedCallers`; erst dann
   geht ein expliziter Intent an genau dieses Package. iOS hat keine
   Entsprechung (E3).

### Fehlerfälle Rücksprung status-Variante

| Fall | Verhalten |
|---|---|
| `correlationId` fehlt / leer / unbekannt / abgelaufen / doppelt | verwerfen (Regel 2, 3) |
| `status` fehlt oder unbekannt | kein `talerUri`/`talerPaymentData` gelesen; bei ACCEPT_OR_CANCEL trotzdem Fast-Poll; bei SEND/REFUND passiert nichts |
| `status=ready`, aber `talerUri` und JSON fehlen | SEND/REFUND: nichts tun |
| `talerPaymentData` nicht parsbar | Rückfall auf `talerUri` (Android loggt eine Warnung ohne Inhalt) |
| `talerPaymentData` parsbar, aber eine URI besteht die Prüfung nicht | nichts senden; **kein** Rückfall auf `talerUri` [Ist Android: `TalerReturnActivity.kt:108-127`] |
| `talerUri` besteht die Prüfung nicht | nichts senden / kein Entwurf |
| Falsches Scheme oder Host | ignorieren |
| Rücksprung fehlt ganz | siehe 2.4 (bekannte Grenze bei SEND/REFUND) |

## 9. Rücksprung, result-Variante [Neu, Gap A]

Nur für compose-abort.

`sgnl://taler-return?correlationId=<id>&result=<uri>|<ergebnis>&result=<uri>|<ergebnis>...`

| Parameter | Pflicht | Typ | Werte | Kodierung |
|---|---|---|---|---|
| `correlationId` | ja | UUID | Echo | roh |
| `result` | nein, wiederholt | String `<uri>\|<ergebnis>` | pro URI ein Parameter, Reihenfolge wie in `uri` des Anfrage-Links. `<ergebnis>` einer von `aborted`, `already_claimed`, `expired`, `declined` | **der gesamte Wert** `<uri>\|<ergebnis>` streng prozent-kodiert (also auch das `\|` als `%7C`) |

Kein `status`-Parameter in dieser Variante. (Ein Empfänger, der `status`
vorfindet, wertet ihn bei `ABORT` nicht aus, Abschnitt 8 Regel 4.)

Beispiel:

```
sgnl://taler-return?correlationId=91d3e0aa-5c47-4b6e-a8d2-7f10c3b9e455
  &result=taler%3A%2F%2Fpay-push%2Fexchange.example.org%2FAAAA%7Caborted
  &result=taler%3A%2F%2Fpay-push%2Fexchange.example.org%2FBBBB%7Calready_claimed
```

**Signal-Regeln:**

1. Store-Eintrag muss `ABORT` sein; sonst `result` ignorieren.
2. Jeden `result`-Wert am **ersten** `|` teilen. Unbekanntes Ergebnis oder
   fehlendes `|`: nur diesen Eintrag verwerfen.
3. Nur URIs übernehmen, die in `uris` des Store-Eintrags stehen; andere
   Einträge verwerfen.
4. Ergebnis -> Status (siehe `datenmodell.md`, Abbruch-Ergebnis-Mapping):
   `aborted` -> `UNGUELTIG`, `expired` -> `ABGELAUFEN`, `already_claimed` und
   `declined` -> keine Statusänderung (Fast-Poll übernimmt den echten Zustand).
5. Keine neue lokale Statuszeile (die Zahlungsnachricht wurde gerade gelöscht).
   Die Zeile bleibt dem lokalen Fallback vorbehalten. [Plan Zeile 716]
6. URIs aus `uris`, für die kein `result` kam, bleiben unverändert.

**Taler-Regeln:** Ziel validieren und Query neu aufbauen wie in Abschnitt 8.
`ReturnIntentSender.fireAbort` (im Plan vorgesehen, noch nicht im Code)
baut: `correlationId`, dann je URI ein `result`.

## 10. Prüfregeln für URIs aus Links (Signal)

| Prüfung | Regel |
|---|---|
| "Genau eine URI" | `TalerUriDetector.isExactlyOneUri`: der ganze String ist genau ein Treffer des Musters `(?i)\b(?:taler\|ext\+taler\|payto)://\S+`, ohne Text davor oder dahinter. `taler+http://` wird bewusst **nicht** erkannt (kein Klartext-Abruf) |
| Klassifikation | `TalerUriParser.classify` (Spiegelkopie aus taler-android, byte-identisch zu halten): `taler://`, `ext+taler://`, `taler+http://` (nach Kleinschreibung), Pfad-Präfix `pay-push/`, `pay-pull/`, `pay/`, `pay-template/`, `withdraw/`, `withdraw-exchange/`, `refund/`. `payto://` wird von `classify` **nicht** erkannt (liefert null) |
| Senden zulässig | nur `PAY_PUSH` und `PAY_PULL` |
| Vorschau | nur `PAY_PUSH` und `PAY_PULL` (lokale Contract-Entschlüsselung); `PAY`, `WITHDRAW`, `REFUND` nur klassifizieren und Taler öffnen |

## 11. Änderungen gegenüber Android (Kurzfassung)

Siehe `android-nachzieh-liste.md`. Kurz: `talerlink://` auch für Aktionslinks
annehmen, compose-abort mit result-Parser, `talerPaymentData` tolerant
lesen, URI-Art im JSON-Sendepfad prüfen, Aktionslink-Öffnen absichern.
