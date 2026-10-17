//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// NaCl-SecretBox (XSalsa20-Poly1305), mit dem Taler Contract-Terms ablegt.
/// Portiert aus `XSalsa20Poly1305.kt` (signal-android); Gegenstueck zu
/// wallet-cores `xsalsa20Poly1305Decrypt` (`@noble/ciphers`).
///
/// Format wie `crypto_secretbox_easy`: 16-Byte-Poly1305-Tag vorangestellt,
/// danach der Ciphertext. Poly1305 folgt TweetNaCls `crypto_onetimeauth`.
public enum XSalsa20Poly1305 {
    private static let tagSize = 16
    private static let sigma: [UInt32] = [0x6170_7865, 0x3320_646e, 0x7962_2d32, 0x6b20_6574]

    /// Gibt den Klartext zurueck, oder `nil`, wenn der Tag nicht passt.
    public static func open(_ ciphertext: Data, nonce: Data, key: Data) -> Data? {
        guard key.count == 32, nonce.count == 24, ciphertext.count >= tagSize else {
            return nil
        }
        let keyBytes = [UInt8](key)
        let nonceBytes = [UInt8](nonce)
        let box = [UInt8](ciphertext)

        let subKey = hsalsa20(key: keyBytes, input: Array(nonceBytes[0..<16]))
        let streamNonce = Array(nonceBytes[16..<24])
        let body = Array(box[tagSize...])

        let firstBlock = salsa20Block(key: subKey, nonce: streamNonce, counter: 0)
        let expectedTag = poly1305(message: body, key: Array(firstBlock[0..<32]))
        guard constantTimeEquals(expectedTag, Array(box[0..<tagSize])) else {
            return nil
        }
        return Data(xorKeyStream(body, subKey: subKey, streamNonce: streamNonce, firstBlock: firstBlock))
    }

    /// Gegenrichtung zu `open` - nur fuer Tests (Rundlauf) gedacht.
    public static func seal(_ plaintext: Data, nonce: Data, key: Data) -> Data? {
        guard key.count == 32, nonce.count == 24 else {
            return nil
        }
        let keyBytes = [UInt8](key)
        let nonceBytes = [UInt8](nonce)
        let subKey = hsalsa20(key: keyBytes, input: Array(nonceBytes[0..<16]))
        let streamNonce = Array(nonceBytes[16..<24])
        let firstBlock = salsa20Block(key: subKey, nonce: streamNonce, counter: 0)
        let body = xorKeyStream([UInt8](plaintext), subKey: subKey, streamNonce: streamNonce, firstBlock: firstBlock)
        let tag = poly1305(message: body, key: Array(firstBlock[0..<32]))
        return Data(tag + body)
    }

    // MARK: - Salsa20

    private static func xorKeyStream(_ input: [UInt8], subKey: [UInt8], streamNonce: [UInt8], firstBlock: [UInt8]) -> [UInt8] {
        var output = [UInt8](repeating: 0, count: input.count)
        var counter: UInt64 = 0
        var keyStream = firstBlock
        // Die ersten 32 Bytes des ersten Blocks sind der Poly1305-Schluessel.
        var keyStreamOffset = 32
        for offset in 0..<input.count {
            if keyStreamOffset == 64 {
                counter += 1
                keyStream = salsa20Block(key: subKey, nonce: streamNonce, counter: counter)
                keyStreamOffset = 0
            }
            output[offset] = input[offset] ^ keyStream[keyStreamOffset]
            keyStreamOffset += 1
        }
        return output
    }

    private static func hsalsa20(key: [UInt8], input: [UInt8]) -> [UInt8] {
        let state = initialState(key: key, input: input)
        let mixed = rounds(state)
        var out = [UInt8]()
        out.reserveCapacity(32)
        for index in [0, 5, 10, 15, 6, 7, 8, 9] {
            appendLittleEndian(&out, mixed[index])
        }
        return out
    }

    private static func salsa20Block(key: [UInt8], nonce: [UInt8], counter: UInt64) -> [UInt8] {
        var input = nonce
        appendLittleEndian(&input, UInt32(truncatingIfNeeded: counter))
        appendLittleEndian(&input, UInt32(truncatingIfNeeded: counter >> 32))
        let state = initialState(key: key, input: input)
        let mixed = rounds(state)
        var out = [UInt8]()
        out.reserveCapacity(64)
        for i in 0..<16 {
            appendLittleEndian(&out, mixed[i] &+ state[i])
        }
        return out
    }

