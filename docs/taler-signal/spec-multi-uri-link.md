# Spec: Multi-URI-Link Signal an Taler (Zielbild 5.2)

**Status: ENTWURF – wartet auf Freigabe durch den Nutzer. Nicht implementieren.**

Stand: 2026-09-29. Paket D2-multiuri-spec. Grundlage: `docs/ZIEL-signal-fuer-gnu-android.md`
(Abschnitte 4.4, 5.1, 5.2, 6.2), Gap-A-Spec
`docs/superpowers/specs/2026-09-17-taler-payment-delete-abort-design.md`, AIDL-Entfernung
`docs/superpowers/specs/2026-09-09-taler-aidl-removal-design.md`, Code in
`signal-android/.../securesms/taler/` und `taler-android/wallet/.../wallet/` (Stand der
Lektüre, nichts davon wurde verändert). Was aus dem Code nicht sicher folgt, ist mit
**[UNSICHER]** markiert.

## 0. Kurzfassung

- Version 1 liefert genau **einen** neuen Link: `talerlink://compose-abort` (Gap A), aber gleich
  mit dem allgemeinen Mehr-URI-Schema (wiederholtes `uri`, `result=<uri>|<status>`) und flachen,
  versionierten Metadaten-Parametern.
- Metadaten reisen als **einzelne flache Query-Parameter** (plus `v=1`), nicht als JSON-Parameter.
- Weitere Aktionen (Annehmen mehrerer Anteile, Mehrfach-Rückerstattung) übernehmen dasselbe Schema
  unter eigenem Linknamen (`compose-accept`, `compose-refund` mit mehreren `uri`), sind aber nicht Teil von V1.

## 1. Anwendungsfälle

Ausgangslage im Code: Jede Aktion trägt genau eine URI. Bei Gruppen-Splits ruft
`TalerMenuActions.onCancelFromMenu`, `onRefreshFromMenu` und `onRefundFromMenu` die Einzelaktion
in einer Schleife pro URI auf. Für `onCancelClicked` bedeutet das ein `startActivity` pro URI;
der Kommentar in `cancelCancelablePaymentsForDeletedMessages` hält fest, dass bei mehreren
gestarteten Intents nur der zuletzt gestartete sicher ankommt. Das ist die eigentliche Lücke,
die ein Mehr-URI-Link schließt.

| # | Fall | Nutzen eines Mehr-URI-Links | V1? |
|---|---|---|---|
| 1 | **Abbrechen aller eigenen offenen Anteile beim „Für alle löschen“** (Gap A, `compose-abort`) | Ein Link, ein Sammel-Dialog in Taler, ein Rücksprung. Das ist der Spezialfall mit N = 1 bis n. | **Ja** |
| 2 | **Abbrechen aller eigenen Anteile per Long-Press-Menü** einer Gruppenkarte (`cancelUris` mit mehr als einem Element) | Gleiche Mechanik wie 1, nur anderer Auslöser (`reason=menu`). Behebt das Schleifenproblem oben. Bei genau einer URI bleibt der heutige Link (die `taler://`-URI + `correlationId`) unverändert. | **Ja**, nur bei mehr als einer URI (Frage 3) |
| 3 | **Annehmen mehrerer Anteile** einer Gruppenkarte | Heute nimmt die Karte einen Anteil pro Klick (`resolveTargetUri`); „mehrere beanspruchen“ ist bewusst möglich. Ein Sammel-Annehmen bräuchte in Taler einen Mehrfach-Claim mit Betragssumme und Teilfehlern. Es ist Geldeingang (Regel 1: Bestätigung nur in Taler). Ob wallet-core mehrere `preparePeerPushCredit` sauber parallel verkraftet, ist **[UNSICHER]**. Der Nutzen ist klein. | Nein (V2-Kandidat) |
| 4 | **Rückerstattung mehrerer Anteile** (`onRefundFromMenu` schleift pro URI) | Betrag pro Anteil, Verwendungszweck und Zitat-Antwort auf eine Nachricht. `compose-refund` hat ein eigenes, betragsabhängiges UI; der Sammelfall braucht ein eigenes Design. | Nein |
| 5 | **Bezahlen einer `pay-pull`-Anfrage** | Eine Anfrage hat genau eine URI. Es gibt keinen Mehrfachfall. | Nein (kein Bedarf) |
| 6 | **Aktualisieren/Refresh** mehrerer URIs | Rein lokal in Signal (`TalerUriRefreshJob`), kein Taler-Link. | Nicht zuständig |
| 7 | **Senden** (`compose-send`) | Die Gegenrichtung (Taler an Signal) trägt schon N URIs in `talerPaymentData.uri`. Der Link Signal an Taler trägt keine URIs. | Nicht zuständig |

