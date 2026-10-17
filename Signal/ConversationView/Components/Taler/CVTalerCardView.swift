//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// Zahlungskarte in der Konversation, manuell gelayoutet (thread-sicher
/// messbar wie alle CVComponent-Ansichten). Umsetzung des Android-Kachel-
/// Designs (`taler_payment_card.xml`): Marke, Richtung + Betrag + Waehrung,
/// "von dir/an dich", Zweck, Exchange-Chip, kompakter Status, optional
/// Gruppen-Fortschritt und Annehmen-Knopf.
class CVTalerCardView: ManualStackView {

    struct State: Equatable {
        let model: TalerCardModel
        let showAcceptButton: Bool
        let isIncoming: Bool
        let conversationStyle: ConversationStyle

        static func == (lhs: State, rhs: State) -> Bool {
            lhs.model == rhs.model && lhs.showAcceptButton == rhs.showAcceptButton && lhs.isIncoming == rhs.isIncoming
        }
    }

    private static let measurementKey_outerStack = "CVTalerCardView.outerStack"
    private static let measurementKey_buttonStack = "CVTalerCardView.buttonStack"

    private static var outerStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical, alignment: .fill, spacing: 4, layoutMargins: .init(hMargin: 0, vMargin: 6))
    }

    private static var buttonStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .horizontal, alignment: .center, spacing: 0, layoutMargins: UIEdgeInsets(margin: 10))
    }

    private let kindLabel = CVLabel()
    private let amountLabel = CVLabel()
    private let partyLabel = CVLabel()
    private let splitNoteLabel = CVLabel()
    private let summaryLabel = CVLabel()
    private let exchangeLabel = CVLabel()
    private let statusLabel = CVLabel()
    private let acceptLabel = CVLabel()
    let buttonStack = ManualStackViewWithLayer(name: "CVTalerCardView.buttonStack")

    // MARK: - Label-Konfiguration

    private static func textColor(_ state: State) -> UIColor {
        state.conversationStyle.bubbleTextColor(isIncoming: state.isIncoming)
    }

    private static func secondaryColor(_ state: State) -> UIColor {
        state.conversationStyle.bubbleSecondaryTextColor(isIncoming: state.isIncoming)
    }

    private static func toneColor(_ tone: TalerCardModel.Tone, state: State) -> UIColor {
        switch tone {
        case .ok: return UIColor(rgbHex: 0x2E7D32)
        case .bad: return UIColor(rgbHex: 0xC62828)
        case .waiting: return UIColor(rgbHex: 0xB26A00)
        case .neutral: return secondaryColor(state)
        }
    }

    private static func labelConfigs(_ state: State) -> [CVLabelConfig] {
        let model = state.model
        var configs: [CVLabelConfig] = []
        configs.append(.unstyledText(model.kindLabel, font: .dynamicTypeFootnote.semibold(), textColor: secondaryColor(state), numberOfLines: 1))
        let arrow = model.directionIn ? "↓" : "↑"
        configs.append(.unstyledText(
            "\(arrow) \(model.amountText) \(model.currencySymbol)",
            font: .dynamicTypeTitle2.semibold(),
            textColor: textColor(state),
            numberOfLines: 1,
            lineBreakMode: .byTruncatingTail,
        ))
        configs.append(.unstyledText(model.partyText, font: .dynamicTypeFootnote, textColor: secondaryColor(state), numberOfLines: 1))
        if let splitNote = model.splitNote {
            configs.append(.unstyledText(splitNote, font: .dynamicTypeFootnote, textColor: secondaryColor(state), numberOfLines: 0))
        }
        if let summary = model.summary {
            configs.append(.unstyledText(summary, font: .dynamicTypeBody, textColor: textColor(state), numberOfLines: 0))
        }
        if let host = model.exchangeHost {
            configs.append(.unstyledText("⇄ \(host)", font: .dynamicTypeCaption1, textColor: secondaryColor(state), numberOfLines: 1, lineBreakMode: .byTruncatingMiddle))
        }
        let statusText: String
        let statusColor: UIColor
        if let progress = model.splitProgress {
            statusText = progress.text
            statusColor = toneColor(progress.accepted == progress.total ? .ok : .waiting, state: state)
        } else {
            statusText = "\(model.statusIcon) \(model.statusText)"
            statusColor = toneColor(model.statusTone, state: state)
        }
        configs.append(.unstyledText(statusText, font: .dynamicTypeFootnote.semibold(), textColor: statusColor, numberOfLines: 0))
        return configs
    }

    private static func acceptLabelConfig(_ state: State) -> CVLabelConfig {
        let font: UIFont = .dynamicTypeHeadline
        return CVLabelConfig.unstyledText(TalerStrings.actionAccept, font: font, textColor: .white, numberOfLines: 1, textAlignment: .center)
    }

    // MARK: - Rendering

    private var contentLabels: [CVLabel] {
        [kindLabel, amountLabel, partyLabel, splitNoteLabel, summaryLabel, exchangeLabel, statusLabel]
    }

    func configureForRendering(state: State, cellMeasurement: CVCellMeasurement) {
        let configs = Self.labelConfigs(state)
        // Die Labels werden in derselben Reihenfolge belegt, in der die
        // Konfigurationen erzeugt werden; fehlende optionale Zeilen entfallen.
        var subviews: [UIView] = []
        for (index, config) in configs.enumerated() {
            let label = contentLabels[index]
            config.applyForRendering(label: label)
            subviews.append(label)
        }
        if state.showAcceptButton {
            Self.acceptLabelConfig(state).applyForRendering(label: acceptLabel)
            buttonStack.backgroundColor = UIColor(rgbHex: 0x0042B3)
            buttonStack.addLayoutBlock { view in
                view.layer.cornerRadius = 8
                view.layer.masksToBounds = true
            }
            buttonStack.configure(
                config: Self.buttonStackConfig,
                cellMeasurement: cellMeasurement,
                measurementKey: Self.measurementKey_buttonStack,
                subviews: [acceptLabel],
            )
            subviews.append(buttonStack)
        }
        configure(
            config: Self.outerStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_outerStack,
            subviews: subviews,
        )
    }

    static func measurement(for state: State, maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        let outerConfig = outerStackConfig
        let labelMaxWidth = maxWidth - outerConfig.layoutMargins.totalWidth
        var subviewInfos: [ManualStackSubviewInfo] = labelConfigs(state).map {
            $0.measure(maxWidth: labelMaxWidth).asManualSubviewInfo
        }
        if state.showAcceptButton {
            let buttonConfig = buttonStackConfig
            let buttonLabelSize = acceptLabelConfig(state).measure(maxWidth: labelMaxWidth - buttonConfig.layoutMargins.totalWidth)
            let buttonMeasurement = ManualStackView.measure(
                config: buttonConfig,
                measurementBuilder: measurementBuilder,
                measurementKey: measurementKey_buttonStack,
                subviewInfos: [buttonLabelSize.asManualSubviewInfo],
            )
            subviewInfos.append(buttonMeasurement.measuredSize.asManualSubviewInfo)
        }
        let outerMeasurement = ManualStackView.measure(
            config: outerConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: measurementKey_outerStack,
            subviewInfos: subviewInfos,
        )
        return outerMeasurement.measuredSize
    }

    override func reset() {
        super.reset()
        buttonStack.reset()
        for label in contentLabels + [acceptLabel] {
            label.text = nil
            label.removeFromSuperview()
        }
        buttonStack.removeFromSuperview()
    }
}
