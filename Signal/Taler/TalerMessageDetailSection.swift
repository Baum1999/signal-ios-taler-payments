//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

/// Nachrichtendetails (Zielbild 4.8): pro Taler-URI der Nachricht ein
/// eigener Abschnitt mit gekuerzter URI (per Long-Press kopierbar), Status,
/// Betrag + Waehrung, "Erkannt am" (ehrlich: Signal kennt keinen
/// Zahlungszeitpunkt, nur wann dieses Geraet die URI erkannt hat) und -
/// nach einem Statuswechsel - "Status geaendert am". Betraege stehen nur im
/// Record (Regel 5), die volle URI erscheint nie (Regel 4). Aufgerufen wird
/// aus `MessageDetailViewController.updateTableContents` beim
/// Neuaufbau der Inhalte, nicht im Zell-Layout.
enum TalerMessageDetailSection {

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// `nil` bzw. leeres Ergebnis, wenn die Nachricht keine Taler-URI traegt.
    static func sections(for message: TSMessage) -> [OWSTableSection] {
        var uris: [String] = []
        var records: [TalerPaymentRecord?] = []
        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            uris = CVComponentTalerPayment.uris(for: message, transaction: transaction)
            records = uris.map { TalerPaymentStore.record(forUri: $0, tx: transaction) }
        }
        guard !uris.isEmpty else {
            return []
        }

        return zip(uris, records).map { uri, record in
            let section = OWSTableSection()
            section.headerTitle = TalerStrings.detailSectionTitle
            section.add(uriRow(uri: uri))
            section.add(
                OWSTableItem(
                    text: TalerStrings.detailStatusLabel,
                    actionBlock: nil,
                    accessoryText: statusText(record),
                    accessoryType: .none
                )
            )
            if let amountText = amountText(record) {
                section.add(
                    OWSTableItem(
                        text: TalerStrings.detailAmountLabel,
                        actionBlock: nil,
                        accessoryText: amountText,
                        accessoryType: .none
                    )
                )
            }
            if let record {
                section.add(
                    OWSTableItem(
                        text: TalerStrings.detailDetectedLabel,
                        actionBlock: nil,
                        accessoryText: dateString(record.createdAt),
                        accessoryType: .none
                    )
                )
                if let statusChangedAt = record.statusChangedAt {
                    section.add(
                        OWSTableItem(
                            text: TalerStrings.detailStatusChangedLabel,
                            actionBlock: nil,
                            accessoryText: dateString(statusChangedAt),
                            accessoryType: .none
                        )
                    )
                }
            }
            return section
        }
    }

    // MARK: - Zeileninhalte

    /// Gekuerzte URI wie Android (`MessageDetailsFragment.shortenTalerUri`):
    /// Anfang...Ende. In der Anzeige steht nie die volle URI.
    static func shortenedUri(_ uri: String) -> String {
        guard uri.count > 48 else {
            return uri
        }
        return String(uri.prefix(28)) + "…" + String(uri.suffix(12))
    }

    private static func statusText(_ record: TalerPaymentRecord?) -> String {
        guard let record else {
            return TalerStrings.statusChecking
        }
        return TalerCardModel.plainStatusLabel(record.status)
    }

    /// Betrag nur aus dem Record (Regel 5), sonst keine Betragszeile.
    private static func amountText(_ record: TalerPaymentRecord?) -> String? {
        guard let amount = record?.amount, !amount.isEmpty else {
            return nil
        }
        let currency = record?.currency ?? ""
        return "\(TalerCardModel.formatAmount(amount)) \(currency)".trimmingCharacters(in: .whitespaces)
    }

    private static func dateString(_ milliseconds: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
        return dateTimeFormatter.string(from: date)
    }

    // MARK: - URI-Zeile (Long-Press kopiert die volle URI)

    private static func uriRow(uri: String) -> OWSTableItem {
        let shortUri = shortenedUri(uri)
        return OWSTableItem(
            customCellBlock: {
                let cell = UITableViewCell()
                cell.selectionStyle = .none

                let nameLabel = UILabel()
                nameLabel.text = TalerStrings.detailUriLabel
                nameLabel.textColor = Theme.primaryTextColor
                nameLabel.font = .dynamicTypeBodyClamped
                nameLabel.adjustsFontForContentSizeCategory = true
                nameLabel.numberOfLines = 1
                nameLabel.lineBreakMode = .byTruncatingTail
                nameLabel.setCompressionResistanceHorizontalLow()
                nameLabel.setContentHuggingLow()

                let uriLabel = UILabel()
                uriLabel.text = shortUri
                uriLabel.textColor = Theme.isDarkThemeEnabled ? UIColor.ows_gray25 : UIColor.ows_gray45
                uriLabel.font = .dynamicTypeBodyClamped
                uriLabel.adjustsFontForContentSizeCategory = true
                uriLabel.numberOfLines = 1
                uriLabel.lineBreakMode = .byTruncatingMiddle
                uriLabel.setCompressionResistanceHorizontalHigh()
                uriLabel.setContentHuggingHigh()

                let contentRow = UIStackView(arrangedSubviews: [nameLabel, uriLabel])
                contentRow.axis = .horizontal
                contentRow.alignment = .center
                contentRow.spacing = 8
                cell.contentView.addSubview(contentRow)
                contentRow.autoPinEdgesToSuperviewMargins()

                // Der Handler haelt die volle URI und schreibt sie bei
                // Long-Press nur in die Zwischenablage - nie in Logs oder
                // Fehlermeldungen (Regel 4). Der Cell-Block haelt den
                // Handler am Leben, solange das Item existiert.
                let copyHandler = TalerUriCopyHandler(uri: uri)
                let longPress = UILongPressGestureRecognizer(
                    target: copyHandler,
                    action: #selector(TalerUriCopyHandler.handleLongPress(_:))
                )
                cell.contentView.addGestureRecognizer(longPress)
                // UIGestureRecognizer haelt sein Target nur schwach.
                objc_setAssociatedObject(cell, &TalerUriCopyHandler.associationKey, copyHandler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                return cell
            }
        )
    }
}

/// Ziel des Long-Press auf der URI-Zeile: kopiert die volle URI in die
/// Zwischenablage und zeigt den Standard-Toast.
private final class TalerUriCopyHandler: NSObject {

    nonisolated(unsafe) static var associationKey: UInt8 = 0

    private let uri: String

    init(uri: String) {
        self.uri = uri
        super.init()
    }

    @objc func handleLongPress(_ sender: UILongPressGestureRecognizer) {
        guard sender.state == .began else {
            return
        }
        UIPasteboard.general.string = uri
        ToastViewHelper.presentToastOnFrontmostViewController(
            text: OWSLocalizedString(
                "COPIED_TO_CLIPBOARD",
                comment: "Indicator that a value has been copied to the clipboard."
            ),
            image: UIImage(named: "check")
        )
    }
}
