# Android-Nachzieh-Liste

Stand: 2026-09-29. Was Android (`signal-android` und `taler-android`, Branch
`gnu-fork`) übernehmen oder anpassen muss, damit die Verträge in diesem Ordner
gelten. Jede Aussage wurde gegen den Android-Code geprüft (Datei:Zeile), nicht
nur aus der Doku übernommen. Nichts davon wurde zur Laufzeit ausgeführt; wo
das relevant ist, steht "nicht zur Laufzeit geprüft".

Priorität: **P1** Fehler oder Sicherheitsrisiko, vor jeder iOS-Interop
beheben. **P2** nötig, damit der Vertrag gilt (Parität). **P3** Härtung oder
Kosmetik.

Typ: **Neu** (Funktion fehlt), **Anpassung** (vorhanden, muss geändert werden),
**Abweichung** (Code und Doku widersprechen sich; Code ist der Ist-Stand).

Pfade: Signal = `signal-android/app/src/main/java/org/thoughtcrime/securesms/`,
Taler = `taler-android/wallet/src/main/java/net/taler/wallet/`.

## 1. Übersicht

| ID | Prio | Typ | Thema | Vertrag |
|---|---|---|---|---|
| N1 | P2 | Neu | Taler-Android nimmt `talerlink://pay-push` und `pay-pull` an | `link-protokoll.md` 2.1, 6 |
| N2 | P1 | Abweichung | Aktionslink-Öffnen ohne Fehlerabfang | `link-protokoll.md` 6 |
| N3 | P2 | Neu | Taler-Tab in der Medienübersicht (Zielbild 6.1) | `entscheidungen.md` E11 |
| N4 | P1 | Anpassung | `talerPaymentData` tolerant lesen (`ignoreUnknownKeys`) | `datenmodell.md` 2 |
| N5 | P1 | Abweichung | URI-Art im JSON-Sendepfad nicht geprüft | `link-protokoll.md` 3, 10 |
| N6 | P2 | Abweichung | Bestätigungsnachricht lokalisiert statt fest englisch | `entscheidungen.md` E13 |
| N7 | P2 | Neu | `status_changed_at` (Spalte, Migration, Schreibpfade) | `datenmodell.md` 5.2 |
| N8 | P3 | Abweichung | Zielbild 4.11/Regel 7: "Aufrufer-Signatur wird geprüft" stimmt für Signal nicht | `link-protokoll.md` 2.5 |
| N9 | P3 | Abweichung | Kleinere Lesetoleranzen (`direction`, leere Strings, Duplikate, `returnUri`) | `link-protokoll.md` 2.3, 3, 8 |
| N10 | P2 | Neu | compose-abort (Gap A): Signal- und Taler-Seite, `ABORT`, `result=`-Parser | `link-protokoll.md` 5, 9 |
| N11 | P2 | Abweichung | Menüaktionen feuern pro URI einen eigenen Intent | `link-protokoll.md` 5 |
| N12 | P3 | Neu | Multi-URI-Link (Zielbild 5.2) | `spec-multi-uri-link.md` (in Arbeit, D2) |
| N13 | P3 | Offen | pay-pull: Aktionslink und Annehmen-Knopf | `link-protokoll.md` 6 |
| N14 | P3 | Abweichung | Doku: Gap-A-Spec gegen Plan/Zielbild (Encoding, Fallback) | `link-protokoll.md` 5 |
| N15 | P1 | Abweichung | `OwnUriTracker` speichert Klartext-URIs (Inhaberpapier) als SharedPreferences-Schlüssel | `datenmodell.md`, Regel 4 |
| N16 | P2 | Neu | compose-abort: `declined` auch beim Schließen ohne Entscheidung und für fremde URIs, erledigte Transaktionen nicht erneut abbrechen | `link-protokoll.md` 5 |
| N17 | P2 | Offen | Persistenter Correlation-Store für SEND/REFUND (Signal-Prozess-Tod während Taler-Besuch) | `link-protokoll.md` 9 |
| N18 | P3 | Offen | Bestätigungsnachricht bei mehreren eigenen Geräten mehrfach möglich | `entscheidungen.md` |

## 2. Details

### N1 Taler-Android nimmt `talerlink://pay-push` und `pay-pull` an (P2, Neu)

Vertrag: iOS sendet Annehmen/Abbrechen als `talerlink://pay-push/<rest>?correlationId=&returnUri=`.
Damit Android später dieselben Links verarbeiten kann (und ein einheitlicher
Vertrag gilt), soll Taler-Android sie annehmen.

