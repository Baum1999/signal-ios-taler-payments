# Entscheidungen (ADR-Log)

Stand: 2026-09-29. Jede Entscheidung: Kontext, Entscheidung, Alternativen,
Folgen. E1 bis E8 stammen aus dem Parity-Plan (`2026-09-28-ios-android-parity.md`,
Abschnitt 5) und sind hier auf den Stand nach den Nutzerentscheidungen vom
2026-09-29 gebracht. E9 und folgende sind neu.

Status: **gilt** = beschlossen, **gilt (aktualisiert)** = Inhalt gegenüber dem
Parity-Plan geändert, **offen** = noch zu entscheiden.

| ID | Titel | Status |
|---|---|---|
| E1 | Krypto vor Karte | gilt, umgesetzt (M1, M2) |
| E2 | `talerlink://` für alle Links Signal -> Taler auf iOS | gilt (aktualisiert, Nutzer 2026-09-29) |
| E3 | Rücksprung über `sgnl://taler-return` | gilt |
| E4 | CryptoKit plus schmale Eigenimplementierung | gilt |
| E5 | Seitentabelle statt SDS-Feld | gilt |
| E6 | Polling als Actor/Manager statt JobQueue | gilt |
| E7 | Lokale Statuszeilen | gilt (Variante A, umgesetzt in S6) |
| E8 | Keine Allowlist/Cert-Prüfung auf iOS | gilt |
| E9 | Kein HMAC beim Rücksprung | gilt (Nutzer 2026-09-29) |
| E10 | `statusChangedAt` als neue Migration | gilt |
| E11 | Taler-Tab ersetzt die Einstellungsblöcke | gilt |
| E12 | taler-ios: Code im synchronisierten Ordner mit `#if TALER_SIGNAL` | gilt |
| E13 | Bestätigungsnachricht: englischer Wortlaut fest | gilt vorläufig, Android-Unklarheit offen |
| E14 | Wiederholte Parameter und `result` am ersten `\|` | gilt |
| E15 | Gap A: Fallback und "kein Rücksprung" | teilweise offen |

---

## E1 Krypto vor Karte

**Kontext.** Die Zahlungskarte braucht Betrag, Richtung und Status. Seit der
AIDL-Entfernung liefert diese Daten nicht mehr die Taler-App, sondern die
lokale Contract-Entschlüsselung (`pay-push`/`pay-pull`) plus Purse-Status vom
Exchange.

**Entscheidung.** M2 (Contract-Krypto) wird vor M4 (Karte) gebaut. Persistenz
und Tracking (M3) liegen dazwischen.

**Alternativen.** Karte zuerst mit Platzhalter "unbekannt". Verworfen: genau
der Interimszustand, den Android mit `b3ec1b2d07` beendet hat.

**Folgen.** M1 und M2 sind committet (72 Tests grün). Die Karte hat eine echte
Datenquelle. Erledigt.

## E2 `talerlink://` für alle Links Signal -> Taler auf iOS

**Kontext.** Upstream-GNU-Taler registriert ebenfalls `taler://`. Sind beide
Apps installiert, wählt iOS bei doppelt registriertem Scheme nicht
deterministisch. Android löst das mit `setPackage`, iOS hat kein Gegenstück.
Der Parity-Plan sah `talerlink://` für compose-*, aber `taler://`-Semantik
(nach Rückschreiben) auch für Annehmen/Abbrechen vor.

**Entscheidung (Nutzer, 2026-09-29).** iOS nutzt `talerlink://` für **alle**
Links Signal -> Taler, auch `talerlink://pay-push/...` und
`talerlink://pay-pull/...` (Annehmen/Abbrechen). `Taler_Signal` schreibt das
Scheme vor der Verarbeitung zurück auf `taler`, entfernt die gesamte Query und
reicht nur die bereinigte URI an die bestehende Logik. Das Protokoll ist sonst
identisch zu Android.

**Alternativen.** (a) `taler://` und hoffen, dass die richtige App öffnet:
nicht deterministisch, kann Geldbewegung in der falschen App auslösen.
(b) `Taler_Signal` gibt `taler://` ab: Taler-Links aus Safari landeten dann nicht
mehr in der Fork-App. (c) Universal Links: brauchen Associated Domains, die das
Personal Team nicht hat.