**Gap-A-Spezialfall:** `compose-abort` aus dem Zielbild ist genau dieser Link. Diese Spec macht
ihn zum ersten Vertreter des allgemeinen Schemas und ersetzt damit den Teil „Encoding im
Implementierungsplan festlegen“ der Gap-A-Spec (dort offener Punkt 1). Achtung: Die Gap-A-Spec
selbst nennt noch `uris=<kommagetrennt>` und `results=…`; das Zielbild 5.2 legt dagegen
wiederholtes `uri` und `result` fest. Das Zielbild gilt, die Gap-A-Spec beziehungsweise ihr Plan
ist entsprechend zu korrigieren (Frage 1).

## 2. Varianten

Gemeinsame Randbedingungen (gelten für alle Varianten):
- Android: `Intent.ACTION_VIEW` explizit an das Taler-Package
  (`setPackage` + `setClassName(..., "net.taler.wallet.main.MainActivity")`), wie `TalerSendActions`.
  Die Grenze für die Länge ist praktisch die Binder-Transaktionsgröße (etwa 1 MB) und damit kein
  Engpass **[UNSICHER, nicht getestet]**.
- iOS: Alle Links Signal an Taler über `talerlink://`, ohne `setPackage`-Äquivalent.
  Es gibt keine dokumentierte harte Grenze für die Länge eines Custom-Scheme-URL beim `open(_:)`;
  in der Praxis funktionieren mehrere KB **[UNSICHER, vor Umsetzung mit 30 URIs auf einem Gerät testen]**.
- Größenordnung: eine `pay-push`-URI hat grob 130 bis 160 Zeichen, prozentkodiert grob 200. Ein
  Split mit 30 Anteilen liegt damit bei 6 KB **[Schätzung, nicht gemessen]**.

### Variante A: ein Link pro Aktion, gemeinsames Parameterschema, flache Metadaten (Empfehlung)

`talerlink://compose-abort?v=1&uri=…&uri=…&currency=…&totalAmount=…&…&correlationId=…&returnUri=…`
(später analog `compose-accept`).

- Vorteile: Passt zu `compose-send`/`compose-refund` (Host = Compose-Screen, alle Felder als
  Query-Parameter, siehe `TalerSendActions`, `MainActivity.composeSendFrom`). Der Host-Name ist die
  Aktion, damit gibt es keinen Dispatch auf ein Aktionsfeld, den man verwechseln könnte. Flache
  Parameter werden von einer älteren Taler-Version, die eine Metadatenspalte nicht kennt, ohne
  Fehler ignoriert; kein Doppel-Encoding; `URLComponents` (iOS) und `Uri` (Android) lesen sie ohne
  eigenen JSON-Parser. `compose-abort` ist unverändert das Gap-A-Ziel, es entsteht kein zweiter Link.
- Nachteile: Bei jeder neuen Aktion kommt ein neuer Host hinzu und muss in `MainActivity` (Android)
  sowie im iOS-Router eingetragen werden. Verschachtelte oder listenförmige Metadaten (pro-URI-Betrag)
  sind flach unbequem; V1 verzichtet deshalb darauf.

### Variante B: ein generischer Link mit Aktionsparameter

`talerlink://batch?action=abort|accept|refund&uri=…`

- Vorteile: Ein Router-Eintrag, neue Aktionen ohne neuen Host.
- Nachteile: Eine falsch geschriebene oder unbekannte `action` läuft in einen generischen Fehlerpfad
  statt in „Link unbekannt“; Taler-Screens würden im Dispatch vermischt (das Muster im Repo trennt
  bewusst compose-send und compose-refund in eigene Routentypen, siehe Kommentar in `MainActivity`
  zu `emitComposeRefund`). Bricht mit dem Namensschema `compose-*` aus 5.1. Kein Gewinn, der die
  Abweichung rechtfertigt.