Befund im Code:

- Manifest: `MainActivity` registriert nur `taler`, `TALER`, `ext+taler`, `EXT+TALER`,
  `payto` (`taler-android/wallet/src/main/AndroidManifest.xml:76-85`). Ein Filter
  für `talerlink` fehlt. Die compose-Links funktionieren nur, weil Signal sie
  explizit per `setClassName` an die Activity schickt.
- `MainActivity.handleIntents` behandelt `talerlink` nur mit den Hosts
  `compose-send` und `compose-refund` (`MainActivity.kt:437-442`). Alles andere
  geht als Rohstring an `emitUri`.
- `HandleUriScreen` kennt nur die Präfixe `taler://`, `ext+taler://`,
  `taler+http://` (`HandleUriScreen.kt:62-73`). Ein `talerlink://pay-push/...`
  würde als unbekannte URI enden (welche Fehlermeldung, nicht zur Laufzeit
  geprüft).

Aufgabe:

1. In `MainActivity.handleIntents`: bei Scheme `talerlink` und Host `pay-push`/`pay-pull`
   das Scheme auf `taler` zurückschreiben und wie bisher an `emitUri`/`HandleUriScreen`
   geben (die Query mit `correlationId`/`returnUri` liest `ReturnCallbackParams.extract`
   danach ohnehin).
2. Optional Intent-Filter für `talerlink` (für implizite Intents) ergänzen,
   oder bewusst bei "nur explizit adressiert" bleiben (Android-Sicherheitsmodell).
   [Offen: Nutzerentscheidung]
3. Optional: Signal-Android sendet Aktionslinks künftig ebenfalls als
   `talerlink://` (heute `taler://` mit `setPackage`, `TalerAcceptRejectActions.kt:32-37`,
   `:79-83`). Nicht nötig, solange `setPackage` greift.

### N2 Aktionslink-Öffnen ohne Fehlerabfang (P1, Abweichung)

Zielbild 5.1 sagt: "Alle Intents an Taler: `ACTION_VIEW` + `setPackage`". Das
stimmt, aber Annehmen und Abbrechen unterscheiden sich von Senden/Refund:

- `TalerSendActions.kt:62` und `TalerRefundActions.kt:71` kapseln `startActivity` in
  `runCatching` (stiller Abbruch).
- `TalerAcceptRejectActions.kt:38` (`onAcceptClicked`) und `:84` (`onCancelClicked`)
  rufen `context.startActivity(intent)` **ohne** Abfang. Bei nicht installiertem
  Taler wirft ein expliziter Intent `ActivityNotFoundException`.
- Die Karte zeigt "Annehmen" ohne Prüfung, ob Taler installiert ist
  (`TalerCardActionGate.showAccept` prüft nur Status, Art, Eigenschaft;
  `TalerInstallation.isInstalled/isTrusted` wird nur im Anhang-Menü
  `AttachmentKeyboardFragment.kt:158` und in `TalerConnectionTestRow.kt:28-29`
  benutzt).

Nicht zur Laufzeit geprüft, aber aus dem Code eindeutig. Aufgabe: `runCatching`
wie bei Send/Refund, Hinweis an den Nutzer statt stiller Ausfall (Vertrag:
kein Absturz, kein Statuswechsel). Zusätzlich `setClassName` ergänzen, damit
alle Intents an Taler gleich adressiert sind (optional, `setPackage` genügt).

### N3 Taler-Tab in der Medienübersicht (P2, Neu)

Zielbild 6.1, Status [TEILWEISE]: Logik fertig (`TalerThreadSummary.kt`:
`aggregate`, `headline`, `latestOf`, Commit `bcb44525c7`). Es fehlen Tab, View,
Filter-Chips (Alle/Offen/Erhalten/Gesendet), Liste, die asynchrone
Datenladung, und die Entfernung der Blöcke "Payments" und "Zahlungshistorie"
aus den Chat-Einstellungen. Die globale Payment History
(`payments/history/PaymentHistoryFragment.kt`, ruft `TalerRefundActions.onRefundClicked`
auf, `:105`) entfällt laut E11 nach dem Umbau [Offen: Nutzer bestätigt].
Abhängigkeit: N7 (`statusChangedAt`) für "Letzter Vorgang" nach Abschluss;
`TalerThreadSummary.latestOf` sortiert heute nach `createdAt` (`:118-119`).
Vertrag: Kopfzeile, Rangfolge und Filter gemäß Zielbild 6.1; `latestActivity =
statusChangedAt ?? createdAt` (`datenmodell.md` 5.2).