**Folgen.** Taler-Android soll `talerlink://pay-push|pay-pull/...` später
ebenfalls annehmen (N1), damit der Vertrag einheitlich ist. Signal-iOS-Menü
prüft `canOpenURL(talerlink://)` (`LSApplicationQueriesSchemes`). Auf iOS gibt
es keinen `setClassName`-Ersatz; der Vertrag (`link-protokoll.md` 2.1) hält die
Unterschiede fest.

## E3 Rücksprung über `sgnl://taler-return`

**Kontext.** Ziel-App für den Rücksprung muss eindeutig gegenüber
Original-Signal sein (`sgnl://` wäre bei parallel installiertem Signal
mehrdeutig) und ohne Capability laufen.

**Entscheidung.** Custom-Scheme `sgnl`, Host `taler-return`,
identisch zu Android (gemeinsames Protokoll). Keine Universal Links.

**Alternativen.** `sgnl://`: mehrdeutig. Universal Link: nicht möglich (siehe E2).

**Folgen.** Vertrauen ruht auf der correlationId (E9), nicht auf dem Scheme.

## E4 CryptoKit plus schmale Eigenimplementierung

**Kontext.** Zum Entschlüsseln des Contracts braucht Signal Ed25519, X25519,
XSalsa20-Poly1305, Taler-KDF, Crockford, zlib.

**Entscheidung.** SHA-512, HMAC und X25519/Ed25519 über CryptoKit. Eigenimplementiert:
Ed25519-Public -> Montgomery-u (GF(2^255-19)), XSalsa20-Poly1305, Taler-KDF
(Zähler am Ende, SHA512-Extract/SHA256-Expand), Crockford-Base32, zlib-Inflate
über `Compression` (raw DEFLATE nach 2-Byte-Header, Adler-32 selbst geprüft).
Tests mit denselben `taler-exchange-tvg`-Vektoren wie Android
(`TalerCryptoVectorTest.kt`).

**Alternativen.** libsodium (nicht in Pods, ein neuer Pod erzwänge ein eigenes
Pods-Repo), LibSignalClient (bietet weder SecretBox noch Ed25519->Montgomery),
wallet-core in Signal (QuickJS viel zu schwer für eine Vorschau).

**Folgen.** Regel "keine neuen externen Abhängigkeiten" bleibt erfüllt.
Low-Order-Punkte führen zu einem Wurf in CryptoKit und werden als `UNGUELTIG`
behandelt.

## E5 Seitentabelle statt SDS-Feld

**Kontext.** Die strukturierte Payload (Feld 9000) einer ausgehenden Nachricht
muss den DB-Roundtrip überleben. Android nutzt dafür `MessageExtras.talerPayment`.
Eine Änderung an `TSMessage` verlangt SDS-Codegen in Signal-iOS.

**Entscheidung.** Tabelle `TalerPaymentMessage` (FK auf `model_TSInteraction`,
CASCADE). `TSOutgoingMessage._dataMessageBuilder` schlägt dort nach. Ebenso
`TalerConfirmationMessage`. Zusätzlich iOS-only `TalerPaymentInteraction`
(URI -> Nachrichten), damit nach einem Statuswechsel genau die betroffenen
Zellen neu gerendert werden.

**Alternativen.** Neues Feld auf `TSMessage` mit Codegen: großer Eingriff in
generierten Code, Merge-Konflikte bei Upstream-Updates.

**Folgen.** Gleiche Semantik wie Android. Die Seitentabellen sind
plattformintern; nur Proto und Payload-Felder sind Vertrag
(`datenmodell.md`).

## E6 Polling als Actor/Manager statt JobQueue

**Kontext.** Android nutzt `TalerUriRefreshJob` mit persistierter Job-Queue und
Dedup. Signal-iOS hat kein Pendant mit Queue-Dedup, und Refresh-Aufträge müssen
Neustarts nicht überleben.

**Entscheidung.** Swift-Actor/Manager (`TalerPaymentManager`) mit In-Flight-Set
pro (URI, Trigger): Vordergrund-Timer 20 s, Backoff bis 20 min, Cap 200, TTL 24 h,
Fast-Poll 2 s/2 min nach Rücksprung. Kein Hintergrund-Polling (kein BGTask).

**Alternativen.** Eigenes `JobRecord`-SDS-Modell: unnötiger Codegen-Eingriff.

**Folgen.** Nach Neustart pollt der nächste Vordergrund ohnehin erneut. Der
Vertrag beschreibt nur das beobachtbare Verhalten (Statuswechsel, einmalige
Statuszeile), nicht den Mechanismus.

