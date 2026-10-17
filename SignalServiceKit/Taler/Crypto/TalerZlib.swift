//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Compression
import Foundation

/// zlib (RFC 1950), nicht gzip - wallet-core komprimiert Contract-Terms mit
/// `fflate.zlibSync`. Apples `COMPRESSION_ZLIB` ist rohes DEFLATE (RFC 1951),
/// deshalb wird der 2-Byte-zlib-Header hier selbst geprueft und abgeschnitten.
enum TalerZlib {

    /// Entpackt genau `expectedLength` Bytes. Die Laenge stammt aus dem
    /// Chiffrat der Gegenseite und begrenzt bewusst den Speicherbedarf
    /// (gleiches Verhalten wie `Inflater` auf Android). `nil`, wenn Header
    /// oder Laenge nicht passen.
    static func inflate(_ compressed: Data, expectedLength: Int) -> Data? {
        guard compressed.count > 2, expectedLength > 0 else {
            return nil
        }
        let cmf = compressed[compressed.startIndex]
        let flg = compressed[compressed.startIndex + 1]
        // CM = 8 (deflate), kein preset dictionary, Header-Pruefsumme.
        guard cmf & 0x0f == 8, flg & 0x20 == 0, (UInt16(cmf) << 8 | UInt16(flg)) % 31 == 0 else {
            return nil
        }
        let deflate = compressed.dropFirst(2)
        var output = [UInt8](repeating: 0, count: expectedLength)
        let written = deflate.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
            guard let base = source.bindMemory(to: UInt8.self).baseAddress else {
                return 0
            }
            return compression_decode_buffer(&output, expectedLength, base, source.count, nil, COMPRESSION_ZLIB)
        }
        guard written == expectedLength else {
            return nil
        }
        return Data(output)
    }

    /// Gegenrichtung - nur fuer Tests.
    static func deflate(_ data: Data) -> Data? {
        let capacity = data.count + 1024
        var output = [UInt8](repeating: 0, count: capacity)
        let written = data.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
            guard let base = source.bindMemory(to: UInt8.self).baseAddress else {
                return 0
            }
            return compression_encode_buffer(&output, capacity, base, source.count, nil, COMPRESSION_ZLIB)
        }
        guard written > 0 else {
            return nil
        }
        var result = Data([0x78, 0x9c])
        result.append(contentsOf: output[0..<written])
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        let adler = (b << 16) | a
        result.append(contentsOf: [UInt8(adler >> 24), UInt8((adler >> 16) & 0xff), UInt8((adler >> 8) & 0xff), UInt8(adler & 0xff)])
        return result
    }
}