### N4 `talerPaymentData` tolerant lesen (P1, Anpassung)

Befund: Signal parst das JSON ohne `ignoreUnknownKeys`
(`TalerReturnActivity.kt:92`, `TalerPaymentData.kt:92`, `:101`;
`Json.decodeFromString` mit Standardkonfiguration wirft bei unbekannten Feldern
`SerializationException`). Die Regel "nur additiv erweitern" (README) gilt für
Link-Parameter, aber jedes neue JSON-Feld würde Android brechen: im Rücksprung
Rückfall auf `talerUri` (ohne Split-Metadaten), beim Body-Lesen Rückfall auf die
Regex. iOS ignoriert unbekannte Felder.

Aufgabe: `Json { ignoreUnknownKeys = true }` an allen Lesestellen (auch in
`taler-android`, sofern dort gelesen wird). Vorbedingung für den Multi-URI-Link
(N12), falls dort JSON-Metadaten reisen.

### N5 URI-Art im JSON-Sendepfad nicht geprüft (P1, Abweichung)

Der Einzel-URI-Pfad verlangt `classify` = `PAY_PUSH` oder `PAY_PULL`
(`TalerReturnActivity.kt:224-225`). Der `talerPaymentData`-Pfad prüft nur
`classify != null` (`:270`) und lässt damit auch `PAY`, `WITHDRAW`, `REFUND`
durch. Der grobe Vorfilter davor (`isExactlyOneUri`, `:108`) akzeptiert auch
`payto://` und `ext+taler://` (`TalerUriDetector.kt:18`), `classify` lehnt dann
`payto://` ab (`TalerUriParser.kt:34-41`). Ein manipulierter Rücksprung kann so eine
`taler://withdraw/...`-URI als Nachricht in den offenen Chat schicken (mit
gültiger correlationId und innerhalb der TTL). Die Kommentare bei `:106` und `:139`
nennen noch die alte "previewForUri"-Prüfung, die es seit der AIDL-Entfernung
nicht mehr gibt.

Aufgabe: im JSON-Pfad zusätzlich `PAY_PUSH`/`PAY_PULL` verlangen (Vertrag
`link-protokoll.md` Abschnitt 3, Regel 3 und Abschnitt 10).

### N6 Bestätigungsnachricht lokalisiert (P2, Abweichung)

Befund:

- Sender: `TalerUriRefreshJob.kt:149-150` erzeugt `context.getString(
  R.string.TalerFork_accept_confirmation_message, kindLabel, uri)` in der Sprache
  des Senders. Bedingungen: `previous == OFFEN`, `new == ANGENOMMEN`, `PAY_PUSH`,
  `!isOwnPayment`, 1:1-Chat (`:140-147`).
- Empfänger: `TalerConfirmationDetector.kt:38-47` vergleicht den Volltext mit den
  Strings **des Empfängers** (englisch: `strings.xml:10097`; deutsch:
  `values-de/strings.xml:10060` "Zahlung für %1$s akzeptiert (%2$s)", Labels
  `:10014-10015`). Sprachen unterschiedlich -> nicht erkannt.
- Die Zielbild-Doku erwähnt das nicht. Der Parity-Plan nennt es unter "Android-Unklarheiten".

Aufgabe: feste englische Fassung senden (E13) **und** beim Erkennen die
englische Fassung zusätzlich zur lokalisierten akzeptieren (Übergang). Vertrag:
`entscheidungen.md` E13. [Offen: sprachneutrale Lösung per Proto]

### N7 `status_changed_at` (P2, Neu)

Spec: `datenmodell.md` 5.2. Aufgabe auf Android:

1. Migration (neue `V4xx`): `ALTER TABLE taler_payment ADD COLUMN status_changed_at INTEGER`.
   `CREATE_TABLE` (`TalerPaymentTable.kt:67-83`) und `readRecord` (`:87-`)
   entsprechend anpassen, dabei wie bei `V323` vorgehen (`consecutive_failures`
   kam ebenfalls nachträglich). Kein Backfill.
