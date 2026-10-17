//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit
import UniformTypeIdentifiers

/// Rendert die Taler-Zahlungskarte einer Nachricht offscreen zu einem
/// PNG-Schnappschuss (Zielbild 4.9, Android `TalerForwardGate.attachPaymentSnapshot`
/// bzw. `TalerMenuActions.onCopyAsImageFromMenu`). Breite 1080 px: gemessen
/// und gelayoutet wird bei 360 pt, gerendert mit 3x-Skalierung, damit der
/// Text im Bild die gewohnte relative Groesse behaelt (Android misst bei
/// 1080 px mit dichte-skalierten sp-Texten).
///
/// Das Bild zeigt nur verifizierte Daten (entschluesselter Contract bzw.
/// Exchange-Status, Regel 5) und enthaelt KEINE URI - weitergeleitet oder
/// kopiert wird damit kein Inhaberpapier. Ohne Knoepfe: `showAcceptButton`
/// ist immer false.
enum TalerCardSnapshot {

    /// Breite des PNG in Pixeln (Vorgabe Zielbild 4.9).
    static let snapshotWidthPx: CGFloat = 1080
    /// Logische Breite in Punkten; mit `snapshotScale` multipliziert ergibt
    /// sich exakt `snapshotWidthPx`.
    private static let logicalWidth: CGFloat = 360
    private static let snapshotScale: CGFloat = 3

    // MARK: - Schnappschuss

    /// Rendert die Karte der Nachricht (Einzel- wie Sammelkarte; dasselbe
    /// `buildState` wie in der Konversation) zu einem 1080 px breiten PNG.
    /// `nil`, wenn die Nachricht keine (beobachtbare) Taler-Zahlung mehr ist.
    static func image(messageUniqueId: String) -> UIImage? {
        AssertIsOnMainThread()

        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        guard
            let prepared = databaseStorage.read(block: { tx -> CVTalerCardView.State? in
                guard
                    let message = TSMessage.fetchMessageViaCache(uniqueId: messageUniqueId, transaction: tx),
                    let thread = TSThread.fetchViaCache(uniqueId: message.uniqueThreadId, transaction: tx)
                else {
                    return nil
                }
                guard let talerPayment = CVComponentTalerPayment.buildState(message: message, thread: thread, transaction: tx) else {
                    return nil
                }
                // Eigenes Standalone-Style: die echte ConversationStyle haengt
                // am View-Controller, hier reicht die chatColor des Threads.
                let conversationStyle = ConversationStyle(
                    type: .default,
                    thread: thread,
                    viewWidth: Self.logicalWidth,
                    hasWallpaper: false,
                    shouldDimWallpaperInDarkMode: false,
                    chatColor: ConversationViewController.loadChatColor(for: thread, tx: tx),
                )
                return CVTalerCardView.State(
                    model: talerPayment.model,
                    showAcceptButton: false,
                    // Immer Label-Farben: das PNG hat einen Themen-Hintergrund,
                    // weisse Text-Farben ausgehender Blasen waeren unlesbar.
                    isIncoming: true,
                    conversationStyle: conversationStyle,
                )
            })
        else {
            return nil
        }

        // Messen (thread-sicher wie alle CV-Ansichten) und dann rendern.
        let measurementBuilder = CVCellMeasurement.Builder()
        let measuredSize = CVTalerCardView.measurement(
            for: prepared,
            maxWidth: Self.logicalWidth,
            measurementBuilder: measurementBuilder,
        )
        measurementBuilder.cellSize = measuredSize
        let cellMeasurement = measurementBuilder.build()

        let cardView = CVTalerCardView(name: "TalerCardSnapshot")
        let cardSize = CGSize(width: Self.logicalWidth, height: measuredSize.height)
        cardView.frame = CGRect(origin: .zero, size: cardSize)
        cardView.configureForRendering(state: prepared, cellMeasurement: cellMeasurement)
        cardView.layoutIfNeeded()

        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = Self.snapshotScale
        let renderer = UIGraphicsImageRenderer(size: cardSize, format: rendererFormat)
        return renderer.image { rendererContext in
            // Die Karte selbst ist transparent (sie liegt sonst in einer
            // Blase); das PNG bekommt einen Themen-Hintergrund.
            Theme.backgroundColor.setFill()
            rendererContext.fill(CGRect(origin: .zero, size: cardSize))
            cardView.layer.render(in: rendererContext.cgContext)
        }
    }

    // MARK: - Verbraucher

    /// "Als Bild kopieren": das PNG in die Zwischenablage. Still, wenn es
    /// keine Karte (mehr) gibt.
    static func copyToPasteboard(messageUniqueId: String) {
        AssertIsOnMainThread()
        guard let image = image(messageUniqueId: messageUniqueId) else {
            return
        }
        UIPasteboard.general.image = image
    }

    /// "Als Bild weiterleiten": das PNG als Bild-Anhang (Android:
    /// "Taler-Zahlung.png", image/png). `nil`, wenn es keine Karte (mehr)
    /// gibt oder die Daten nicht in einen Anhang umwandelbar sind.
    static func pngAttachment(messageUniqueId: String) -> PreviewableAttachment? {
        AssertIsOnMainThread()
        guard let image = image(messageUniqueId: messageUniqueId) else {
            return nil
        }
        guard let pngData = image.pngData() else {
            owsFailDebug("PNG-Daten des Karten-Schnappschusses nicht verfuegbar.")
            return nil
        }
        do {
            let dataSource = try DataSourcePath(writingTempFileData: pngData, fileExtension: "png")
            dataSource.sourceFilename = "Taler-Zahlung.png"
            return try PreviewableAttachment.imageAttachment(dataSource: dataSource, dataUTI: UTType.png.identifier)
        } catch {
            owsFailDebug("Karten-Schnappschuss konnte nicht in einen Anhang umgewandelt werden: \(error)")
            return nil
        }
    }
}
