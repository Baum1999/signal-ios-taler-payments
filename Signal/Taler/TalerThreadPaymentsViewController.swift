//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import SignalServiceKit
import SignalUI
import UIKit

/// Inhalt des "Taler"-Tabs in der Medienuebersicht (Zielbild 6.1): Kopfzeile
/// aus der S5-Verdichtung (`TalerThreadAggregate`/`TalerThreadHeadline`),
/// Filter-Chips (Alle/Offen/Erhalten/Gesendet) und eine Liste aller Vorgaenge
/// des Chats. Tippen springt zur Nachricht im Chat; annehmen/abbrechen gibt
/// es hier bewusst nicht (Regel 1: Signal bewegt kein Geld).
///
/// Alle Betraege stammen ausschliesslich aus den Records (Regel 5), die URI
/// erscheint nie (Regel 4). Daten werden asynchron geladen, nie im
/// Layout-Pfad; aktualisiert wird bei viewWillAppear und bei DB-Aenderungen
/// an den Taler-Tabellen.
final class TalerThreadPaymentsViewController: OWSViewController {

    private let threadUniqueId: String
    /// Anzeigename des Gegenuebers, nur im 1:1-Chat gesetzt.
    private let chatName: String?
    private let isGroupThread: Bool

    private var records: [TalerPaymentRecord] = []
    private var filter: TalerThreadFilter = .all
    private var lastHeaderWidth: CGFloat = 0

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(TalerPaymentRowCell.self, forCellReuseIdentifier: TalerPaymentRowCell.reuseIdentifier)
        tableView.backgroundColor = .Signal.groupedBackground
        tableView.rowHeight = UITableView.automaticDimension
        return tableView
    }()

    private lazy var headerStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [headlineLabel, latestLabel, contextLabel, filterSegmentedControl])
        stack.axis = .vertical
        stack.spacing = 8
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 16, left: 20, bottom: 12, right: 20)
        return stack
    }()

    /// Haelt den Kopfzeilen-Stack; als tableHeaderView muss eine
    /// groessenberechenbare Container-View liegen, nicht der Stack selbst.
    private lazy var headerContainer: UIView = {
        let container = UIView()
        container.addSubview(headerStack)
        headerStack.autoPinEdgesToSuperviewEdges()
        return container
    }()

    private lazy var headlineLabel: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeHeadline.semibold()
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        return label
    }()

    private lazy var latestLabel: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeSubheadline
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .Signal.secondaryLabel
        label.numberOfLines = 0
        return label
    }()

    private lazy var contextLabel: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeSubheadline
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .Signal.secondaryLabel
        label.numberOfLines = 0
        return label
    }()

    private lazy var filterSegmentedControl: UISegmentedControl = {
        let items = [
            TalerStrings.threadFilterAll,
            TalerStrings.threadFilterOpen,
            TalerStrings.threadFilterReceived,
            TalerStrings.threadFilterSent,
        ]
        let segmentedControl = UISegmentedControl(items: items)
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.addAction(
            UIAction { [weak self] action in
                self?.filterChanged(action.sender as? UISegmentedControl)
            },
            for: .valueChanged,
        )
        return segmentedControl
    }()

    private lazy var emptyStateLabel: UILabel = {
        let label = UILabel()
        label.text = TalerStrings.threadEmptyFilterMessage
        label.font = .dynamicTypeSubheadline
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .Signal.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    // MARK: - Init

    init(threadUniqueId: String, chatName: String?, isGroupThread: Bool) {
        self.threadUniqueId = threadUniqueId
        self.chatName = chatName
        self.isGroupThread = isGroupThread
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lebenszyklus

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.groupedBackground

        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        tableView.autoPinEdgesToSuperviewEdges()

        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyStateLabel)
        emptyStateLabel.autoPinWidthToSuperview(withMargin: 32)
        emptyStateLabel.autoVCenterInSuperview()

        tableView.tableHeaderView = headerContainer

        DependenciesBridge.shared.databaseChangeObserver.appendDatabaseChangeDelegate(self)

        reloadFromDatabase()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadFromDatabase()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Beim ersten Durchlauf ist die Tabellenbreite noch 0; die Header-
        // Hoehe haengt aber von der Breite ab (Umbruch der Kopfzeile).
        if lastHeaderWidth != tableView.bounds.width {
            lastHeaderWidth = tableView.bounds.width
            relayoutTableHeader()
        }
    }

    // MARK: - Daten

    /// Laedt die Vorgaenge asynchron; sichtbares Update nur auf dem
    /// Haupt-Thread nach dem Lesen.
    func reloadFromDatabase() {
        let threadUniqueId = self.threadUniqueId
        SSKEnvironment.shared.databaseStorageRef.asyncRead(
            block: { TalerPaymentStore.records(forThreadUniqueId: threadUniqueId, tx: $0) },
            completion: { [weak self] records in
                DispatchQueue.main.async {
                    self?.apply(records: records)
                }
            }
        )
    }

    private func apply(records: [TalerPaymentRecord]) {
        self.records = records
        updateContent()
    }

    /// Gefiltert und nach letzter Aktivitaet absteigend sortiert;
    /// Gleichstand bricht die URI (deterministisch, wie in S5).
    private var filteredRecords: [TalerPaymentRecord] {
        records.filter { filter.matches($0) }.sorted { lhs, rhs in
            let lhsActivity = TalerPaymentStore.latestActivityAt(lhs)
            let rhsActivity = TalerPaymentStore.latestActivityAt(rhs)
            if lhsActivity != rhsActivity {
                return lhsActivity > rhsActivity
            }
            return lhs.uri > rhs.uri
        }
    }

    // MARK: - Darstellung

    private func updateContent() {
        let aggregate = TalerThreadAggregate.build(records)
        let headline = TalerThreadHeadline.from(aggregate)

        let headlineParts = TalerThreadHeadlineFormat.label(
            for: headline,
            chatName: isGroupThread ? nil : chatName
        )
        if headlineParts.text.isEmpty {
            headlineLabel.isHidden = true
        } else {
            headlineLabel.text = "\(headlineParts.icon) \(headlineParts.text)"
            headlineLabel.textColor = Self.headlineColor(headline)
            headlineLabel.isHidden = false
        }

        var latestParts = TalerThreadSummaryFormat.latestLineParts(
            aggregate,
            receivedLabel: TalerStrings.threadLatestReceived,
            sentLabel: TalerStrings.threadLatestSent,
            locale: Locale.current
        )
        if latestParts.isEmpty {
            latestLabel.isHidden = true
        } else {
            if let latest = aggregate.latest {
                latestParts.append(Self.relativeTime(of: latest))
            }
            latestLabel.text = TalerStrings.threadLatestPrefix + latestParts.joined(separator: " · ")
            latestLabel.isHidden = false
        }

        if let contextLine = TalerThreadSummaryFormat.contextLine(aggregate, locale: Locale.current) {
            contextLabel.text = TalerStrings.threadBalancePrefix + contextLine
            contextLabel.isHidden = false
        } else {
            contextLabel.isHidden = true
        }

        emptyStateLabel.isHidden = !filteredRecords.isEmpty

        relayoutTableHeader()
        tableView.reloadData()
    }

    /// Hoch-Runter-Rechnen der Header-Hoehe (Label-Inhalte und Breite
    /// aendern sich).
    private func relayoutTableHeader() {
        guard let header = tableView.tableHeaderView, tableView.bounds.width > 0 else { return }
        let width = tableView.bounds.width
        let fittingSize = header.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        header.frame = CGRect(origin: .zero, size: CGSize(width: width, height: fittingSize.height))
        tableView.tableHeaderView = header
    }

    private func filterChanged(_ sender: UISegmentedControl?) {
        guard
            let sender,
            let selectedFilter = TalerThreadFilter.allCases[safe: sender.selectedSegmentIndex]
        else {
            owsFailDebug("Unbekannter Filter-Index.")
            return
        }
        filter = selectedFilter
        updateContent()
    }

    // MARK: - Formatierung

    /// Farbe der Kopfzeile nach Rangfolge: Handlungsbedarf auffaellig,
    /// Wissensluecke neutral, erledigt positiv. Dieselben Tonalitaeten wie
    /// die Zahlungskarte (S3), ueber das gemeinsame Farbmapping
    /// (`TalerToneColors`, Theme-/Dark-Mode-faehig).
    private static func headlineColor(_ headline: TalerThreadHeadline) -> UIColor {
        switch headline {
        case .waitingForMe, .waitingForOther, .waitingForBoth:
            return TalerToneColors.color(for: TalerCardModel.Tone.waiting)
        case .unverifiable:
            return TalerToneColors.color(for: TalerCardModel.Tone.neutral)
        case .allSettled:
            return TalerToneColors.color(for: TalerCardModel.Tone.ok)
        case .empty:
            return .Signal.label
        }
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .short
        return formatter
    }()

    private static func relativeTime(of record: TalerPaymentRecord) -> String {
        let timestamp = TalerPaymentStore.latestActivityAt(record)
        let date = Date(millisecondsSince1970: UInt64(clamping: timestamp))
        return relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }

    /// Statuszeile einer Listezeile - dasselbe Bild wie der Kompaktstatus der
    /// Karte (S3), nur mit dessen oeffentlichen Bausteinen nachgebaut.
    private static func statusText(of record: TalerPaymentRecord, chatName: String?) -> String {
        if record.status == .offen, record.uriKind == .payPush {
            if record.isOwnPayment {
                return String(
                    format: TalerStrings.statusWaitingForRecipientFormat,
                    nonEmpty(chatName) ?? TalerStrings.recipientFallback
                )
            }
            return TalerStrings.statusWaitingForAcceptance
        }
        if record.status == .angenommen, record.uriKind == .payPush {
            if record.isOwnPayment {
                return String(
                    format: TalerStrings.statusSentConfirmedFormat,
                    nonEmpty(chatName) ?? TalerStrings.recipientFallback
                )
            }
            return String(
                format: TalerStrings.statusAcceptedFromFormat,
                nonEmpty(chatName) ?? TalerStrings.senderFallback
            )
        }
        return TalerCardModel.plainStatusLabel(record.status)
    }

    private static func statusColor(_ record: TalerPaymentRecord) -> UIColor {
        TalerToneColors.color(for: record.status)
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

// MARK: - UITableViewDataSource

extension TalerThreadPaymentsViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filteredRecords.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard
            let cell = tableView.dequeueReusableCell(
                withIdentifier: TalerPaymentRowCell.reuseIdentifier,
                for: indexPath
            ) as? TalerPaymentRowCell
        else {
            owsFailDebug("Falscher Zelltyp.")
            return UITableViewCell()
        }
        let record = filteredRecords[indexPath.row]
        let chatName = isGroupThread ? nil : self.chatName
        cell.configure(
            directionIn: TalerCardModel.isDirectionIn(kind: record.uriKind, isOwnPayment: record.isOwnPayment),
            amountText: Self.amountText(of: record),
            statusText: Self.statusText(of: record, chatName: chatName),
            statusColor: Self.statusColor(record),
            detailText: Self.detailText(of: record)
        )
        return cell
    }

    private static func amountText(of record: TalerPaymentRecord) -> String {
        var parts: [String] = []
        if let amount = record.amount, !amount.isEmpty {
            parts.append(TalerCardModel.formatAmount(amount))
        } else {
            // Regel 5: ohne verifizierten Betrag ein Platzhalter, nie eine
            // Zahl aus dem Nachrichtentext.
            parts.append(TalerStrings.amountPending)
        }
        if let currency = record.currency, !currency.isEmpty {
            parts.append(currency)
        }
        return parts.joined(separator: " ")
    }

    private static func detailText(of record: TalerPaymentRecord) -> String {
        var parts: [String] = []
        if let summary = nonEmpty(record.summary) {
            parts.append(summary)
        }
        parts.append(relativeTime(of: record))
        if let host = TalerCardModel.displayHost(record.exchangeBaseUrl) {
            parts.append(host)
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - UITableViewDelegate

extension TalerThreadPaymentsViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let record = filteredRecords[indexPath.row]
        // Regel 4: die URI ist ein Inhaberpapier - sie wird weder geloggt
        // noch angezeigt, sondern nur zum Sprung zur Nachricht benutzt.
        let uri = record.uri
        SSKEnvironment.shared.databaseStorageRef.asyncRead(
            block: { (tx: DBReadTransaction) -> String? in
                guard let interactionId = TalerPaymentStore.interactionIds(forUri: uri, tx: tx).first else {
                    return nil
                }
                let sql = """
                    SELECT \(InteractionRecord.columnName(.uniqueId)) FROM \(InteractionRecord.databaseTableName)
                    WHERE \(InteractionRecord.columnName(.id)) = ?
                    """
                return try? String.fetchOne(tx.database, sql: sql, arguments: [interactionId])
            },
            completion: { [weak self] interactionUniqueId in
                DispatchQueue.main.async {
                    guard let self, let interactionUniqueId else { return }
                    // Derselbe Sprung, den Medienuebersicht und Suche nutzen
                    // (MediaPageViewController/ConversationSearchViewController).
                    SignalApp.shared.presentConversationForThread(
                        threadUniqueId: self.threadUniqueId,
                        focusMessageId: interactionUniqueId,
                        animated: true
                    )
                }
            }
        )
    }
}

