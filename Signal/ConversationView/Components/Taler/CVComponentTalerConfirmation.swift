//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

extension CVComponentState {
    /// Zustand einer erkannten Bestaetigungsnachricht (S7a). Wird beim Laden
    /// aus `TalerConfirmationMessage` gelesen; aendert sich der zugehoerige
    /// Vorgang, beruehrt `TalerPaymentManager.touchInteractions` die
    /// Bestaetigungs-Interaktion und die Zelle wird neu geladen. Die URI
    /// selbst bleibt bewusst draussen - sie steht in der DB und ist ein
    /// Inhaberpapier.
    struct TalerConfirmation: Equatable {
        /// Die URI der Bestaetigung ist beim Exchange als ANGENOMMEN
        /// bestaetigt (farbliche Betonung, sonst grau).
        let isAccepted: Bool
    }
}

/// Kompakte Zeile mit Icon statt Rohtext fuer eine erkannte Bestaetigungs-
/// nachricht des Zahlungsempfaengers: grau = erkannt, blau = die URI ist
/// ANGENOMMEN. Spiegel von `TalerConfirmationIconPresenter.kt`
/// (signal-android); angezeigt wird der Zustand aus der DB, nie der Rohtext.
class CVComponentTalerConfirmation: CVComponentBase, CVComponent {

    var componentKey: CVComponentKey { .talerConfirmation }

    private let talerConfirmation: CVComponentState.TalerConfirmation

    init(itemModel: CVItemModel, talerConfirmation: CVComponentState.TalerConfirmation) {
        self.talerConfirmation = talerConfirmation
        super.init(itemModel: itemModel)
    }

    // MARK: - Zustand

    static func buildState(message: TSMessage, transaction: DBReadTransaction) -> CVComponentState.TalerConfirmation? {
        guard
            let interactionId = message.sqliteRowId,
            let uri = TalerPaymentStore.confirmationUri(interactionId: interactionId, tx: transaction)
        else {
            return nil
        }
        // Zustand nur aus der DB (verifizierter Record), nie aus dem Text.
        let isAccepted = TalerPaymentStore.record(forUri: uri, tx: transaction)?.status == .angenommen
        return CVComponentState.TalerConfirmation(isAccepted: isAccepted)
    }

    // MARK: - Anzeige

    private var lineColor: UIColor {
        if talerConfirmation.isAccepted {
            // Blau wie der Lesebestaetigungs-Haken (Android signal_colorPrimary).
            return UIColor.Signal.ultramarine
        }
        var color = UIColor.Signal.secondaryLabel
        if conversationStyle.hasWallpaper {
            color = conversationStyle.bubbleSecondaryTextColor(isIncoming: isIncoming)
        }
        return color
    }

    private var labelConfig: CVLabelConfig {
        let font: UIFont = .dynamicTypeFootnote
        let color = lineColor
        let text = NSMutableAttributedString()
        text.append(SignalSymbol.checkCircle.attributedString(
            dynamicTypeBaseSize: font.pointSize,
            leadingCharacter: .space,
            attributes: [.foregroundColor: color],
        ))
        text.append(NSAttributedString(
            string: TalerStrings.confirmationLine,
            attributes: [.font: font, .foregroundColor: color],
        ))
        return CVLabelConfig(
            text: .attributedText(text),
            displayConfig: .forUnstyledText(font: font, textColor: color),
            font: font,
            textColor: color,
            numberOfLines: 1,
            lineBreakMode: .byTruncatingTail,
        )
    }

    // MARK: - CVComponent

    func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewTalerConfirmation()
    }

    func configureForRendering(
        componentView: CVComponentView,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate,
    ) {
        guard let componentView = componentView as? CVComponentViewTalerConfirmation else {
            owsFailDebug("Unexpected componentView.")
            componentView.reset()
            return
        }
        labelConfig.applyForRendering(label: componentView.label)
    }

    func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)
        let maxWidth = min(maxWidth, conversationStyle.maxMessageWidth)
        return labelConfig.measure(maxWidth: maxWidth)
    }

    class CVComponentViewTalerConfirmation: NSObject, CVComponentView {
        fileprivate let label = CVLabel()

        var isDedicatedCellView = false

        var rootView: UIView { label }

        func setIsCellVisible(_ isCellVisible: Bool) {}

        func reset() {
            label.text = nil
            label.attributedText = nil
        }
    }
}
