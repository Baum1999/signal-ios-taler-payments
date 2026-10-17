# Signal-iOS with GNU Taler payments

This repository is a fork of [Signal-iOS](https://github.com/signalapp/Signal-iOS)
that adds peer-to-peer payments with [GNU Taler](https://taler.net). It is a
development fork and is not affiliated with Signal Messenger LLC or the GNU Taler
team. The original upstream README follows further down.

Signal never holds money or wallet keys. All money movement happens in the
companion GNU Taler wallet (see the matching fork of taler-ios:
https://github.com/Baum1999/taler-ios-signal-integration). The two apps talk
**only through URL links**. There is no IPC and no server of our own.

## Branches

| Branch | Content |
|---|---|
| `main` | Upstream Signal-iOS plus the Taler feature, regularly rebased onto upstream `main` |

## What the fork adds

- **URI detection.** Recognises `taler://` URIs in messages and classifies them
  (`pay-push`, `pay-pull`, `pay`, `withdraw`, `refund`, …).
- **Local contract decryption.** For `pay-push`/`pay-pull` the URI carries a
  one-time key. Signal fetches the encrypted contract straight from the exchange
  (`GET <exchange>/contracts/<pub>`) and decrypts it on the device. This shows
  amount, purpose and direction without the wallet app. It uses CryptoKit plus
  small in-house parts (XSalsa20-Poly1305, Taler KDF, Crockford Base32, zlib).
  wallet-core is not embedded in Signal.
- **Payment card in the conversation.** Shows amount, direction and status,
  with an "Accept" button. Status is polled from the exchange.
- **Message transport.** The payment travels in a new protobuf field
  `DataMessage.talerPayment` (field 9000). The message text also carries a
  readable line plus the plain URI, so ordinary Signal clients see a normal link.
- **Send / request.** An entry in the attachment keyboard opens
  `talerlink://compose-send`. The wallet returns the created URI via
  `sgnl://taler-return`, and Signal sends the message. Group payments
  can be split per member.
- **Refund** via `compose-refund`, prepared as a quoted reply draft and never
  sent automatically.
- **Real abort on "Delete for everyone".** Own open payments are aborted in
  the wallet via `compose-abort`.
- **Status and history.**
  - Local status lines in the chat and a long-press menu.
  - A confirmation message after acceptance, a "paid" delivery status and a
    payment section in message details.
  - Quote summaries.
  - A Taler tab in the media overview.
  - A preview label instead of the raw URI in the chat list and notifications.
  - Forwarding or copying a payment as an image or as text.

## Where the code is

| Path | Content |
|---|---|
| `SignalServiceKit/Taler/` | Model, store, tracker/polling, link builder, return parser, URI parser |
| `SignalServiceKit/Taler/Crypto/` | Contract decryption (`TalerContractCrypto`, `TalerKdf`, `XSalsa20Poly1305`, …) |
| `SignalServiceKit/tests/Taler/` | Unit tests, including crypto test vectors |
| `Signal/Taler/` | UI glue: compose launcher, return handler, card actions, Taler tab, settings row |
| `Signal/ConversationView/Components/Taler/` | Card and confirmation components (CVComponent) |
| `SignalServiceKit/Protos/Specifications/SignalService.proto` | Field 9000 |
| `SignalServiceKit/Storage/Database/GRDBSchemaMigrator.swift` | Tables for payments (side table, no change to existing records) |
| `Signal/URLs/UrlOpener.swift`, `Signal/AppLaunch/AppLifecycleManager.swift` | Entry point for `sgnl://taler-return` (`TalerLinks.returnUri`) |

Interface contracts between the apps (links, parameters, data model, decision
log): [`docs/taler-signal/`](docs/taler-signal/README.md).

## Building

Build as described in the upstream [BUILDING.md](BUILDING.md). Taler unit tests
(simulator), e.g.:

```
xcodebuild test -workspace Signal.xcworkspace -scheme Signal \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= \
  -only-testing:SignalServiceKitTests/TalerLinksTest \
  -only-testing:SignalServiceKitTests/TalerContractCryptoTest
```

All Taler test classes are in `SignalServiceKit/tests/Taler/`. The payment
features need the GNU Taler wallet with Signal integration installed on the
same device. Without it, the send/request entry is hidden.

## Known limitations

- **Return link trust.** iOS cannot check which app registered a URL scheme.
  Returns therefore only finish a pending `correlationId` and trigger a
  re-check; they never deliver amounts or status (decisions E8/E9).
- **Payment without a message.** On send and refund, the wallet commits the
  payment *before* it jumps back. If the return gets lost (app killed, more than
  15 minutes), the payment exists but Signal sends no message. Android has the
  same limitation.
- **Draft only.** The multi-URI link (`docs/taler-signal/spec-multi-uri-link.md`)
  is a draft and not implemented.
- The contract documents are mostly in German.

## Related repositories

- GNU Taler wallet with Signal integration, iOS: https://github.com/Baum1999/taler-ios-signal-integration
- Signal Android with GNU Taler payments: https://github.com/Baum1999/signal-taler-payments
- GNU Taler wallet with Signal integration, Android: https://github.com/Baum1999/taler-signal-integration

---

_Original upstream README:_

# Signal iOS

Signal is a free and open source messaging app for simple private communication with friends.

[![Available on the App Store](https://signal.org/external/images/app-store-download-badge.svg)](https://apps.apple.com/app/id874139669)

Also available on [Android](https://github.com/signalapp/signal-android) and [Desktop](https://github.com/signalapp/signal-desktop).

## Questions?

For troubleshooting and questions, please visit our [support center](https://support.signal.org/) or [unofficial community forum](https://community.signalusers.org/).

## Contributing Bug Reports

The best way to submit a bug report or support request is [via the Support Center](https://support.signal.org/hc/requests/new). Signal iOS doesn't collect any analytics or telemetry, and we rely on your feedback to help us troubleshoot and fix problems when something isn't working correctly.

## Contributing Code

Instructions for how to configure your development environment and build Signal iOS can be found in [BUILDING.md](https://github.com/signalapp/Signal-iOS/blob/main/BUILDING.md). We also recommend reading the [contribution guidelines](https://github.com/signalapp/Signal-iOS/blob/main/CONTRIBUTING.md).

## Contributing Ideas

Have something you want to say about Signal Foundation projects or want to be part of the conversation? Get involved in the [community forum](https://community.signalusers.org).

## Cryptography Notice

This distribution includes cryptographic software. The country in which you currently reside may have restrictions on the import, possession, use, and/or re-export to another country, of encryption software.
BEFORE using any encryption software, please check your country's laws, regulations and policies concerning the import, possession, or use, and re-export of encryption software, to see if this is permitted.
See <http://www.wassenaar.org/> for more information.

The U.S. Government Department of Commerce, Bureau of Industry and Security (BIS), has classified this software as Export Commodity Control Number (ECCN) 5D002.C.1, which includes information security software using or performing cryptographic functions with asymmetric algorithms.
The form and manner of this distribution makes it eligible for export under the License Exception ENC Technology Software Unrestricted (TSU) exception (see the BIS Export Administration Regulations, Section 740.13) for both object code and source code.

## License

Copyright 2013-2025 Signal Messenger, LLC

Licensed under the GNU AGPLv3: https://www.gnu.org/licenses/agpl-3.0.html

_Apple and the Apple logo are trademarks of Apple Inc., registered in the U.S. and other countries. App Store is a service mark of Apple Inc., registered in the U.S. and other countries._
