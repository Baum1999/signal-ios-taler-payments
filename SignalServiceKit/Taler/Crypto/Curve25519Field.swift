//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Minimale Arithmetik in GF(2^255 - 19), genau so viel, wie die Konvertierung
/// eines Ed25519-Public-Keys auf die Montgomery-Kurve braucht
/// (`u = (1 + y) / (1 - y)`). CryptoKit bietet diese Konvertierung nicht an.
///
/// Darstellung und Routinen folgen TweetNaCl (16 Limbs zu 16 Bit in Int64;
/// `car25519`, `M`, `inv25519`, `pack25519`, `unpack25519`). Nicht
/// seitenkanalresistent verwendet: der einzige Eingabewert ist ein
/// oeffentlicher Schluessel.
enum Curve25519Field {
    typealias Element = [Int64]

    private static func zero() -> Element { Element(repeating: 0, count: 16) }

    private static func one() -> Element {
        var e = zero()
        e[0] = 1
        return e
    }

    private static func carry(_ o: inout Element) {
        for i in 0..<16 {
            o[i] += 1 << 16
            let c = o[i] >> 16
            if i < 15 {
                o[i + 1] += c - 1
            } else {
                o[0] += (c - 1) + 37 * (c - 1)
            }
            o[i] -= c << 16
        }
    }

    private static func select(_ p: inout Element, _ q: inout Element, _ b: Int64) {
        let c = ~(b - 1)
        for i in 0..<16 {
            let t = c & (p[i] ^ q[i])
            p[i] ^= t
            q[i] ^= t
        }
    }

    private static func add(_ a: Element, _ b: Element) -> Element {
        var o = zero()
        for i in 0..<16 { o[i] = a[i] + b[i] }
        return o
    }

    private static func sub(_ a: Element, _ b: Element) -> Element {
        var o = zero()
        for i in 0..<16 { o[i] = a[i] - b[i] }
        return o
    }

    private static func mul(_ a: Element, _ b: Element) -> Element {
        var t = [Int64](repeating: 0, count: 31)
        for i in 0..<16 {
            for j in 0..<16 {
                t[i + j] += a[i] * b[j]
            }
        }
        for i in 0..<15 {
            t[i] += 38 * t[i + 16]
        }
        var o = Array(t[0..<16])
        carry(&o)
        carry(&o)
        return o
    }

    private static func invert(_ input: Element) -> Element {
        var c = input
        var a = 253
        while a >= 0 {
            c = mul(c, c)
            if a != 2, a != 4 {
                c = mul(c, input)
            }
            a -= 1
        }
        return c
    }

    private static func unpack(_ n: [UInt8]) -> Element {
        var o = zero()
        for i in 0..<16 {
            o[i] = Int64(n[2 * i]) + (Int64(n[2 * i + 1]) << 8)
        }
        o[15] &= 0x7fff
        return o
    }

    private static func pack(_ n: Element) -> [UInt8] {
        var t = n
        carry(&t)
        carry(&t)
        carry(&t)
        var m = zero()
        for _ in 0..<2 {
            m[0] = t[0] - 0xffed
            for i in 1..<15 {
                m[i] = t[i] - 0xffff - ((m[i - 1] >> 16) & 1)
                m[i - 1] &= 0xffff
            }
            m[15] = t[15] - 0x7fff - ((m[14] >> 16) & 1)
            let b = (m[15] >> 16) & 1
            m[14] &= 0xffff
            select(&t, &m, 1 - b)
        }
        var o = [UInt8](repeating: 0, count: 32)
        for i in 0..<16 {
            o[2 * i] = UInt8(truncatingIfNeeded: t[i] & 0xff)
            o[2 * i + 1] = UInt8(truncatingIfNeeded: t[i] >> 8)
        }
        return o
    }

    /// Ed25519-Public-Key (y, Vorzeichenbit ignoriert) -> Montgomery-u.
    /// Gegenstueck zu `ed25519.utils.toMontgomery` (wallet-core) bzw.
    /// `Ed25519.toMontgomery` (signal-android).
    static func edwardsToMontgomery(_ publicKey: Data) -> Data? {
        guard publicKey.count == 32 else {
            return nil
        }
        let y = unpack([UInt8](publicKey))
        let numerator = add(one(), y)
        let denominator = sub(one(), y)
        let packedDenominator = pack(denominator)
        if packedDenominator.allSatisfy({ $0 == 0 }) {
            // y == 1: kein gueltiger Punkt (Android: modInverse wirft).
            return nil
        }
        return Data(pack(mul(numerator, invert(denominator))))
    }
}
