//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

/// Baut den "Taler"-Tab in der Medienuebersicht eines Chats (Zielbild 6.1).
/// Der Tab erscheint nur, wenn der Chat mindestens einen `TalerPaymentRecord`
/// hat. Statt `AllMediaCategory` um einen vierten Fall zu erweitern (das
/// wuerde neun erschöpfende Switches in drei Upstream-Dateien brechen), wird
/// das vorhandene Segment-Control unverletzt in einen Container neben einen
/// zusaetzlichen Taler-Knopf gelegt: die Mediensegmente verhalten sich exakt
/// wie bisher, der Taler-Knopf blendet einen eigenen Child-ViewController ueber
/// das Medien-Grid. Der einzige Eingriff in Upstream ist der install-Aufruf
/// in `AllMediaViewController.init`.
///
/// Halterung: der Coordinator bleibt so lange am Leben wie der Knopf bzw. das
/// Segment-Control (beide leben im navigationItem des Hosts); deren Actions
/// halten ihn stark fest.
@MainActor
final class TalerMediaTabCoordinator {

    private weak var host: AllMediaViewController?
    private let threadUniqueId: String
    private let chatName: String?
    private let isGroupThread: Bool
    private var talerViewController: TalerThreadPaymentsViewController?
    private weak var titleContainer: UIView?
    private weak var mediaSegmentControl: UISegmentedControl?
    private weak var tabButton: UIButton?
    private var installAttemptCount = 0

    private init(host: AllMediaViewController, threadUniqueId: String, chatName: String?, isGroupThread: Bool) {
        self.host = host
        self.threadUniqueId = threadUniqueId
        self.chatName = chatName
        self.isGroupThread = isGroupThread
    }

    static func install(host: AllMediaViewController, thread: TSThread, chatName: String?) {
        let coordinator = TalerMediaTabCoordinator(
            host: host,
            threadUniqueId: thread.uniqueId,
            chatName: chatName,
            isGroupThread: thread.isGroupThread
        )
        coordinator.checkForRecords()
    }

    // MARK: - Tab-Sichtbarkeit

    /// Der Tab wird nur eingebaut, wenn der Chat mindestens einen Vorgang hat
    /// (Nutzervorgabe). Kommen spaeter waehrend der offenen Uebersicht neue
    /// hinzu, erscheint der Tab beim naechsten Oeffnen.
    private func checkForRecords() {
        let threadUniqueId = self.threadUniqueId
        SSKEnvironment.shared.databaseStorageRef.asyncRead(
            block: { TalerPaymentStore.records(forThreadUniqueId: threadUniqueId, tx: $0) },
            completion: { records in
                DispatchQueue.main.async {
                    guard !records.isEmpty else { return }
                    self.installTab()
                }
            }
        )
    }

    private func installTab() {
        guard let host else { return }
        // Das Segment-Control existiert erst nach installViews() im
        // viewDidLoad des Tile-Controllers. Im Normalfall ist das DB-Ergebnis
        // spaeter da; zur Sicherheit ein paar Wiederholungen.
        guard let segmentControl = host.navigationItem.titleView as? UISegmentedControl else {
            installAttemptCount += 1
            guard installAttemptCount < 10 else {
                owsFailDebug("Segment-Control der Medienuebersicht nicht gefunden.")
                return
            }
            // Starkes self: bis der Knopf existiert, haelt der Retry-Block
            // den Coordinator fest, sonst wuerde die Kette abbrechen.
            DispatchQueue.main.async {
                self.installTab()
            }
            return
        }

        let container = UIView()
        segmentControl.removeFromSuperview()
        // Kein sizeToFit: `installViews()` im Accessories-Helper gibt dem
        // Segment zusaetzliche Breite (+20 pro Kategorie); die bleibt hier
        // erhalten, damit die Segmente nicht zusammengequetscht werden.
        container.addSubview(segmentControl)

        var buttonConfiguration = UIButton.Configuration.tinted()
        buttonConfiguration.cornerStyle = .capsule
        let tabButton = UIButton(configuration: buttonConfiguration)
        tabButton.tintColor = .Signal.accent
        // Starkes self: Action und Knopf halten den Coordinator am Leben.
        tabButton.addAction(UIAction { _ in self.talerButtonTapped() }, for: .touchUpInside)
        container.addSubview(tabButton)
        self.tabButton = tabButton

        // Medien-Segment gewaehlt: Taler-Ansicht wegdecken (das Segment
        // erledigt seinen eigenen Kategorie-Wechsel wie bisher).
        segmentControl.addAction(UIAction { [weak self] _ in self?.hideTalerTab() }, for: .valueChanged)

        titleContainer = container
        mediaSegmentControl = segmentControl

        updateTabButton(selected: false)
        host.navigationItem.titleView = container
        Self.activeCoordinators.add(self)
    }

