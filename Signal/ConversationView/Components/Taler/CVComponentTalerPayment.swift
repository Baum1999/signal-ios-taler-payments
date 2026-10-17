//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import SignalUI

extension CVComponentState {
    /// Zustand der Taler-Karte einer Nachricht. Wird beim Laden aus
    /// `TalerPayment` gelesen; aendert sich der Vorgang, beruehrt
    /// `TalerPaymentManager` die verknuepften Interaktionen und die Zelle
    /// wird neu geladen.
    struct TalerPayment: Equatable {
        let model: TalerCardModel
        let uris: [String]
        /// URI, die der Annehmen-Knopf oeffnet (nil = kein Knopf).
        let acceptUri: String?
        let threadUniqueId: String
    }
}

public class CVComponentTalerPayment: CVComponentBase, CVComponent {

    public var componentKey: CVComponentKey { .talerPayment }

    private let talerPayment: CVComponentState.TalerPayment

    init(itemModel: CVItemModel, talerPayment: CVComponentState.TalerPayment) {
        self.talerPayment = talerPayment
        super.init(itemModel: itemModel)
    }

    private var state: CVTalerCardView.State {
        CVTalerCardView.State(
            model: talerPayment.model,
            showAcceptButton: talerPayment.acceptUri != nil,
            isIncoming: isIncoming,
            conversationStyle: conversationStyle,
        )
    }

    // MARK: - Zustand

    static func uris(for message: TSMessage, transaction: DBReadTransaction) -> [String] {
        if
            let rowId = message.sqliteRowId,
            let structured = TalerPaymentStore.paymentMessage(interactionId: rowId, tx: transaction)
        {
            return structured.payload.uris
        }
        guard let body = message.body, !body.isEmpty else {
            return []
        }
        return TalerMessageBody.uris(in: body)
    }

    static func buildState(message: TSMessage, thread: TSThread, transaction: DBReadTransaction) -> CVComponentState.TalerPayment? {
        let uris = CVComponentTalerPayment.uris(for: message, transaction: transaction).filter(TalerPaymentTracker.isTrackable)
        guard !uris.isEmpty else {
            return nil
        }
        // Deckt auch Chats ab, deren URIs laengst bekannt sind (Oeffnen/Scrollen).
        TalerPaymentManager.shared.ensureStarted()

        let otherPartyName = CVComponentTalerPayment.otherPartyName(thread: thread, transaction: transaction)
        let records = uris.map { TalerPaymentStore.record(forUri: $0, tx: transaction) }

        if uris.count == 1 {
            let model = TalerCardModel.build(record: records[0], otherPartyName: otherPartyName)
            return CVComponentState.TalerPayment(
                model: model,
                uris: uris,
                // Nur Cache-Lesen: buildState laeuft im Ladepfad, nicht
                // unbedingt auf dem Main-Thread; frisch geprueft wird beim
                // Tippen (TalerCardActions.accept).
                acceptUri: model.showAccept && TalerInstallation.isInstalled ? uris[0] : nil,
                threadUniqueId: thread.uniqueId,
            )
        }

        let structured = message.sqliteRowId.flatMap { TalerPaymentStore.paymentMessage(interactionId: $0, tx: transaction) }?.payload
        let legacy = message.body.flatMap(TalerPaymentData.parseOrNil)
        let group = TalerGroupSplit.buildCard(
            message: message,
            thread: thread,
            uris: uris,
            records: records,
            totalAmount: structured?.totalAmount ?? legacy?.totalAmount,
            includeSelf: structured?.includeSelf ?? legacy?.includeSelf,
            otherPartyName: otherPartyName,
            transaction: transaction,
        )
        return CVComponentState.TalerPayment(
            model: group.model,
            uris: uris,
            acceptUri: TalerInstallation.isInstalled ? group.acceptUri : nil,
            threadUniqueId: thread.uniqueId,
        )
    }

    static func otherPartyName(thread: TSThread, transaction: DBReadTransaction) -> String? {
        if let contactThread = thread as? TSContactThread {
            return SSKEnvironment.shared.contactManagerRef.displayName(for: contactThread.contactAddress, tx: transaction).resolvedValue()
        }
        if let groupThread = thread as? TSGroupThread {
            return groupThread.groupNameOrDefault
        }
        return nil
    }

    // MARK: - CVComponent

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewTalerPayment()
    }

    public func configureForRendering(
        componentView: CVComponentView,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate,
    ) {
        guard let componentView = componentView as? CVComponentViewTalerPayment else {
            owsFailDebug("Unexpected componentView.")
            componentView.reset()
            return
        }
        componentView.cardView.configureForRendering(state: state, cellMeasurement: cellMeasurement)
    }

    /// Mindestbreite eingehender Karten, damit die Karte nicht als schmaler
    /// Streifen erscheint (Vorgabe S3; Muster: CVComponentGiftBadge).
    static let minIncomingCardWidth: CGFloat = 240

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)
        let maxWidth = min(maxWidth, conversationStyle.maxMessageWidth)
        var size = CVTalerCardView.measurement(for: state, maxWidth: maxWidth, measurementBuilder: measurementBuilder)
        if isIncoming {
            size.width = max(size.width, min(Self.minIncomingCardWidth, maxWidth))
        }
        return size
    }

    override public func handleTap(
        sender: UIGestureRecognizer,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
        renderItem: CVRenderItem,
    ) -> Bool {
        guard
            let componentView = componentView as? CVComponentViewTalerPayment,
            let acceptUri = talerPayment.acceptUri
        else {
            return false
        }
        let buttonView = componentView.cardView.buttonStack
        guard buttonView.superview != nil, buttonView.bounds.contains(sender.location(in: buttonView)) else {
            return false
        }
        TalerCardActions.accept(uri: acceptUri, threadUniqueId: talerPayment.threadUniqueId, isGroupShare: talerPayment.uris.count > 1)
        return true
    }

    public class CVComponentViewTalerPayment: NSObject, CVComponentView {
        fileprivate let cardView = CVTalerCardView(name: "CVTalerCardView")

        public var isDedicatedCellView = false

        public var rootView: UIView { cardView }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            cardView.reset()
        }
    }
}