### Variante C: Metadaten als ein JSON-Parameter (`meta={"v":1,…}`)

Wie `talerPaymentData` beim Rücksprung.

- Vorteile: Verschachtelung und Listen sind einfach (pro-URI-Metadaten); es gibt schon
  `kotlinx.serialization` auf beiden Android-Seiten.
- Nachteile: JSON in einer Query wird stark prozentkodiert (Anführungszeichen, Klammern, Doppelpunkte),
  das kostet etwa 40 Prozent Länge auf den ohnehin langen Links. Ein Parse-Fehler im JSON verwirft
  auf einen Schlag **alle** Metadaten, statt nur ein Feld. Auf iOS braucht es einen `Codable`-Pfad und
  identische Feldreihenfolge nur zum Test. Da die Metadaten reine Anzeigehilfe sind, ist die Robustheit
  flacher Felder mehr wert als die Ausdruckskraft von JSON.

### Variante D: wiederholte Parameter an die `taler://`-URI hängen

Verworfen. `taler://pay-push/…` ist genau eine Zahlung; wallet-core parst sie mit eigenem Format
(`HandleUriScreen` trennt `correlationId`/`returnUri` schon heute vorher ab). Mehr als eine
Zahlungs-URI in einer Zahlungs-URI wäre auch für ältere Taler-Versionen ein Fremdkörper.

### Vergleich

| Kriterium | A (Host pro Aktion, flach) | B (`batch?action`) | C (JSON `meta`) |
|---|---|---|---|
| Länge (30 URIs) | am kürzesten | wie A | etwa 0,5 bis 1 KB länger |
| Robustheit gegen ein defektes Feld | Feld einzeln verworfen | wie A | alles oder nichts |
| Rückwärtskompatibilität älterer Taler | unbekannter Host: siehe 3.7 | wie A, aber schwerer erkennbar | wie A |
| Versionierung | `v` plus additive Felder | wie A | `v` im JSON |
| Verhältnis zu `compose-abort` | identisch | ersetzt es | identisch |
| Aufwand pro neuer Aktion | neuer Host | keiner | neuer Host |

**Empfehlung: Variante A.** Sie behält die Konvention von 5.1 und verlangt keinen JSON-Pfad auf iOS.

## 3. Vertrag der Empfehlung (Variante A, V1 = `compose-abort`)

### 3.1 Link Signal an Taler

`talerlink://compose-abort?…`, Parameter als Query, jeder Wert einzeln prozentkodiert
(`Uri.Builder.appendQueryParameter` bzw. auf iOS `URLComponents` mit eigenem Zeichensatz, siehe 3.6).

| Parameter | Wiederholbar | Typ | Pflicht | Bedeutung |
|---|---|---|---|---|
| `v` | nein | Ganzzahl | optional (fehlt = 1) | Schema-Version, hier 1 |
| `uri` | **ja** | vollständige `taler://pay-push/…`-URI (Inhaberpapier) | Pflicht, 1 bis 32 | Die zu behandelnden Zahlungen; Reihenfolge = Anzeigereihenfolge |
| `correlationId` | nein | UUID | Pflicht | Zuordnung des Rücksprungs, 15 Minuten, einmal verwendbar |
| `returnUri` | nein | `sgnl://taler-return` | Pflicht | Rücksprungziel, Taler prüft Schema und Host |
| `reason` | nein | `delete` oder `menu` | optional | Auslöser, nur für den Dialogtext („Nachricht gelöscht“ oder „Abbrechen“) |
| `isGroup` | nein | `true`/`false` | optional | Chat ist Gruppe (wie bei `compose-send`) |
| `recipientHint` | nein | Text, 1 bis 80 Zeichen | optional | Anzeigename Chat oder Gruppe (wie bei `compose-send`) |
| `memberCount` | nein | Ganzzahl ≥ 1 | optional | Nur bei `isGroup=true` (wie bei `compose-send`) |
| `isGroupSplit` | nein | `true`/`false` | optional | Nachricht war ein Gruppen-Split |
| `includeSelf` | nein | `true`/`false` | optional | Split: Sender hat sich mitgezählt |
| `splitCount` | nein | Ganzzahl | optional | Ursprüngliche Zahl der Anteile der Nachricht (kann größer sein als die Zahl der `uri`, weil nur noch offene eigene Anteile übergeben werden) |
| `currency` | nein | Währungscode (z. B. `KUDOS`) | optional | Währung des Splits |
| `totalAmount` | nein | Betragstext im Format des vorhandenen `talerPayment.totalAmount` | optional | Ursprünglicher Gesamtbetrag vor dem Split |
| `summary` | nein | Text, höchstens 200 Zeichen | optional | Verwendungszweck der Nachricht |
| `sentAt` | nein | Epoche in Millisekunden | optional | Sendezeitpunkt der Nachricht |