## E7 Lokale Statuszeilen

**Kontext.** Ein Statuswechsel erzeugt eine lokale Chat-Zeile ("Taler-Zahlungslink
abgelaufen"). Auf Android ist das eine `TALER_PAYMENT_UPDATE`-Nachricht. Auf iOS
wäre ein eigener `TSInfoMessage`-Typ ein SDS-Eingriff.

**Entscheidung.** **Gilt: Variante A** (S6, 2026-09-30). Neuer Enum-Wert
`TSInfoMessageTalerPaymentUpdate = 9000` plus userInfo-Key
`InfoMessageUserInfoKeyTalerPaymentStatus` (Rohwert des Status, kein SDS-
Codegenerator-Lauf, keine neue Tabelle). Rund 9 einzeilige Pflicht-Einträge
in Upstream-Switches erzwingt der Compiler. Unabhängig davon gilt der Vertrag:
Zeile bei Erst-Erreichen von `ANGENOMMEN`/`ABGELAUFEN` (einmalig, auch bei
parallelen Polls), lokale Ablehnung/Abbruch mit eigener Zeile, Zeilen
respektieren Verschwinde-Timer. Verworfen: B (`.typeUnsupportedMessage`
missbrauchen, semantisch falsch), C (Unterklasse, bräuchte generierten SDS-Code),
D (`TSErrorMessage`, Fehleroptik und -zählung).

## E8 Keine Allowlist/Cert-Prüfung auf iOS

**Kontext.** Android prüft auf der Taler-Seite das Signing-Cert der Ziel-App
(`AllowedCallers`) und in Signal das Cert der Wallet (`TalerAllowlist`, für die
Sichtbarkeit des Buttons). iOS kann nicht prüfen, welche App ein Scheme
registriert hat.

**Entscheidung.** Nicht portiert. Ersatz: correlationId (15 min, single-use) plus
erneute Prüfung der URIs gegen Exchange (E9, `link-protokoll.md` 2.5).

**Alternativen.** HMAC mit Build-Secret (E9), Universal Links (E2).

**Folgen.** iOS ist gegenüber Android schwächer gegen ein fremdes App, das
`sgnl` oder `talerlink` mitregistriert. Der Schaden ist begrenzt (ein
Link, den der Nutzer gerade selbst angestoßen hat). Die Sicherheitsaussage im
Zielbild 4.11 ("Aufrufer-Signatur wird geprüft") trifft auch auf Android nicht
für Signal zu, siehe N8.

## E9 Kein HMAC beim Rücksprung

**Kontext.** `docs/API-ios.md` §4.3 skizzierte eine HMAC-Härtung mit einem
gemeinsamen Build-Secret beider Forks. Frage 2 im Parity-Plan.

**Entscheidung (Nutzer, 2026-09-29).** Rücksprung **ohne HMAC**. Es genügen die
correlationId (15 min, single-use, nur Speicher) und die erneute Prüfung aller
Werte (`status` wird nie angezeigt, URIs werden gegen Exchange geprüft).

**Alternativen.** HMAC über Rücksprung-Parameter mit eingebettetem Secret.
Verworfen: Secret ließe sich aus einer App extrahieren, Schlüsselverwaltung für
zwei Forks mit getrennten Keystores, kaum Mehrwert gegenüber correlationId.

**Folgen.** Ein gefälschter Rücksprung mit bekannter (erratener oder
mitgehörter) correlationId kann höchstens eine syntaktisch gültige, aber fremde
URI in den Chat schicken, den der Nutzer gerade selbst für "Senden" geöffnet
hatte, einmalig und innerhalb 15 Minuten. Die correlationId ist eine
zufällige UUID (nicht erratbar). Bei einem Update Richtung HMAC müssten die
Parameter erweitert werden (additiv, README Versionierung).

## E10 `statusChangedAt` als neue Migration

**Kontext.** "Zuletzt abgeschlossen" statt "zuletzt erkannt" braucht einen
Statuswechsel-Zeitpunkt (Zielbild 3.2, 6.1). Auf iOS gibt es die Tabelle schon
in Geräten (Migration `addTalerPaymentTables` hat gelaufen).

**Entscheidung.** iOS legt eine **neue** Migration `addTalerPaymentStatusChangedAt`
an (`ALTER TABLE TalerPayment ADD COLUMN statusChangedAt INTEGER`, Enum-Case
direkt nach `addTalerPaymentTables`). Die bestehende Migration und
`createTables` bleiben unverändert (Migration-IDs sind permanent).
`grdbSchemaVersionLatest` bleibt. Kein Backfill (Altzeilen `NULL`).
Semantik: `datenmodell.md` 5.2. Android baut die Spalte später mit derselben
Semantik (`status_changed_at`).

**Alternativen.** Spalte in `createTables` ergänzen: bricht auf Geräten mit
vorhandener Tabelle und verletzt "IDs sind permanent". `lastCheckedAt` als
Ersatz: ändert sich bei jedem Poll, keine Aussage über den Wechsel.

**Folgen.** `latestActivity = statusChangedAt ?? createdAt`. Altzeilen fallen auf
`createdAt` zurück.

## E11 Taler-Tab ersetzt die Einstellungsblöcke

**Kontext.** Android hatte in den Chat-Einstellungen einen Block "Payments"
(Salden) und "Zahlungshistorie" mit globaler Payment History (Android 4.10, ca.
746 Zeilen). Das Zielbild 6.1 verschiebt die Übersicht in einen eigenen Tab
"Taler" der Medienübersicht mit Kopfzeile (Handlungsbedarf, letzter Vorgang,
Kontext), Filter-Chips und Liste.

**Entscheidung.** iOS baut **keinen** Einstellungsblock und **keine** globale
Payment History (Parity-Plan M7 entfällt in diesem Teil). iOS baut direkt den
Taler-Tab (Paket S8). Die Logik (`TalerThreadSummary`, Rangfolge der
Kopfzeile) wird 1:1 portiert (S5).

**Alternativen.** Erst die alten Einstellungsblöcke auf iOS nachbauen und später
ersetzen: doppelte Arbeit.

**Folgen.** Auf Android bleiben Blöcke und Payment History bis zum Umbau
bestehen (N3). Die globale Payment History gibt es künftig auf keiner Plattform,
sobald Android nachzieht [Offen: Nutzer bestätigt, dass Android sie dann
ebenfalls entfernt; Zielbild 4.10 sagt "wird durch 6.1 ersetzt"].

## E12 taler-ios: Code im synchronisierten Ordner mit `#if TALER_SIGNAL`

**Kontext.** `taler-ios` baut mehrere Targets (`GNU_Taler`, `Taler_Wallet`,
`Taler_Nightly`, `Taler_Signal`). Neue Dateien in einer synchronisierten
Xcode-Gruppe werden automatisch in alle App-Targets kompiliert.

**Entscheidung.** Neuer Signal-Code liegt unter
`TalerWallet1/Controllers/SignalLink/` (synchronisierte Gruppe, keine
pbxproj-Änderung). Der gesamte Dateiinhalt (nach den Imports) steht in
`#if TALER_SIGNAL ... #endif`. Änderungen an bestehenden Dateien ebenfalls nur
innerhalb `#if TALER_SIGNAL`. Das Flag ist auf `ios-integration` gesetzt
(`9622dd04`).

**Alternativen.** Target-Membership pro Datei per pbxproj: fehleranfällig,
Merge-Konflikte. Separater Fork-Zweig ohne Flag: Upstream-Updates schwer.

**Folgen.** Die anderen Targets bauen unverändert. In `taler-ios` gibt es im
Build-Slot keine automatischen Tests; dort gilt Build plus Review (`SignalLinkSelfCheck`
für die Parser, nicht automatisch aufgerufen).

## E13 Bestätigungsnachricht: englischer Wortlaut fest

**Kontext.** Nach dem Annehmen sendet der Empfänger (nur 1:1, nur `PAY_PUSH`,
nur `OFFEN -> ANGENOMMEN`, nur nicht-eigene Zahlung) eine Nachricht
"Payment for <Art> accepted (<URI>)". Der Sender erkennt sie per Volltext-Vergleich
und zeigt statt des Texts ein Icon (grau/blau). **Android-Unklarheit:** Der
Detektor vergleicht gegen die **lokalisierten** Strings des Empfängers
(`TalerConfirmationDetector.kt:39-46`), der Sender erzeugt sie in **seiner**
Sprache (`TalerUriRefreshJob.kt:149-150`). `values-de` übersetzt Text und
Art-Label ("Zahlung für Taler-Zahlungslink akzeptiert (...)"). Ein
deutsches Gerät erkennt eine englische Bestätigung also nicht, und umgekehrt.

**Entscheidung.** iOS sendet und erkennt den **englischen** Wortlaut fest,
unabhängig von der Gerätesprache:
`Payment for %1$s accepted (%2$s)` mit den englischen Art-Labels aus
`datenmodell.md` Abschnitt 4. Grund: Kompatibilität und Erkennbarkeit über
Plattform- und Sprachgrenzen.

**Alternativen.** (a) Lokalisiert wie Android: plattform- und sprachübergreifend
kaputt. (b) Sprachneutrales Format, z. B. das Feld in Proto 9000 oder ein
eigenes Proto-Feld: sauberste Lösung, aber Vertragsänderung auf beiden Seiten.

**Folgen.** iOS <-> iOS und iOS <-> Android(en) funktionieren nur, wenn Android
ebenfalls den festen englischen Text sendet und ihn akzeptiert (N6). Bis dahin
wird eine Bestätigung eines deutsch eingestellten Android-Geräts von iOS nicht
erkannt. **Offen:** ob der Text dauerhaft sprachneutral (Proto) werden soll.

Verwandte offene Android-Unklarheiten aus dem Parity-Plan, unverändert von iOS
übernommen: (1) `TalerCardActionGate.showAccept` nur für `PAY_PUSH`
(Absicht oder Lücke?), (2) beim Gruppen-Split zählt `splitDivisor` den Sender
nur bei `includeSelf` mit, erzeugt aber nie eine URI für ihn.

## E14 Wiederholte Parameter, `result` am ersten `|`

**Kontext.** Mehrere URIs und mehrere Ergebnisse müssen durch einen Link. URIs
können Kommas, Doppelpunkte und `+` enthalten. Die Gap-A-Spec hatte zunächst
`uris=a,b` und `results=uri:status,...` skizziert.

**Entscheidung.** Wiederholte Parameter `uri=` und `result=`, streng
prozent-kodiert (nur `A-Za-z0-9-._~` roh). `result` hat die Form
`<uri>|<status>` und wird am **ersten** `|` geteilt; unbekannter Status oder
fehlendes `|` verwirft nur diesen Eintrag. Der Multi-URI-Link (Zielbild 5.2,
Paket D2) übernimmt das Muster.

**Alternativen.** Komma/Doppelpunkt-getrennt (bricht bei URIs mit Kommas bzw.
`:`), JSON in einem Parameter (schwerer zu prüfen, Android-JSON ist strikt, siehe N4).

**Folgen.** `+` muss als `%2B` gesendet werden, weil Android `+` in Query-Werten
zu Leerzeichen dekodiert. URIs mit rohem `|` sind nicht sicher transportierbar
[Offen, `link-protokoll.md` Abschnitt 5].

## E15 Gap A: Abbruch beim "Für alle löschen"

**Kontext.** Löschen einer eigenen offenen Zahlungsnachricht setzt heute nur
lokal `LOKAL_ABGEBROCHEN`. Taler-seitig bleibt die Zahlung offen.

**Entscheidung.** Nur "Für alle löschen" löst `talerlink://compose-abort` aus
(nicht "Für mich löschen"); Taler zeigt einen Sammel-Dialog und bricht pro
Transaktion ab; Rücksprung mit `result=<uri>|aborted|already_claimed|expired|declined`.
Mapping in `datenmodell.md` Abschnitt 9. Ist Taler nicht installiert: lokaler
Fallback `LOKAL_ABGEBROCHEN` plus Statuszeile. Kommt kein Rücksprung: `OFFEN`
(Zielbild 6.2).

**Alternativen.** Stiller Abbruch ohne Nutzerbestätigung (verstößt gegen "Signal
bewegt niemals Geld"), N sequenzielle Deep-Links (nur der letzte Intent kommt
zuverlässig an, `TalerAcceptRejectActions.kt:107-111`).

**Folgen.** Auf Android fehlen Signal- und Taler-Seite (N10). **Offen:**
Die Gap-A-Spec setzt beim fehlenden Rücksprung ebenfalls `LOKAL_ABGEBROCHEN`,
das Zielbild lässt `OFFEN`. Der Vertrag folgt dem Zielbild; die Entscheidung des
Nutzers steht aus. Gap B (Löschungen von außen) bleibt zurückgestellt.