// MARK: - DatabaseChangeDelegate

extension TalerThreadPaymentsViewController: DatabaseChangeDelegate {

    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        guard
            databaseChanges.didUpdate(tableName: "TalerPayment")
                || databaseChanges.didUpdate(tableName: "TalerPaymentInteraction")
        else {
            return
        }
        reloadFromDatabase()
    }

    func databaseChangesDidUpdateExternally() {
        reloadFromDatabase()
    }

    func databaseChangesDidReset() {
        reloadFromDatabase()
    }
}

// MARK: - Zelle

/// Eine Vorgangszeile: Richtungspfeil, Betrag + Waehrung, Status rechts,
/// darunter Summary, relative Zeit und Exchange-Host.
private final class TalerPaymentRowCell: UITableViewCell {

    static let reuseIdentifier = "TalerPaymentRowCell"

    private let arrowLabel = UILabel()
    private let amountLabel = UILabel()
    private let statusLabel = UILabel()
    private let detailLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .Signal.secondaryGroupedBackground

        for label in [arrowLabel, amountLabel, statusLabel, detailLabel] {
            label.adjustsFontForContentSizeCategory = true
        }
        arrowLabel.font = .dynamicTypeTitle3.semibold()
        arrowLabel.textColor = .Signal.label
        amountLabel.font = .dynamicTypeTitle3.semibold()
        amountLabel.textColor = .Signal.label
        amountLabel.numberOfLines = 1
        amountLabel.lineBreakMode = .byTruncatingTail
        amountLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusLabel.font = .dynamicTypeFootnote.semibold()
        statusLabel.numberOfLines = 0
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        detailLabel.font = .dynamicTypeSubheadline
        detailLabel.textColor = .Signal.secondaryLabel
        detailLabel.numberOfLines = 0

        let topRow = UIStackView(arrangedSubviews: [arrowLabel, amountLabel, statusLabel])
        topRow.axis = .horizontal
        topRow.spacing = 8
        topRow.alignment = .firstBaseline

        let outerStack = UIStackView(arrangedSubviews: [topRow, detailLabel])
        outerStack.axis = .vertical
        outerStack.spacing = 4
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(outerStack)
        outerStack.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(margin: 12))

        selectionStyle = .default
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        directionIn: Bool,
        amountText: String,
        statusText: String,
        statusColor: UIColor,
        detailText: String
    ) {
        // ↓ = an mich, ↑ = von mir (wie auf der Karte, S3).
        arrowLabel.text = directionIn ? "↓" : "↑"
        amountLabel.text = amountText
        statusLabel.text = statusText
        statusLabel.textColor = statusColor
        detailLabel.text = detailText
        detailLabel.isHidden = detailText.isEmpty
    }
}