Format von `totalAmount`: Das vorhandene Proto-Feld `TalerPayment.totalAmount` ist ein `string`;
sein genaues Betragsformat ist im gelesenen Code nicht festgelegt **[UNSICHER]**. Die Umsetzung
muss dasselbe Format übernehmen und darf kein neues erfinden.

Bewusst **nicht** übertragen: Empfänger-ACIs, Telefonnummern, Nachrichten-IDs, Thread-IDs,
Nachrichtentext, Kontaktdaten aus Signal. Der Betrag pro Anteil fehlt in V1 absichtlich; Taler
kennt ihn aus der eigenen Transaktion.

Beispiel (gekürzt, Werte nicht prozentkodiert dargestellt):
```
talerlink://compose-abort?v=1&uri=taler://pay-push/ex.example/AAA…&uri=taler://pay-push/ex.example/BBB…
  &reason=delete&isGroup=true&recipientHint=Familie&memberCount=4&isGroupSplit=true&includeSelf=true
  &splitCount=4&currency=KUDOS&totalAmount=…&summary=Pizza&correlationId=<uuid>&returnUri=sgnl://taler-return
```

Grenzen: Taler verarbeitet höchstens 32 `uri`; mehr werden ignoriert und mit
`status`-Ergebnis `failed` (siehe 3.3) beantwortet. Signal baut bei mehr als 32 offenen Anteilen
Stapel zu je 32 und startet sie nacheinander (den nächsten erst nach dem Rücksprung des vorherigen).
Die Obergrenze 32 ist eine Annahme **[UNSICHER]**: Sie muss gegen die größte Gruppen-Split-Größe in
Signal und die Linklänge auf iOS geprüft werden (Frage 5). Doppelte `uri` werden von Taler
zusammengefasst.

### 3.2 Metadaten-Regeln

- **Nur Anzeigehilfe.** Taler zeigt nur an, was es selbst verifiziert hat. Es trifft keine
  Entscheidung (Betrag, Status, Abbruchfähigkeit) auf Grundlage eines Metadatenfelds.
- **Unbekannte Parameter** werden ignoriert, **ungültige Werte** (falscher Typ, zu lang, Zahl außerhalb
  des Bereichs) verwerfen nur dieses eine Feld. Fehlt `v`, gilt 1. `v` größer als das von Taler
  bekannte Maximum: trotzdem verarbeiten (alles Zusätzliche ist Anzeigehilfe), im Dialog aber nur
  Felder zeigen, die Taler kennt.
- **Abweichung zum verifizierten Wert:** Weicht ein Metadatenfeld (Betrag, Währung, Anzahl) von dem
  ab, was Taler aus den eigenen Transaktionen ermittelt, zeigt Taler **nur** den verifizierten Wert
  und blendet eine Warnung ein („Angaben von Signal weichen ab“). Die Aktion bleibt möglich, der
  Nutzer bestätigt weiterhin selbst.
- **Keine Geheimnisse.** Metadaten dürfen nichts enthalten, was ein Inhaberpapier ist oder eines
  offenlegt (keine Contract-Schlüssel, keine Teilstücke von URIs, keine Kontodaten). Die einzige
  Ausnahme sind die `uri`-Parameter selbst, die für die Aktion nötig sind.