2. `TalerPaymentRecord` (`TalerPaymentRecord.kt`) um `statusChangedAt: Long?` erweitern.
3. Schreibpfade: `applyPreviewAndRecordTransition` (`TalerPaymentTable.kt:201`) und
   `updateStatus` (`:268`) setzen die Spalte genau bei `neu != alt` und tatsächlichem
   Schreiben (Schutz lokaler Endzustände respektieren).
   `upsertDetected` (`:114`) und `recordFailure` (`:298`) setzen sie nicht.
   `updateFromPreview` (`:128`) hat keine Aufrufer (nur Kommentare): entfernen oder
   anpassen.
4. `TalerThreadSummary.latestOf` auf `statusChangedAt ?: createdAt` umstellen
   (`:118-119`), Tests ergänzen (`TalerThreadSummaryTest`).
5. Test: OFFEN -> ANGENOMMEN setzt die Spalte, gleicher Status nicht, blockierter
   Wechsel aus lokalem Endzustand nicht, Erkennung `NULL`, Fallback auf `createdAt`.

### N8 Zielbild 4.11 und Regel 7: Aufrufer-Signatur (P3, Abweichung)

Zielbild 4.11 sagt: "Die Aufrufer-Signatur wird geprüft." Im Code ist das für
Signal nicht so: `TalerReturnActivity` liest nur `correlationId` und prüft keinen
Aufrufer (kein `getCallingPackage`, keine Referrer-Prüfung, kein Aufruf von
`CallerVerification`; `TalerReturnActivity.kt:39-172`). Geprüft wird auf der
**Taler-Seite**, an wen der Rücksprung geht (`ReturnIntentSender.kt:63-76`,
`AllowedCallers`, `CallerVerification`). Signal-seitig trägt allein die
correlationId (15 min, single-use). `TalerAllowlist.CERT_SHA256` in Signal dient
nur der Sichtbarkeit des Anhang-Buttons und der Einstellungszeile
(`TalerInstallation.isTrusted`). Aufgabe: Zielbild und Regel 7 korrigieren
("Signaturprüfung des Rücksprung-**Ziels** in Taler"). Der Vertrag beschreibt
den tatsächlichen Stand (`link-protokoll.md` 2.5).

### N9 Kleinere Abweichungen (P3, Abweichung)

| Was | Ist (Datei:Zeile) | Vertrag |
|---|---|---|
| `direction` akzeptiert jeden `TalerUriKind`-Namen (`PAY`, `WITHDRAW`, `REFUND`) | `MainActivity.kt:473-476` | nur `PAY_PUSH`/`PAY_PULL`, sonst `PAY_PUSH`. Folgeverhalten von `ComposeSendScreen` bei `WITHDRAW` nicht geprüft |
| leere `correlationId`/`returnUri` werden angenommen (nur null wird verworfen) | `MainActivity.kt:471-472`, `:489-491` | Pflicht, nicht leer; ein leerer Wert führt zum Verwerfen |
| `ReturnCallbackParams.extract`: bei doppeltem Parameter gewinnt der **letzte** (`toMap()`), überall sonst der **erste** (`Uri.getQueryParameter`) | `ReturnCallbackParams.kt:33-39` | erster Wert gewinnt |
| `returnUri`-Prüfung nur `scheme` und `host` per `Uri.parse`; User-Info, Port und Pfad werden nicht ausgeschlossen (die Query wird danach verworfen) | `ReturnIntentSender.kt:60-61` | iOS prüft zusätzlich kein User/Passwort, kein Port, leerer Pfad (T1); Android angleichen (P3, das Ziel ist ohnehin auf das Signal-Package beschränkt) |
| Abbrechen-Rücksprung liefert `status=ready` immer beim Verlassen, auch ohne Abbruch | `TransactionDetailScreen.kt:141-149` | Signal ignoriert `status` bei `ACCEPT_OR_CANCEL`; im Vertrag festgehalten, keine Änderung nötig |
| `returnUri` mit falschem Scheme: compose-send wird angenommen, Zahlung kann committet werden, aber kein Rücksprung | `ReturnIntentSender.kt:61`, `MainActivity.kt:471-472` | [Offen: Link schon beim Öffnen verwerfen] |

### N10 compose-abort, Gap A (P2, Neu)

Auf Android existiert nichts davon (`grep`: kein `compose-abort`, kein
`ABORT`). Ist-Stand: `TalerAcceptRejectActions.cancelCancelablePaymentsForDeletedMessages`
(`:115-125`) setzt bei **jeder** Löschung (beide Varianten, Aufruf
`ConversationFragment.kt:3288` im gemeinsamen `onSuccess`-Callback von
`DeleteDialog.show(...)`) nur lokal `LOKAL_ABGEBROCHEN` plus Statuszeile.
Aufgaben laut Plan `docs/superpowers/plans/2026-09-28-taler-payment-delete-abort.md`
und Vertrag:

Signal:
1. `TalerCorrelationIntent.ABORT` (`TalerCorrelationStore.kt:17`), `Entry.uris`.
2. Neue `TalerAbortActions` (Link bauen gemäß `link-protokoll.md` Abschnitt 5,
   wiederholtes `uri` per `appendQueryParameter`).
3. `TalerReturnActivity`: `when (entry.intent)` um `ABORT` erweitern (`:68`),
   `getQueryParameters("result")`, Teilung am ersten `|`, Filter gegen `entry.uris`,
   Mapping `aborted -> UNGUELTIG`, `expired -> ABGELAUFEN`, sonst keine Änderung
   plus Fast-Poll.
4. Die beiden Lösch-Zweige trennen: nur "Für alle löschen" (`DeleteDialog`)
   löst den Link aus; "Für mich löschen" bleibt beim lokalen Verhalten. Heute laufen
   beide in denselben Callback (Spec, Offener Punkt 3).
5. Fallback: Öffnen scheitert -> lokal `LOKAL_ABGEBROCHEN` (heutiges Verhalten).

Taler:
1. `WalletDestination.ComposeAbort` und Parser in `MainActivity.handleIntents`
   (neben `compose-refund`, `:438-441`).
2. `ComposeAbortScreen` mit Sammel-Dialog. Auflösung der URI über
   `OwnUriTracker.transactionIdFor` (Verifikationspunkt der Spec: ob das für extern
   hereinkommende URIs ausreicht, ist nicht geprüft).
3. `abortTransaction` pro Transaktion; Ergebnisse `aborted`/`already_claimed`/
   `expired`/`declined`.
4. `ReturnIntentSender.fireAbort` (Query neu aufbauen, `correlationId` plus je URI
   ein `result`).

Offen: Verhalten bei "kein Rücksprung" (Spec: `LOKAL_ABGEBROCHEN`, Zielbild:
`OFFEN`), siehe N14.

### N11 Menüaktionen feuern pro URI einen eigenen Intent (P2, Abweichung)

`TalerMenuActions.onCancelFromMenu` und `onRefundFromMenu` rufen für jede URI
einer Gruppenkarte `startActivity` (`TalerMenuActions.kt:39-43`, `:51-60`). Der
Kommentar in `TalerAcceptRejectActions.kt:107-111` benennt selbst, dass bei
mehreren Intents nur der zuletzt gestartete zuverlässig ankommt. Damit sind
"Abbrechen" (mehrere eigene offene Anteile) und "Rückerstatten" (mehrere
beanspruchte Anteile) bei Gruppen-Splits nur teilweise wirksam. Für den
Abbruch löst N10 (ein Sammel-Link) das Problem; für "Rückerstatten" und
"Abbrechen aus dem Menü" (nicht nur beim Löschen) bleibt es offen.
[Offen: Sammel-Aktion für Menü-Abbrechen und Rückerstatten]

### N12 Multi-URI-Link (P3, Neu)

Zielbild 5.2. Spec kommt in Paket D2 (`spec-multi-uri-link.md`, in Arbeit),
danach Freigabe durch den Nutzer. Abhängigkeit: N4 (falls JSON-Metadaten),
N10 (Muster `result=`).

### N13 pay-pull (P3, Offen)

