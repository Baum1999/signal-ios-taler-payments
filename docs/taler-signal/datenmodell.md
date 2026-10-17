# Datenmodell (plattformneutral)

Stand: 2026-09-29. Verbindlich für Android und iOS. Markierungen wie in
`link-protokoll.md`: **[Ist Android]** geprüft im Code, **[Neu]** im Vertrag
festgelegt und auf Android noch nicht vorhanden, **[Offen]** ungeklärt.

## 1. Transport im Signal-Protokoll: `DataMessage.talerPayment` (Feld 9000)

```proto
message TalerPayment {
  repeated string uris = 1;
  optional uint32 version = 2;
  optional bool isGroupSplit = 3;
  optional bool includeSelf = 4;
  optional string totalAmount = 5;
}
// in DataMessage:
optional TalerPayment talerPayment = 9000;
```

[Ist Android: `SignalService.proto:247-253` und `:465`.]

| Feld | Bedeutung | Regeln |
|---|---|---|
| `uris` | Zahlungs-URIs. Einzelzahlung: genau 1. Gruppen-Split: N, eine pro Empfängeranteil | Reihenfolge bedeutsam (Anteil-Index) |
| `version` | Format-Version, heute `1` | fehlt -> `1` |
| `isGroupSplit` | Der Sender hat einen Split gesendet | Sender setzt `recipient.isGroup && uris.size > 1` [Ist Android: `TalerReturnActivity.kt:272`] |
| `includeSelf` | Split: Sender hat sich mitgezählt | nur bei Split; fehlt = keine Split-Info |
| `totalAmount` | Split: Gesamtbetrag vor dem Split als reiner Dezimalstring OHNE Währung (Ist-Stand Android `Amount.amountStr`, z. B. `10` oder `12.5`; iOS `Amount.valueStr` identisch). Leser sollen zusätzlich die Form `WÄHRUNG:BETRAG` tolerieren | nur bei Split; wird vom Empfänger gegen die Summe der Anteile validiert (Toleranz 1e-6) und nur als Anzeigehilfe genutzt (Regel 5) |

Feldnummer 9000 und Feldnamen sind fest. Neue Felder nur mit neuer Nummer.

**Zusätzlich im Body** (für Clients ohne Patch): Klartext, siehe Abschnitt 4.

Das Feld muss den lokalen DB-Roundtrip beim Senden überleben (Einzelzahlung
und Split). Android: `MessageExtras.talerPayment`. iOS: Seitentabelle
`TalerPaymentMessage`, die in `TSOutgoingMessage._dataMessageBuilder`
nachgeschlagen wird (`entscheidungen.md` E5).

## 2. `TalerPaymentData` (JSON, `talerPaymentData` im Rücksprung)

Taler -> Signal beim Rücksprung von compose-send (und als ganzer Body in
älteren Nachrichten, siehe 3). Ein JSON-Objekt:

| Feld | Typ | Pflicht | Bedeutung |
|---|---|---|---|
| `legacyText` | String | ja | Fallback-Text für Clients ohne Feld 9000, heute englisch: "This is a GNU Taler link. Update Signal or copy the URI below into the GNU Taler app to make the payment." (`taler-android` `taler_payment_legacy_text`) |
| `version` | Int | nein | Standard `1` |
| `includeSelf` | Bool | nein | Split: Sender mitgezählt; `null`/fehlt = keine Split-Info |
| `totalAmount` | String | nein | Split: Gesamtbetrag vor dem Split, Dezimalstring ohne Währung (z. B. `12.5`); fehlt = keine Split-Info |
| `uri` | Array von String | ja | Zahlungs-URIs. **Feldname im Singular**, obwohl Liste. Einzelzahlung: 1 Element, Split: N |

[Ist Android: `TalerPaymentData.kt:41-47` (Signal) und
`link/TalerPaymentData.kt:33-39` (Taler), identisch.]