- Feldlängen werden beim Senden gekürzt (`summary` auf 200 Zeichen, `recipientHint` auf 80), beim
  Empfang erneut begrenzt.

### 3.3 Rücksprung Taler an Signal

`sgnl://taler-return?correlationId=<echo>&status=<ready|cancelled>&result=<uri>|<status>&result=…`

- `status` verwendet den vorhandenen `ReturnStatus`: `ready` = Taler hat die Anfrage bearbeitet und
  liefert `result`-Einträge; `cancelled` = der Nutzer hat den Sammel-Dialog geschlossen, alle Anteile
  bleiben unverändert (`result` darf zusätzlich `declined` je URI enthalten).
- `result` ist wiederholt, **je URI ein Eintrag**, aufgebaut mit `appendQueryParameter`. Signal
  teilt am **ersten** `|` (URIs enthalten kein `|` als Trenner-Problem, weil Taler-URIs ihn nicht
  nutzen; das ist der Grund für „am ersten“). Unbekannte Statuswerte werden verworfen, ebenso
  `result`-Einträge, deren URI nicht zur `correlationId` gehört (Signal gleicht gegen die im Store
  gemerkte URI-Liste ab).
- `ReturnIntentSender` ruft heute `clearQuery()` und hängt nur `correlationId`, `status`, `talerUri`
  und `talerPaymentData` an; er braucht eine zusätzliche wiederholte Parameterliste.

Statuswerte je Anwendungsfall:

| Fall | Status je URI | Übernahme in Signal |
|---|---|---|
| `compose-abort` (Fälle 1 und 2) | `aborted` | `UNGUELTIG` |
| | `expired` | `ABGELAUFEN` |
| | `already_claimed` | keine erzwungene Änderung, `TalerUriRefreshJob` holt den echten Stand |
| | `declined` | keine Änderung, bleibt `OFFEN` |
| | `not_own` (neu, Erweiterung der Gap-A-Liste) | keine Änderung; die URI gehört keiner eigenen ausgehenden Zahlung in dieser Wallet |
| | `failed` (neu, Erweiterung) | keine Änderung; Abbruch technisch gescheitert (Netz, Backend) |
| `compose-accept` (V2, nur Vorschlag) | `accepted`, `declined`, `already_claimed`, `expired`, `failed` | `accepted` löst nur einen sofortigen Re-Check aus, der Status kommt aus der Verifikation |
| `compose-refund` (Mehrfach, nicht V1) | offen | |

`not_own` und `failed` sind gegenüber Gap A neu. Da Signal unbekannte Status verwirft, sind sie
für eine ältere Signal-Version unschädlich (Frage 2).

**Wichtig:** Der Status in `result` wird in Signal nie als Anzeigewert übernommen, sondern nur wie
oben in die Tabelle abgebildet. Der Rücksprung ist angreiferkontrolliert (exportierte Activity, siehe
Kommentar in `TalerReturnActivity`); ein `aborted` ohne belegten Zustand ist ein Vertrauensvorschuss.
Damit Signal nicht auf eine bloße Behauptung hin `UNGUELTIG` setzt, soll bei `aborted` zusätzlich ein
Re-Check per `TalerUriRefreshJob` laufen (Empfehlung, Frage 6).

### 3.4 Ablauf und Zustand auf Signal-Seite

1. Signal ermittelt die URIs (`showCancel` pro URI, wie heute) und legt einen
   `TalerCorrelationStore`-Eintrag mit Intent `ABORT` an. Der Eintrag muss künftig eine
   **Liste** von URIs tragen (heute `uri: String?`), sonst kann Signal Ergebnisse nicht abgleichen.
2. Signal startet den Link explizit an Taler. Schlägt `startActivity` fehl (Taler fehlt), gilt der
   Fallback aus Gap A (lokal `LOKAL_ABGEBROCHEN`).
3. Taler löst jede `uri` über `OwnUriTracker.transactionIdFor` auf die eigene Transaktion auf. Ob
   das für alle Fälle genügt, ist der offene Verifikationspunkt 2 der Gap-A-Spec **[UNSICHER]**.