- Signal-Android sendet keinen Annehmen-Link für `pay-pull`: `showAccept` verlangt
  `PAY_PUSH` (`TalerCardActionGate.kt:22-25`; Kommentar: "der Taler-seitige
  Rücksprung-Mechanismus ist bisher nur dafür Ende-zu-Ende verdrahtet").
- Taler unterstützt den Rücksprung für `pay-pull` bereits
  (`HandleUriScreen.kt:119-131`, `IncomingPullPaymentScreen.kt:88`, `:112`).
- Absicht oder Lücke? Im Parity-Plan als Android-Unklarheit geführt. iOS
  übernimmt heute dasselbe Gate. [Offen: Nutzer entscheidet]

### N14 Gap-A-Spec gegen Plan und Zielbild (P3, Abweichung, Doku)

| Punkt | Spec (`...-design.md`) | Plan (`...-delete-abort.md` Z. 16-17), Zielbild 6.2 | Vertrag |
|---|---|---|---|
| Signal -> Taler | `uris=<kommagetrennt>` | wiederholtes `uri=` | wiederholtes `uri=` |
| Taler -> Signal | `results=<uri>:<status>,...` | wiederholtes `result=<uri>\|<status>`, Teilung am ersten `\|` | Plan/Zielbild |
| Kein Rücksprung | `LOKAL_ABGEBROCHEN` | Zielbild: bleibt `OFFEN` | Zielbild (offen) |

Die Spec selbst verweist beim Encoding auf den Implementierungsplan. Aufgabe:
Spec-Abschnitte "Deep-Link-Flow" und "Fallback" nachziehen oder als überholt
markieren; Nutzerentscheidung zum Fallback einholen.


### N15 `OwnUriTracker` speichert Klartext-URIs (P1, Abweichung)
**Ist Android:** `taler-android/.../link/OwnUriTracker.kt:79` `prefs.edit().putString(uri, transactionId)`. Die volle
`taler://pay-push/...`-URI (Inhaberpapier, Regel 4) liegt als Schlüssel in `taler_link_own_uris`.
**iOS (T3, Review-Fix):** `OwnUriStore` speichert nur den SHA-256-Hash der URI als Schlüssel. `SentRefundStore` (T4)
nutzt ebenfalls einen Hash.
**Nachzug:** Den Schlüssel auf SHA-256(URI) umstellen und bestehende Einträge migrieren. `isOwn`/`transactionIdFor`
hashen die Eingabe vor dem Nachschlagen.

### N16 compose-abort: Ergebnis für jede URI (P2, Neu)
iOS T5 setzt den Vertrag so um:
- Jede Eingangs-URI bekommt genau ein `result`.
- Schließt der Nutzer den Dialog ohne Entscheidung, oder ist die URI keine eigene: `declined`.
- Bereits `done`/`expired`/`aborted` gewordene Transaktionen werden nicht erneut abgebrochen, sondern direkt als
  `already_claimed`/`expired`/`aborted` gemeldet.
Taler-Android übernimmt das mit N10.

### N17 Persistenter Correlation-Store (P2, Offen)
Beide Plattformen halten Korrelationen nur im Speicher. Wird Signal beendet, während der Nutzer in Taler eine Zahlung
erstellt, verwirft Signal den Rücksprung. Die Zahlung existiert dann in Taler, aber im Chat gibt es keine Nachricht.
Vorschlag für beide Plattformen: SEND/REFUND persistent mit TTL 15 min. Nutzerentscheidung offen.

### N18 Bestätigungsnachricht und mehrere eigene Geräte (P3, Offen)
Jedes eigene Gerät pollt die URI und sieht den Übergang zu `ANGENOMMEN` selbst. Die Deduplizierung wirkt nur auf dem
jeweiligen Gerät, iOS und Android verhalten sich hier gleich. Eine saubere Lösung wäre eine geräteübergreifende
Kennzeichnung, etwa über ein Proto-Feld statt eines erkannten Textes. Hängt mit N6 zusammen (sprachneutrale Bestätigung).

## 3. Nicht-Abweichungen (geprüft, stimmt mit dem Zielbild)

- compose-send: Parameter und Reihenfolge (`TalerSendActions.kt:37-51`), `memberCount`
  nur bei Gruppe, `setClassName` plus `setPackage` (`:53-56`).
- compose-refund: `originalUri`, `correlationId`, `returnUri` (`TalerRefundActions.kt:57-63`).
- Aktionslink: `?` bzw. `&`, `Uri.encode` für beide Werte (`TalerAcceptRejectActions.kt:32-33`).
- Rücksprung: Query wird neu aufgebaut (`ReturnIntentSender.kt:88-94`), Ziel-Scheme und
  -Host geprüft (`:60-61`), Signing-Cert per Allowlist (`:63-76`).
- `TalerCorrelationStore`: TTL 15 min, `take` single-use, unbekannt/abgelaufen -> null
  (`TalerCorrelationStore.kt:65-83`).
- Return-Activity: `isHierarchical`-Guard und `try/finally { finish() }`
  (`TalerReturnActivity.kt:52-54`, `:171-173`).
- `TalerPaymentData`-JSON und Proto-Feld 9000 (`TalerPaymentData.kt:41-62`,
  `SignalService.proto:247-253`, `:465`).
- Lese-Reihenfolge `urisFromMessageBody` (`TalerPaymentData.kt:99-112`).
- Status und Gates (`TalerPaymentStatus.kt`, `TalerCardActionGate.kt`).