Kodierung durch Android (kotlinx.serialization mit Standardkonfiguration):
`encodeDefaults=false`. Felder mit Standardwert (`version = 1`, `null`) werden
**weggelassen**. Ein Einzelzahlungs-JSON lautet also:

```json
{"legacyText":"This is a GNU Taler link. Update Signal or copy the URI below into the GNU Taler app to make the payment.","uri":["taler://pay-push/exchange.example.org/7Q4XK2"]}
```

Empfänger müssen fehlendes `version` als `1` und fehlende optionale Felder als
"nicht vorhanden" lesen. iOS-Sender kodieren gleich (Standardwerte weglassen,
`TalerPaymentData.swift`, `encode(to:)`), damit beide Seiten dasselbe JSON
erzeugen.

**Grenze [Ist Android]:** Android liest das JSON strikt
(`Json.decodeFromString`, kein `ignoreUnknownKeys`;
`TalerReturnActivity.kt:92`, `TalerPaymentData.kt:92`, `:101`). Ein
zusätzliches JSON-Feld lässt das Parsen scheitern. Folgen: im Rücksprung Rückfall
auf `talerUri`, beim Body-Lesen Rückfall auf die Regex. Additive JSON-Felder
(z. B. für den Multi-URI-Link) brauchen deshalb zuerst den Fix N4. iOS
(`JSONDecoder`) ignoriert unbekannte Felder bereits.

## 3. Lese-Reihenfolge für Nachrichten

Beim Anzeigen und Tracken einer Nachricht gilt, in dieser Reihenfolge:

1. **Proto-Feld 9000** (bzw. die lokal gespeicherte Seitentabelle dazu).
2. **Legacy-JSON**: der `body` ist als Ganzes ein `TalerPaymentData`-JSON
   (ältere Taler-Versionen). Ist `uri` nicht leer, gilt die Liste.
3. **Regex-Fallback** `TalerUriDetector.findUris` über freien Text. Er muss auch
   greifen, wenn vor der URI anderer Text steht. Er wird **nie** auf einen
   JSON-Body angewendet (kompaktes JSON klebt Anführungszeichen an die URI und
   verschmilzt mehrere URIs).

[Ist Android: `urisFromMessageBody`, `TalerPaymentData.kt:99-112`.]

Regex und Nachbearbeitung (`TalerUriDetector`, beide Plattformen gleich):

- Muster `(?i)\b(?:taler|ext\+taler|payto)://\S+`
- Nachlaufende Zeichen `. , ) ] } ! ? ; :` werden abgeschnitten
- `distinct`, Reihenfolge des Auftretens
- `taler+http://` wird nicht erkannt.

`NSRegularExpression` und Java weichen bei `\b`/`\S` minimal ab; beide Seiten
haben Tests mit denselben Randfällen.

## 4. Body-Formate ausgehender Nachrichten

| Nachricht | Body | Feld 9000 |
|---|---|---|
| Zahlung gesendet/angefordert, mit `talerPaymentData` | `legacyText` + Leerzeile + URIs durch Leerzeile getrennt [Ist Android: `TalerReturnActivity.kt:295`] | ja |
| Zahlung, Rückfall ohne JSON | "Payment sent: <Art> (<URI>)" bzw. "Payment requested: <Art> (<URI>)" | ja, 1 URI |
| Rückerstattung (Entwurf) | "Refund: <Zweck oder URI>" + Leerzeile + URIs | durch den Rücksprung nicht gesetzt (der Nutzer sendet den Entwurf manuell). [Offen: nicht geprüft, ob das normale Senden des Entwurfs Feld 9000 ergänzt] |
| Bestätigung nach Annahme | "Payment for <Art> accepted (<URI>)" | nein |

