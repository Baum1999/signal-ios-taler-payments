# Signal ↔ Taler integration: interface contracts

These documents describe how the four fork apps talk to each other:

| App | Platform | Repository |
|---|---|---|
| Signal (Taler fork) | Android | https://github.com/Baum1999/signal-taler-payments |
| GNU Taler wallet (Signal fork) | Android | https://github.com/Baum1999/taler-signal-integration |
| Signal (Taler fork) | iOS | https://github.com/Baum1999/signal-ios-taler-payments |
| GNU Taler wallet (Signal fork) | iOS | https://github.com/Baum1999/taler-ios-signal-integration |

The same copy of this folder lives in both iOS repositories.

**Language note:** the contract documents themselves are written in German.
This index and the repository READMEs are in English.

## Ground rules

- **Links only.** Signal and Taler never call each other directly (no IPC, no
  shared container, no relay server). Signal opens a `talerlink://` URL, Taler
  answers with `sgnl://taler-return`.
- **Signal never moves money.** Every payment is confirmed by the user in the
  Taler UI. Signal only shows payment cards and builds links.
- **Return links are untrusted.** A return only completes a pending
  `correlationId` (UUID, single use, 15 min TTL, in memory). Amount and status
  always come from Signal's own check: local contract decryption plus purse
  status from the exchange. There is no HMAC (decision E9).
- **Payment URIs are bearer tokens.** `taler://pay-push/...` and
  `taler://pay-pull/...` URIs are never logged, not even truncated.
- **Additive changes only.** Parameter names are never renamed; old and new app
  versions must keep working together. Receivers ignore unknown parameters.

## Documents

| File | Content |
|---|---|
| [`link-protokoll.md`](link-protokoll.md) | Every link between the apps: `compose-send`, `compose-refund`, `compose-abort`, accept/cancel action link, return link (status and result variants), encoding rules, error cases, security rules |
| [`datenmodell.md`](datenmodell.md) | Proto field 9000 (`DataMessage.talerPayment`), `TalerPaymentData` JSON, read order, local tables (incl. `statusChangedAt`), status values, `UriKind`, `CorrelationIntent`, abort result mapping, Android/iOS naming differences |
| [`entscheidungen.md`](entscheidungen.md) | Decision log (E1–E15): why things are the way they are |
| [`android-nachzieh-liste.md`](android-nachzieh-liste.md) | Where Android still has to catch up with the contract (iOS implemented some parts first) |
| [`spec-multi-uri-link.md`](spec-multi-uri-link.md) | **Draft**, not implemented: one link carrying several URIs with metadata |

Markers used in the documents: **[Ist Android]** = verified against the
Android code, **[Neu]** = defined by the contract but not yet on Android,
**[Offen]** = undecided or unverified.

Some documents refer to planning files (`docs/ZIEL-…`, `docs/superpowers/…`)
and to work packages (`S1`…`S11` for Signal-iOS, `T1`…`T5` for Taler-iOS).
The planning files live in a private workspace and are not part of these
repositories. The package names match the commit messages in the iOS repos.

## Flow at a glance

```
Signal                                   Taler
  |  store.put(correlationId, intent)      |
  |------ talerlink://compose-* --------->|  parse, user confirms in Taler UI
  |------ talerlink://pay-push/...?... -->|  read + strip query, hand clean URI to wallet-core
  |<----- sgnl://taler-return ---|  rebuild query, validate target
  store.take(correlationId)  (single use)
  re-check against exchange / send message / prepare draft / update status
```