    private static func initialState(key: [UInt8], input: [UInt8]) -> [UInt32] {
        var state = [UInt32](repeating: 0, count: 16)
        state[0] = sigma[0]
        state[5] = sigma[1]
        state[10] = sigma[2]
        state[15] = sigma[3]
        for i in 0..<4 {
            state[1 + i] = readLittleEndian(key, i * 4)
            state[11 + i] = readLittleEndian(key, 16 + i * 4)
            state[6 + i] = readLittleEndian(input, i * 4)
        }
        return state
    }

    private static func rounds(_ state: [UInt32]) -> [UInt32] {
        var x = state
        for _ in 0..<10 {
            quarterRound(&x, 0, 4, 8, 12)
            quarterRound(&x, 5, 9, 13, 1)
            quarterRound(&x, 10, 14, 2, 6)
            quarterRound(&x, 15, 3, 7, 11)

            quarterRound(&x, 0, 1, 2, 3)
            quarterRound(&x, 5, 6, 7, 4)
            quarterRound(&x, 10, 11, 8, 9)
            quarterRound(&x, 15, 12, 13, 14)
        }
        return x
    }

    private static func quarterRound(_ x: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int) {
        x[b] ^= rotateLeft(x[a] &+ x[d], 7)
        x[c] ^= rotateLeft(x[b] &+ x[a], 9)
        x[d] ^= rotateLeft(x[c] &+ x[b], 13)
        x[a] ^= rotateLeft(x[d] &+ x[c], 18)
    }

    private static func rotateLeft(_ value: UInt32, _ count: UInt32) -> UInt32 {
        (value << count) | (value >> (32 - count))
    }

    private static func readLittleEndian(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) |
            (UInt32(bytes[offset + 1]) << 8) |
            (UInt32(bytes[offset + 2]) << 16) |
            (UInt32(bytes[offset + 3]) << 24)
    }

    private static func appendLittleEndian(_ bytes: inout [UInt8], _ value: UInt32) {
        bytes.append(UInt8(truncatingIfNeeded: value))
        bytes.append(UInt8(truncatingIfNeeded: value >> 8))
        bytes.append(UInt8(truncatingIfNeeded: value >> 16))
        bytes.append(UInt8(truncatingIfNeeded: value >> 24))
    }

    // MARK: - Poly1305 (TweetNaCl crypto_onetimeauth)

    private static let minusP: [UInt32] = [5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 252]

    private static func add1305(_ h: inout [UInt32], _ c: [UInt32]) {
        var u: UInt32 = 0
        for j in 0..<17 {
            u = u &+ h[j] &+ c[j]
            h[j] = u & 255
            u >>= 8
        }
    }

    private static func poly1305(message: [UInt8], key: [UInt8]) -> [UInt8] {
        var r = [UInt32](repeating: 0, count: 17)
        var h = [UInt32](repeating: 0, count: 17)
        for j in 0..<16 { r[j] = UInt32(key[j]) }
        r[3] &= 15
        r[4] &= 252
        r[7] &= 15
        r[8] &= 252
        r[11] &= 15
        r[12] &= 252
        r[15] &= 15

        var position = 0
        var remaining = message.count
        while remaining > 0 {
            var c = [UInt32](repeating: 0, count: 17)
            var j = 0
            while j < 16, j < remaining {
                c[j] = UInt32(message[position + j])
                j += 1
            }
            c[j] = 1
            position += j
            remaining -= j
            add1305(&h, c)
            var x = [UInt32](repeating: 0, count: 17)
            for i in 0..<17 {
                var sum: UInt32 = 0
                for k in 0..<17 {
                    let factor = k <= i ? r[i - k] : 320 &* r[i + 17 - k]
                    sum = sum &+ (h[k] &* factor)
                }
                x[i] = sum
            }
            h = x
            var u: UInt32 = 0
            for k in 0..<16 {
                u = u &+ h[k]
                h[k] = u & 255
                u >>= 8
            }
            u = u &+ h[16]
            h[16] = u & 3
            u = 5 &* (u >> 2)
            for k in 0..<16 {
                u = u &+ h[k]
                h[k] = u & 255
                u >>= 8
            }
            u = u &+ h[16]
            h[16] = u
        }

        let g = h
        add1305(&h, minusP)
        let s: UInt32 = 0 &- (h[16] >> 7)
        for j in 0..<17 {
            h[j] ^= s & (g[j] ^ h[j])
        }
        var c = [UInt32](repeating: 0, count: 17)
        for j in 0..<16 { c[j] = UInt32(key[j + 16]) }
        add1305(&h, c)
        return (0..<16).map { UInt8(truncatingIfNeeded: h[$0]) }
    }

    private static func constantTimeEquals(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else {
            return false
        }
        var difference: UInt8 = 0
        for i in 0..<a.count {
            difference |= a[i] ^ b[i]
        }
        return difference == 0
    }
}