`<Art>` ist das Label der URI-Art. **Achtung [Ist Android]:** Body-Texte und
`<Art>`-Labels sind auf Android **lokalisiert** (`values-de`: "Zahlung für
Taler-Zahlungslink akzeptiert (...)"). Der Detektor vergleicht den Volltext
gegen die Strings des **Empfängers** (`TalerConfirmationDetector.kt:39-46`).
Vertragsregel: siehe `entscheidungen.md` E9 (Bestätigungstext englisch fest)
und N6.

Englische Kind-Labels (Ist): `pay-push` "Taler payment link", `pay-pull`
"Taler payment request", `pay` "Taler payment", `withdraw` "Taler withdrawal
link", `refund` "Taler refund link", unbekannt "Taler link".

## 5. Lokale Tabellen

### 5.1 `taler_payment` (Android) / `TalerPayment` (iOS): ein Vorgang pro URI

`uri` ist **eindeutig** (UNIQUE). Doppelt zugestellte, zitierte,
weitergeleitete Nachrichten mit derselben URI sind derselbe Vorgang.

| Semantik | Android (`snake_case`) | iOS (`camelCase`) | Typ | Hinweis |
|---|---|---|---|---|
| Zeilen-Schlüssel | `_id` | `id` | INTEGER PK | iOS mit AUTOINCREMENT |
| URI | `uri` | `uri` | TEXT NOT NULL UNIQUE | Inhaberpapier |
| Thread | `thread_id` (INTEGER) | `threadUniqueId` (TEXT) | siehe rechts | **Typabweichung**: Android numerische Thread-ID, iOS String-UniqueId. Nie über Plattformgrenzen tauschen |
| Art | `uri_kind` | `uriKind` | TEXT NULL | Name aus `UriKind` (Abschnitt 6) |
| Status | `status` | `status` | TEXT NOT NULL | Name aus Statuswerte (Abschnitt 7) |
| Betrag | `amount` | `amount` | TEXT NULL | Dezimalstring |
| Währung | `currency` | `currency` | TEXT NULL | |
| Exchange | `exchange_base_url` | `exchangeBaseUrl` | TEXT NULL | |
| Zweck | `summary` | `summary` | TEXT NULL | |
| Erkannt am | `created_at` | `createdAt` | INTEGER NOT NULL | ms seit 1970; Zeitpunkt der **Erkennung** durch Signal, kein Zahlungszeitpunkt |
| Zuletzt geprüft | `last_checked_at` | `lastCheckedAt` | INTEGER NULL | ms seit 1970; letzter erfolgreicher Poll |
| Fehlerzähler | `consecutive_failures` | `consecutiveFailures` | INTEGER, Standard 0 | Backoff beim Polling; Erfolg setzt zurück |
| Eigene Zahlung | `is_own_payment` | `isOwnPayment` | INTEGER 0/1 | Richtung aus der Nachricht (ausgehend = eigen) |
| **Statuswechsel-Zeitpunkt** | `status_changed_at` **[Neu, nicht vorhanden]** | `statusChangedAt` **[Neu, Migration S2]** | INTEGER NULL | Abschnitt 5.2 |

Index auf dem Thread. Migrationen: Android `V322_AddTalerPaymentTable`,
`V323_AddTalerPaymentPollingColumns` (Fehlerzähler), `V402_...`. iOS:
`addTalerPaymentTables`, danach `addTalerPaymentStatusChangedAt`.
Migrations-IDs sind auf iOS **permanent** (nie umbenennen oder ändern, es gibt
Geräte, auf denen sie lief). Neue Spalten nur über neue Migration.

Neu erkannte URIs starten mit `status = UNBEKANNT_OFFLINE`
(`upsertDetected`, Android `TalerPaymentTable.kt:114-126`), bis die erste Prüfung
lief. Ein Aufrufer legt nur an, wenn die URI noch nicht existiert
(`CONFLICT_IGNORE`), und stößt dann einen Refresh an.

### 5.2 `statusChangedAt` [Neu]

Zweck: "zuletzt abgeschlossen" statt nur "zuletzt erkannt" anzeigen (Zielbild
3.2, Taler-Tab 6.1).

Semantik:

- Gesetzt auf `now` (ms), **genau dann, wenn sich der Status tatsächlich
  ändert** (neuer Status != alter Status) **und** tatsächlich geschrieben wird.
- **Nicht** gesetzt bei: Erkennung (`upsertDetected`, Spalte bleibt `NULL`),
  Prüf-Fehlern (`recordFailure`), gleichem Status bei erneutem Poll, und
  wenn der Schutz lokaler Endzustände das Schreiben verhindert
  (`LOKAL_ABGELEHNT`, `LOKAL_ABGEBROCHEN` werden nie durch einen Poll
  überschrieben; dann bleibt die Spalte unverändert).
- Kein Backfill: Altzeilen bleiben `NULL`.
- Abgeleitet: **`latestActivity = statusChangedAt ?? createdAt`**. iOS:
  `TalerPaymentStore.latestActivityAt(record)`. "Letzter Vorgang" im
  Thread-Kopf sortiert danach (bei Gleichstand nach `uri`, wie Android heute mit
  `createdAt`: `TalerThreadSummary.kt:118-119`).
- Auf Android müssen die Schreibpfade `applyPreviewAndRecordTransition`
  (`TalerPaymentTable.kt:201`) und `updateStatus` (`:268`) angepasst werden.
  `updateFromPreview` (`:128`) wird im Code nirgends aufgerufen (nur in
  Kommentaren); dort entweder mit anpassen oder entfernen.

### 5.3 Weitere Tabellen (Zuordnung Nachricht <-> Vorgang)

| Zweck | Android | iOS |
|---|---|---|
| Strukturierte Payload pro Nachricht (Feld 9000 persistiert) | `taler_payment_message`: `message_id` (UNIQUE), `uris` (durch `\n` verbunden), `version`, `is_group_split`, `include_self` (NULL erlaubt), `total_amount` | `TalerPaymentMessage`: `interactionId` (PK, FK auf `model_TSInteraction`, ON DELETE CASCADE), `uris` (durch `\n`), `version`, `isGroupSplit`, `includeSelf`, `totalAmount` |
| Erkannte Bestätigungsnachricht -> URI | `taler_confirmation_message`: `message_id` (UNIQUE), `uri`, `matched_at` | `TalerConfirmationMessage`: `interactionId` (PK, FK, CASCADE), `uri`, `matchedAt` |
| URI -> Nachrichten (welche Zellen nach Statuswechsel neu zeichnen) | nicht vorhanden (Android findet die Nachricht anders) | `TalerPaymentInteraction`: `interactionId` + `uri` (Composite-PK, FK, CASCADE), Index auf `uri`. **Nur iOS**, plattformintern, kein Vertragsbestandteil |

Die Trennzeichen (`\n` für `uris`) sind lokal, nicht Teil des Transports.

## 6. `UriKind`

| Wert | Pfad-Präfix (nach `taler://`, `ext+taler://`, `taler+http://`) | Signal-Verhalten |
|---|---|---|
| `PAY_PUSH` | `pay-push/` | Karte, Vorschau, Annehmen/Abbrechen, Refund, Abbruch |
| `PAY_PULL` | `pay-pull/` | Karte, Vorschau; Aktionslink vorgesehen, aber auf Android nicht gesendet |
| `PAY` | `pay/`, `pay-template/` | nur klassifiziert, öffnet Taler |
| `WITHDRAW` | `withdraw/`, `withdraw-exchange/` | nur klassifiziert, öffnet Taler |
| `REFUND` | `refund/` | nur klassifiziert, öffnet Taler |

Klassifikation lokal und zustandslos über `TalerUriParser.classify` (Kleinschreibung,
Trim). Die Kotlin-Datei ist eine Spiegelkopie aus taler-android
(`scripts/sync-aidl.sh`) und muss byte-identisch bleiben; iOS spiegelt die Logik
1:1. Nicht klassifizierbar (`payto://`, Fremdschema) -> `null`. Die Werte werden
als Namen (`PAY_PUSH`, ...) gespeichert und im Link-Parameter `direction` genutzt.

## 7. Statuswerte

| Wert | Quelle | Bedeutung |
|---|---|---|
| `OFFEN` | Exchange | Purse existiert, noch nicht eingelöst |
| `ANGENOMMEN` | Exchange | Empfänger hat eingelöst (merged/deposited) |
| `ABGELAUFEN` | Exchange | Purse abgelaufen, bevor jemand annahm |
| `UNGUELTIG` | Exchange/Prüfung | nicht entschlüsselbar, nicht vorhanden, abgebrochen (siehe Abbruch-Mapping) |
| `UNBEKANNT_OFFLINE` | Signal | nicht prüfbar (offline, Exchange nicht erreichbar) und Startwert nach Erkennung |
| `LOKAL_ABGELEHNT` | Signal, lokal | Nutzer hat auf diesem Gerät abgelehnt (kein Netzwerk, keine Rückerstattung, nur "nicht mehr verfolgen") |
| `LOKAL_ABGEBROCHEN` | Signal, lokal | Nachricht gelöscht/Abbruch-Fallback; rein kosmetische Buchführung |

- Die ersten fünf entsprechen `TalerOperationStatus` (`fromTalerStatus` bildet 1:1 ab).
- `LOKAL_ABGELEHNT` und `LOKAL_ABGEBROCHEN` sind **lokale Endzustände**: ein Poll
  überschreibt sie nie. Nur ein erneuter Aufruf, der genau denselben lokalen Wert
  setzt, wird durchgelassen (`TalerPaymentTable.kt:268-278`).
- Statuszeile im Chat bei Erst-Erreichen von `ANGENOMMEN` oder `ABGELAUFEN`
  (Wechsel `previous != new`). Läuft ROUTINE- und RETURN-Poll parallel, entsteht
  sie trotzdem nur einmal (Vergleich und Schreiben in einer Transaktion:
  `applyPreviewAndRecordTransition`). Statuszeilen respektieren
  Verschwinde-Nachrichten (`expiresIn`).
- Fallbacks (offline, ungültig) sind getrennt, nicht zusammengelegt.
- Persistiert wird der Name (`OFFEN`, `UNBEKANNT_OFFLINE`, ...), auf beiden Plattformen
  identisch.

## 8. `CorrelationIntent` und Store-Eintrag

Der Store ist nur im Speicher (TTL 15 min, single-use, Abschnitt 2.4 im
Link-Protokoll).

| Intent | Wert (Name) | Zweck | Store-Felder | Reaktion beim Rücksprung |
|---|---|---|---|---|
| Annehmen oder Abbrechen | `ACCEPT_OR_CANCEL` | Aktionslink | `uri` (die betroffene URI), `threadId` | Fast-Poll der `uri`; `status` ignoriert |
| Senden | `SEND` | compose-send | `threadId` | bei `ready`: Nachricht senden |
| Rückerstatten | `REFUND` | compose-refund | `uri` (= `originalUri`, nur Kontext), `threadId`, optional `quoteMessageId` + `quoteAuthor` (Android) / `quoteInteractionUniqueId` (iOS) | bei `ready`: Entwurf, ggf. Zitat-Antwort |
| Abbrechen (Löschen) **[Neu]** | `ABORT` | compose-abort | `uris` (**Liste** aller abzubrechenden URIs), `threadId` | `result`-Einträge auswerten, Abbruch-Ergebnis-Mapping |

Android heute: `enum class TalerCorrelationIntent { ACCEPT_OR_CANCEL, SEND, REFUND }`
(`TalerCorrelationStore.kt:17`), `Entry(intent, uri, threadId, quoteMessageId,
quoteAuthor)`. `ABORT` und ein `uris`-Feld fehlen noch (N10).
iOS (Paket S1): `TalerCorrelationIntent` mit den vier Werten (String-Werte
`ACCEPT_OR_CANCEL`, `SEND`, `REFUND`, `ABORT`), `TalerCorrelationEntry`
(`intent`, `threadUniqueId`, `uri`, `uris: [String]` (nur ABORT, sonst leer),
`quoteInteractionUniqueId`).

Regel: Der Intent des Eintrags entscheidet, wie der Rücksprung gelesen wird
(Link-Protokoll Abschnitt 8, Regel 4).

## 9. Abbruch-Ergebnis-Mapping (compose-abort)

| `result`-Ergebnis | Bedeutung | Signal setzt Status | Begründung |
|---|---|---|---|
| `aborted` | Taler hat die Transaktion tatsächlich abgebrochen | `UNGUELTIG` | bestätigter Abbruch, bestehende Zuordnung (`Aborted`/`Deleted` -> `UNGUELTIG`), **kein** neuer Status |
| `expired` | Purse war schon abgelaufen | `ABGELAUFEN` | vorhandener Status |
| `already_claimed` | Empfänger hatte schon angenommen | **keine Änderung** | Fast-Poll übernimmt den echten Zustand (z. B. `ANGENOMMEN`) |
| `declined` | Nutzer hat die Sammelbestätigung in Taler abgelehnt (gilt für alle URIs der Anfrage) | **keine Änderung** | bleibt `OFFEN` |
| kein `result` für eine URI | Taler kannte die URI nicht oder kein Rücksprung | keine Änderung | bleibt `OFFEN` |
| Taler nicht erreichbar | (kein Rücksprung möglich) | `LOKAL_ABGEBROCHEN` + Statuszeile, nur wenn Öffnen sofort scheitert | heutiges Verhalten als Fallback |

Keine neue lokale Statuszeile für `aborted`/`expired`/`already_claimed`: die
Zahlungsnachricht wurde gerade gelöscht. [Offen: Zielbild 6.2 und Spec
widersprechen sich bei "kein Rücksprung", siehe Link-Protokoll Abschnitt 5.]

## 10. Plattform-Namensabweichungen (Übersicht)

| Thema | Android | iOS |
|---|---|---|
| Spaltennamen | `snake_case` (`thread_id`, `exchange_base_url`) | `camelCase` (`threadUniqueId`, `exchangeBaseUrl`) |
| Tabellennamen | `taler_payment`, `taler_payment_message`, `taler_confirmation_message` | `TalerPayment`, `TalerPaymentMessage`, `TalerConfirmationMessage`, zusätzlich `TalerPaymentInteraction` |
| Nachrichten-Schlüssel | `message_id` (Long, `MessageTable`) | `interactionId` (Int64, `model_TSInteraction.id`) mit FK und CASCADE; im Store-Eintrag `threadUniqueId`/`quoteInteractionUniqueId` als String |
| Thread-Bezug in `TalerPayment` | `thread_id` INTEGER | `threadUniqueId` TEXT |
| Statuswechsel-Spalte | `status_changed_at` (Neu) | `statusChangedAt` (Migration S2) |
| Enum-Case-Namen im Code | `TalerPaymentStatus.OFFEN`, `TalerUriKind.PAY_PUSH` | `.offen`, `.payPush` (`rawValue` identisch: `"OFFEN"`, `"PAY_PUSH"`) |
| Statuszeile im Chat (E7) | `TALER_PAYMENT_UPDATE`-Nachricht (`MessageType`) | [Offen: legt Paket S6 fest] |
| Store-Eintrag `uri`/`uris` | `Entry.uri: String?` (Kotlin, `uris` fehlt heute) | `uri: String?` + `uris: [String]` |
| Migrations-Namen | `V322`, `V323`, `V402` (Nummernschema von Signal) | `addTalerPaymentTables`, `addTalerPaymentStatusChangedAt` (GRDB-IDs) |
| Payload-Typen | `TalerPaymentPayload` (Kotlin) | `TalerPaymentPayload` (Swift), `TalerPaymentData` (Codable) |

Persistierte Werte in Spalten (`status`, `uriKind`) sind auf beiden
Plattformen die **Rohnamen** in Großbuchstaben mit Unterstrich. Nur diese sind Vertrag.