4. Taler zeigt **einen** Sammel-Dialog („Zahlung stornieren?“ / „N offene Anteile stornieren?“), bei
   Bestätigung `abortTransaction` pro Transaktion.
5. Rücksprung nach 3.3. Kommt keiner, bleibt der Status `OFFEN`.

### 3.5 Fehlerfälle

| Fall | Verhalten |
|---|---|
| `correlationId` oder `returnUri` fehlt | Taler verwirft den Link (wie `composeSendFrom`), kein Rücksprung möglich |
| Keine gültige `uri` (leer, alle syntaktisch falsch) | Taler verwirft den Link, zeigt eine Fehlermeldung |
| Einzelne `uri` ungültig oder keine `pay-push` | Nur diese URI erhält `failed`; die übrigen laufen normal |
| Mehr als 32 `uri` | Überzählige URIs erhalten `failed` |
| URI ist nicht eigen | `not_own` |
| Purse abgelaufen | `expired` |
| Empfänger hat schon angenommen | `already_claimed` |
| Nutzer lehnt ab / schließt Dialog | `status=cancelled`, jede URI `declined` |
| Taler-Backend nicht bereit | Taler wartet auf die Initialisierung (wie bei `compose-send`, iOS-Paket T1 nennt dies „Warten auf Backend-Init“) |
| `correlationId` abgelaufen (mehr als 15 Minuten) oder schon benutzt | Signal verwirft den Rücksprung, keine Änderung |
| Rücksprung mit fremden URIs | Diese `result`-Einträge werden verworfen |

### 3.6 Kodierung

- Jeder Wert wird einzeln prozentkodiert. `#` in Taler-URIs (Fragment) muss als `%23` gesendet werden,
  sonst schneidet der Parser die URI ab.
- Leerzeichen und `+`: `Uri.getQueryParameter` auf Android decodiert `+` als Leerzeichen
  **[UNSICHER, vor Umsetzung mit einem Test belegen]**. Deshalb muss der Sender `+` als `%2B` kodieren.
  `URLQueryItem` auf iOS kodiert `+`, `&`, `=` und `#` in Werten nicht von selbst; die iOS-Umsetzung
  braucht einen eigenen erlaubten Zeichensatz (nur `A-Z a-z 0-9 - . _ ~` bleibt unkodiert).
- Wiederholte Parameter: Android liest sie mit `getQueryParameters("uri")`, iOS mit
  `queryItems.filter { $0.name == "uri" }`. Keine Komma-Trennung.
- Es gibt einen gemeinsamen Satz Testvektoren (siehe 5), der auch `+`, `#`, `|`, `,`, Umlaute und
  Emoji im `summary` abdeckt.

### 3.7 Verhalten, wenn Taler den Link nicht kennt

- **Android, ältere Taler-Version:** `MainActivity` kennt bisher nur die Hosts `compose-send` und
  `compose-refund`; alle anderen `talerlink://`-Links gehen in `emitUri` und damit nach
  `HandleUriScreen`, wo der `else`-Zweig „Unsupported URI“ zeigt und zurückspringt. Es entsteht
  kein Rücksprung; in Signal bleibt der Status `OFFEN`. Die Sicherheit ist gewahrt (es passiert
  nichts), der Nutzer erhält aber eine kryptische Meldung. Ob der Intent-Filter im Manifest den Host
  `compose-abort` überhaupt an Taler zustellt, ist nicht geprüft **[UNSICHER]**.
- **iOS:** Unbekannter Pfad bei `talerlink://` wird von der Taler-App nicht geroutet; Verhalten je
  nach Umsetzung von T1 (Zielbild: verwerfen ohne Rücksprung).
- **Signal darf nicht raten.** Auf Android kann Signal `versionCode` des Taler-Packages lesen und die
  Aktion erst ab einer Mindestversion anbieten (`getPackageInfo`, Package-Sichtbarkeit nötig, siehe
  Frage 4). Auf iOS gibt es das nicht; dort bleibt nur der Fallback (kein Rücksprung, `OFFEN`, nach 15
  Minuten läuft die `correlationId` ab). Beide Apps sind Forks mit gemeinsamer Auslieferung, der
  Versionsunterschied ist daher ein Randfall.
