//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Crockford-Base32 in der GNUnet-/Taler-Variante (keine Fuellzeichen; beim
/// Dekodieren O->0, I/L->1, U->V). Portiert aus `Crockford.kt`
/// (signal-android), dort aus wallet-core `encodeCrock`/`decodeCrock`.
public enum Crockford {

    public enum Error: Swift.Error {
        case invalidCharacter
        case unexpectedLength(expected: Int, actual: Int)
    }

    private static let encodingTable = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    public static func encode(_ data: Data) -> String {
        let bytes = [UInt8](data)
        var result = ""
        var bitBuf = 0
        var numBits = 0
        var pos = 0
        while pos < bytes.count || numBits > 0 {
            if pos < bytes.count, numBits < 5 {
                bitBuf = (bitBuf << 8) | Int(bytes[pos])
                pos += 1
                numBits += 8
            }
            if numBits < 5 {
                bitBuf = bitBuf << (5 - numBits)
                numBits = 5
            }
            result.append(encodingTable[(bitBuf >> (numBits - 5)) & 31])
            numBits -= 5
            // Wie Kotlin (Int, 32 Bit) nur die relevanten Bits behalten.
            bitBuf &= (1 << numBits) - 1
        }
        return result
    }

    public static func decode(_ encoded: String) throws -> Data {
        let chars = Array(encoded)
        var out = [UInt8]()
        out.reserveCapacity(chars.count * 5 / 8)
        var bitBuf = 0
        var bitPos = 0
        var readPos = 0
        while readPos < chars.count || bitPos > 0 {
            if readPos < chars.count {
                bitBuf = (bitBuf << 5) | (try value(of: chars[readPos]))
                readPos += 1
                bitPos += 5
            }
            while bitPos >= 8 {
                out.append(UInt8((bitBuf >> (bitPos - 8)) & 0xff))
                bitPos -= 8
            }
            bitBuf &= (1 << bitPos) - 1
            if readPos == chars.count, bitPos > 0 {
                bitBuf = (bitBuf << (8 - bitPos)) & 0xff
                bitPos = bitBuf == 0 ? 0 : 8
            }
        }
        // Wie Kotlin: das Ergebnis passt in encoded.length * 5 / 8 Bytes, sonst
        // (nicht-null Restbits) ist die Eingabe ungueltig - dort als
        // Array-Ueberlauf, hier als Fehler.
        guard out.count <= chars.count * 5 / 8 else {
            throw Error.invalidCharacter
        }
        return Data(out)
    }

    /// Dekodiert und besteht auf exakt `expectedLength` Bytes.
    public static func decodeFixed(_ encoded: String, expectedLength: Int) throws -> Data {
        let decoded = try decode(encoded)
        guard decoded.count == expectedLength else {
            throw Error.unexpectedLength(expected: expectedLength, actual: decoded.count)
        }
        return decoded
    }

    private static func value(of character: Character) throws -> Int {
        var normalized = character
        switch character {
        case "o", "O": normalized = "0"
        case "i", "I", "l", "L": normalized = "1"
        case "u", "U": normalized = "V"
        default: break
        }
        guard let ascii = normalized.asciiValue else {
            throw Error.invalidCharacter
        }
        if ascii >= UInt8(ascii: "0"), ascii <= UInt8(ascii: "9") {
            return Int(ascii - UInt8(ascii: "0"))
        }
        let upper = Character(String(normalized).uppercased())
        guard let upperAscii = upper.asciiValue, upperAscii >= UInt8(ascii: "A"), upperAscii <= UInt8(ascii: "Z") else {
            throw Error.invalidCharacter
        }
        var skipped = 0
        if upperAscii > UInt8(ascii: "I") { skipped += 1 }
        if upperAscii > UInt8(ascii: "L") { skipped += 1 }
        if upperAscii > UInt8(ascii: "O") { skipped += 1 }
        if upperAscii > UInt8(ascii: "U") { skipped += 1 }
        return Int(upperAscii - UInt8(ascii: "A")) + 10 - skipped
    }
}
