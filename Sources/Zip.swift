// Copyright (c) 2026 Skitzelles - part of Game Vault, https://github.com/skitzellez/xbox-game-vault
// PolyForm Noncommercial License 1.0.0: not for sale, and this notice stays in every copy.
// Game Vault for iPhone - just enough .zip reading for zipped cartridge games: the names inside (to know the system)
// and unpacking the one game file before it starts. Stored and deflated files; no Zip64 (cartridge zips are small).
import Compression
import Foundation

struct ZipEntry {
    let name: String
    let method: UInt16
    let compressedSize: Int
    let size: Int
    let localHeader: Int
}

enum Zip {
    static func entries(_ url: URL) -> [ZipEntry] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count > 22 else { return [] }
        func u16(_ at: Int) -> Int { Int(data[at]) | Int(data[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        // the end record is in the last 64 KB + 22 bytes
        var end = -1
        var i = data.count - 22
        let stop = max(0, data.count - 22 - 65535)
        while i >= stop {
            if data[i] == 0x50 && data[i + 1] == 0x4B && data[i + 2] == 5 && data[i + 3] == 6 { end = i; break }
            i -= 1
        }
        guard end >= 0 else { return [] }
        let count = u16(end + 10)
        var at = u32(end + 16)
        var out: [ZipEntry] = []
        for _ in 0..<count {
            guard at + 46 <= data.count, u32(at) == 0x02014B50 else { break }
            let nameLen = u16(at + 28), extraLen = u16(at + 30), commentLen = u16(at + 32)
            guard at + 46 + nameLen <= data.count else { break }
            let name = String(decoding: data[(at + 46)..<(at + 46 + nameLen)], as: UTF8.self)
            out.append(ZipEntry(name: name, method: UInt16(u16(at + 10)), compressedSize: u32(at + 20),
                                size: u32(at + 24), localHeader: u32(at + 42)))
            at += 46 + nameLen + extraLen + commentLen
        }
        return out
    }

    // Unpacks one entry to `to`. False when it cannot (damaged, encrypted, or a kind of packing we do not read).
    static func extract(_ url: URL, _ entry: ZipEntry, to: URL) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
        let h = entry.localHeader
        guard h + 30 <= data.count else { return false }
        let nameLen = Int(data[h + 26]) | Int(data[h + 27]) << 8
        let extraLen = Int(data[h + 28]) | Int(data[h + 29]) << 8
        let start = h + 30 + nameLen + extraLen
        guard start + entry.compressedSize <= data.count else { return false }
        let packed = data[start..<(start + entry.compressedSize)]
        var result: Data
        switch entry.method {
        case 0:
            result = Data(packed)
        case 8:
            result = Data(count: entry.size)
            let n = result.withUnsafeMutableBytes { dst in
                packed.withUnsafeBytes { src in
                    compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, entry.size,
                                              src.bindMemory(to: UInt8.self).baseAddress!, entry.compressedSize,
                                              nil, COMPRESSION_ZLIB)
                }
            }
            guard n == entry.size else { return false }
        default:
            return false
        }
        return (try? result.write(to: to, options: .atomic)) != nil
    }
}
