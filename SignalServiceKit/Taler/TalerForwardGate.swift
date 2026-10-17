//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Rein rechnerisches Weiterleiten-Gate (Zielbild 4.9, Android
/// `TalerForwardGate.forwardAsText` mit `anyOpen`): entscheidet, ob
/// "Als Text weiterleiten" die rohen URI(s) nur nach einer Warnung
/// weitergeben darf. "Als Bild" ist von der Frage nicht betroffen - das
/// PNG enthaelt keine URI und gibt damit kein Inhaberpapier weiter.
public enum TalerForwardGate {

    /// `true`, wenn mindestens einer der Anteile noch OFFEN ist. Nur dann
    /// besteht beim Weiterleiten der URI(s) das Risiko, dass wer den Link
    /// zuerst oeffnet, genau DIESEN Anteil einloest (Inhaberpapier); sind
    /// alle Anteile entschieden oder abgelaufen, besteht das Risiko nicht
    /// mehr. Fehlende Records (`nil`) zaehlen wie auf Android (`any { it ==
    /// OFFEN }`) als nicht offen.
    public static func needsOpenShareWarning(statuses: [TalerPaymentStatus?]) -> Bool {
        statuses.contains { $0 == .offen }
    }
}