    // MARK: - Select-Modus

    /// Lebende Coordinatoren, schwach referenziert (der Coordinator lebt
    /// hoechstens so lange wie sein Host). Die Einschubzeile in
    /// `MediaTileViewController.batchSelectionModeDidChange` ruft die
    /// Klassenmethode auf: der Accessories-Helper versteckt im Select-Modus
    /// nur sein eigenes Segment-Control; der Taler-Knopf daneben muss der
    /// Coordinator selbst erledigen.
    private static let activeCoordinators = NSHashTable<TalerMediaTabCoordinator>.weakObjects()

    /// Einschubpunkt fuer den Batch-Select-Modus (eine Zeile in
    /// `MediaTileViewController.batchSelectionModeDidChange`).
    static func batchSelectionModeDidChange(isInBatchSelectMode: Bool) {
        for coordinator in activeCoordinators.allObjects {
            coordinator.handleBatchSelectionModeChange(isInBatchSelectMode: isInBatchSelectMode)
        }
    }

    private func handleBatchSelectionModeChange(isInBatchSelectMode: Bool) {
        if isInBatchSelectMode, isTalerTabVisible {
            // Der Select-Modus wirkt nur aufs Medien-Grid; ist der Taler-Tab
            // aktiv, wird auf das Grid zurueckgeschaltet.
            hideTalerTab()
        }
        // Den ganzen Titel-Container verstecken (der Helper versteckt nur
        // das Segment-Control darin): im Select-Modus gehoert die Titelzeile
        // niemandem, danach stellt der Helper das Segment wieder her.
        titleContainer?.isHidden = isInBatchSelectMode
    }

    private var isTalerTabVisible: Bool {
        guard let talerViewController else { return false }
        return !talerViewController.view.isHidden
    }

    /// Container-Breite/-Hoehe neu festlegen; der Knopf aendert seine Breite
    /// mit der Konfiguration (tinted/filled).
    private func layoutTitleView() {
        guard
            let container = titleContainer,
            let segmentControl = mediaSegmentControl,
            let tabButton
        else { return }
        tabButton.sizeToFit()
        let gap: CGFloat = 8
        let height = max(segmentControl.frame.height, tabButton.frame.height)
        container.frame = CGRect(
            x: 0,
            y: 0,
            width: segmentControl.frame.width + gap + tabButton.frame.width,
            height: height
        )
        segmentControl.frame.origin = CGPoint(
            x: 0,
            y: (height - segmentControl.frame.height) / 2
        )
        tabButton.frame.origin = CGPoint(
            x: segmentControl.frame.maxX + gap,
            y: (height - tabButton.frame.height) / 2
        )
    }

    private func updateTabButton(selected: Bool) {
        guard let tabButton else { return }
        var configuration = selected ? UIButton.Configuration.filled() : UIButton.Configuration.tinted()
        configuration.title = TalerStrings.mediaTabTitle
        configuration.cornerStyle = .capsule
        tabButton.configuration = configuration
        layoutTitleView()
    }

    // MARK: - Tab ein-/ausblenden

    private func talerButtonTapped() {
        if let talerViewController, !talerViewController.view.isHidden {
            hideTalerTab()
        } else {
            showTalerTab()
        }
    }

    private func showTalerTab() {
        guard let host else { return }
        let viewController: TalerThreadPaymentsViewController
        if let existing = talerViewController {
            viewController = existing
        } else {
            viewController = TalerThreadPaymentsViewController(
                threadUniqueId: threadUniqueId,
                chatName: chatName,
                isGroupThread: isGroupThread
            )
            talerViewController = viewController
            host.addChild(viewController)
            host.view.addSubview(viewController.view)
            viewController.view.autoPinEdgesToSuperviewEdges()
            viewController.didMove(toParent: host)
        }
        // addChild loest kein viewWillAppear aus; Daten hier und in
        // viewWillAppear frisch laden.
        viewController.reloadFromDatabase()
        viewController.view.isHidden = false
        updateTabButton(selected: true)
    }

    private func hideTalerTab() {
        talerViewController?.view.isHidden = true
        updateTabButton(selected: false)
    }
}