- **Umgekehrt** (ältere Signal-Version): sendet den Link gar nicht; unproblematisch.

### 3.8 Sicherheitsregeln

1. **Inhaberpapier:** Die `uri`-Werte sind Zahlungs-URIs. Sie werden nie geloggt, auch nicht gekürzt
   (nur `TalerCorrelation.shortHash`), nie in Crash-Reports, nie in Analytics. Das gilt für Signal,
   Taler und beide Plattformen, und ebenso für die `result`-Einträge im Rücksprung.
2. **Keine Zusatzgeheimnisse in Metadaten** (siehe 3.2).
3. **Verifizierte Werte gewinnen** (Regel 5 des Zielbilds); bei Abweichung Warnung, nicht stilles
   Überschreiben in der Anzeige.
4. **Signal bewegt kein Geld.** Der Abbruch geschieht ausschließlich nach Bestätigung im Taler-Dialog.
5. **Android:** Explizite Intents (`setPackage`), Rücksprung mit Prüfung von Schema, Host und
   Signing-Zertifikat (`ReturnIntentSender`, `CallerVerification`); die Aufrufer-Signatur wird nicht
   aufgeweicht.
6. **iOS: Restrisiko Scheme-Übernahme.** Ein Custom Scheme lässt sich auf iOS von jeder App
   registrieren, es gibt keine Zuordnung zu einem Empfänger. Da der Link nun bis zu 32 Inhaberpapiere
   in einem Rutsch trägt, wächst der Schaden eines Abfangens. Der iOS-Rahmen (`talerlink://`, ohne
   HMAC) ist vorgegeben; das Risiko ist damit bekannt und nicht durch diese Spec lösbar. Zu prüfen
   wäre, ob `compose-abort` ohne den geheimen Teil der URI auskäme **[UNSICHER]**: `OwnUriTracker`
   sucht heute mit der vollständigen URI (siehe Frage 7).
7. **Rücksprung-Parameter des Links** (`returnUri`) sind angreiferkontrolliert; die bestehende
   Schema-/Host-Prüfung und `clearQuery()` in `ReturnIntentSender` bleiben unverändert.

## 4. Auswirkungen auf die Plattformen

### Signal Android
- Neuer Linkbau für `compose-abort` (sinnvoll in einem eigenen `TalerLinks`-Objekt, wie es das
  iOS-Paket S1 für iOS vorsieht), Aufruf aus dem „Für alle löschen“-Zweig von `DeleteDialog` und aus
  `TalerMenuActions.onCancelFromMenu` (nur bei mehr als einer URI).
- `TalerCorrelationIntent.ABORT` und ein Store-Eintrag mit URI-Liste.
- `TalerReturnActivity`: Verzweigung für `ABORT`, Parser für wiederholtes `result`, Abgleich gegen
  die URI-Liste des Eintrags, Übernahme laut 3.3.
- Reine Logik ohne Android-Abhängigkeit (Parser, Status-Mapping), damit JVM-Tests genügen.
- Alle sichtbaren Texte mit Präfix `TalerFork_` in `strings.xml`.

### Taler Android
- `MainActivity`: Host `compose-abort` (Routentyp wie `ComposeRefund`, ein Einzelinstanz-Mechanismus).
- `ComposeAbortScreen` mit einem Sammel-Dialog, Auflösung über `OwnUriTracker`, `abortTransaction`
  pro Transaktion, Anzeige verifizierter Werte und Abweichungswarnung.
- `ReturnIntentSender`: wiederholte `result`-Parameter.
- Bisheriger `taler://`-Annehmen/Abbrechen-Pfad für eine einzelne URI bleibt unverändert.

### Signal iOS und Taler iOS
- Beide bauen und parsen dasselbe Schema (`TalerLinks`, `ReturnURLBuilder`, Request-Parser aus den
  iOS-Paketen S1 und T1). `correlationId` 15 Minuten, einmal verwendbar, Rücksprung
  `sgnl://taler-return`.
- Eigene Prozentkodierung (3.6); `LSApplicationQueriesSchemes` nur, falls Signal die Erreichbarkeit
  prüfen will **[UNSICHER]**.

### Signal Desktop
Nicht betroffen (kein Taler-Deep-Link in dieser Spec).

## 5. Teststrategie

- **Gemeinsame Testvektoren** (ein Textfile mit Eingabe und erwartetem Link/Rücksprung), von allen
  vier Apps gelesen: 1 URI, 3 URIs, 32 URIs, 33 URIs, URI mit `+`, `#`, `,`, `|`, Umlaut, Emoji im
  `summary`, fehlendes `v`, `v=2` mit unbekanntem Feld, fehlerhafter Wert (z. B. `memberCount=abc`),
  doppelte `uri`.
- **Signal (JVM, ohne Mocking-Framework):** Linkbau, `result`-Parser (am ersten `|` geteilt,
  unbekannter Status verworfen, fremde URI verworfen), Status-Mapping, Store (15 Minuten,
  einmalig, mit Liste).
- **Taler (JVM):** Request-Parser, Grenzen (32/33), Abweichungserkennung Metadaten zu verifizierten
  Werten, Aufbau des Rücksprungs.
- **Manuell**: die sieben Fälle aus der
  Gap-A-Spec plus ein Test mit einer älteren Taler-Version (Fall 3.7) und ein Test mit 30 Anteilen auf
  iOS (Länge).
- **Kompatibilitätstest:** neuer Signal gegen alter Taler, alter Signal gegen neuer Taler.

## 6. Entscheidungen für den Nutzer

1. **Zielbild gegen Gap-A-Spec:** Soll `compose-abort` mit wiederholtem `uri` und `result` gebaut
   werden (Zielbild 5.2) und die Gap-A-Spec/der Gap-A-Plan (`uris=…kommagetrennt`, `results=…`)
   entsprechend korrigiert werden? *Empfehlung: ja.*
2. **Neue Statuswerte `not_own` und `failed`** für `compose-abort` (Erweiterung der Gap-A-Liste
   `aborted/already_claimed/expired/declined`)? *Empfehlung: ja, ältere Signal-Versionen verwerfen
   unbekannte Werte ohnehin.*
3. **Menü-„Abbrechen“ bei mehreren eigenen Anteilen** ebenfalls über `compose-abort` (`reason=menu`)
   statt Schleife mit mehreren `startActivity`? *Empfehlung: ja, ab zwei URIs; bei einer URI bleibt der
   heutige Link.*
4. **Mindestversion prüfen:** Soll Signal Android vor dem Anbieten den `versionCode` von Taler prüfen
   (braucht Package-Sichtbarkeit im Manifest)? *Empfehlung: nein für V1, der Fallback (nichts passiert,
   Status bleibt `OFFEN`) genügt bei gemeinsamer Auslieferung.*
5. **Obergrenze der URIs pro Link:** 32 mit Stapelbildung? *Empfehlung: ja, vorher auf einem iOS-Gerät
   mit 30 URIs die Linklänge messen.*
6. **Abbruch-Ergebnis verifizieren:** Signal setzt bei `aborted` nicht sofort `UNGUELTIG`, sondern
   löst zusätzlich einen `TalerUriRefreshJob` aus und übernimmt erst dessen Ergebnis? *Empfehlung: ja
   (ein `aborted` im Rücksprung ist ohne Beleg nur eine Behauptung; Kosten sind ein Poll).*
7. **iOS-Scheme-Risiko:** Akzeptierst du, dass auf iOS bis zu 32 Zahlungs-URIs über ein nicht
   exklusives Custom Scheme laufen, oder soll geprüft werden, ob der Abbruch ohne den geheimen
   Teil der URI auskommt? *Empfehlung: Prüfung anstoßen, bis dahin akzeptieren (Rahmen ist vorgegeben).*
8. **Version 2:** `compose-accept` (Sammel-Annehmen) und Mehrfach-`compose-refund` eigene Specs
   später schreiben? *Empfehlung: ja, erst nach V1 und nach Klärung, ob wallet-core parallele
   `preparePeerPushCredit` sauber unterstützt.*
9. **Metadaten pro URI** (Betrag je Anteil) jetzt oder später? *Empfehlung: später; V1 kommt mit
   `totalAmount`, `splitCount` und der eigenen Verifikation von Taler aus.*
