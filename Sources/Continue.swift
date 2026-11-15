// Copyright (c) 2026 Skitzelles - part of Game Vault, https://github.com/skitzellez/xbox-game-vault
// PolyForm Noncommercial License 1.0.0: not for sale, and this notice stays in every copy.
// Game Vault for iPhone - Continue anywhere (the same as Game Vault for Android's VaultLink.kt, against the Xbox's
// GameVault/src/vaultlink.inc): stop a game on the Xbox and carry on here, and the other way round. While Game Vault is
// open on the TV, this asks it what it played last; when this iPhone has the same game, its in-game save comes here.
// After a game here, the save goes to the Xbox, which offers "Continue from your phone".
// Saves only, no save states: the emulators in this app are other builds than the Xbox's, and a save state only
// loads in the very same build (the Xbox would load a state of ours as if it were its own).
import Foundation
import SwiftUI
import UIKit
import zlib

// What the Xbox played last
struct XboxPoint: Equatable {
    let title, file, system, core: String
    let crc: UInt32
    let saved: Date
    let hasSave: Bool
}

extension VaultLink {
    // what the Xbox played last; nil when it cannot be reached or played nothing with a save
    func last() async -> XboxPoint? {
        guard let r = await request("GET", "/v1/last?phone=" + VaultLink.enc(VaultLink.phoneName)), r.code == 200,
              let o = try? JSONSerialization.jsonObject(with: r.body) as? [String: Any],
              let title = o["title"] as? String else { return nil }
        return XboxPoint(title: title, file: o["file"] as? String ?? "", system: o["system"] as? String ?? "",
                         core: o["core"] as? String ?? "", crc: UInt32((o["crc"] as? String).flatMap { UInt32($0, radix: 16) } ?? 0),
                         saved: Date(timeIntervalSince1970: (o["saved"] as? NSNumber)?.doubleValue ?? 0),
                         hasSave: o["save"] as? Bool ?? false)
    }

    // the game here that the Xbox's is: the same file name and system, else the same game data
    func findHere(_ x: XboxPoint, in games: [Game]) async -> Game? {
        let same = games.filter { $0.system.code == x.system }
        if let g = same.first(where: { $0.fileStem.caseInsensitiveCompare(x.file) == .orderedSame }) { return g }
        guard x.crc != 0 else { return nil }
        return await Task.detached(priority: .utility) {
            same.first { GameCRC.of($0) == x.crc }
        }.value
    }

    // the Xbox's save where this app looks for the game's save. Our own save is kept in "Older saves", and our resume
    // point is put aside too (it would load over the Xbox's save).
    func bring(_ x: XboxPoint, _ g: Game) async -> Bool {
        guard x.hasSave, let r = await request("GET", "/v1/save?phone=" + VaultLink.enc(VaultLink.phoneName), timeout: 30),
              r.code == 200, !r.body.isEmpty else { return false }
        let lib = Library.shared
        let save = lib.savesFolder.appendingPathComponent(g.fileStem + ".srm")
        let resume = lib.statesFolder.appendingPathComponent(g.system.code + " - " + g.fileStem + ".state")
        let older = lib.documents.appendingPathComponent("Older saves", isDirectory: true)
        try? FileManager.default.createDirectory(at: older, withIntermediateDirectories: true)
        for f in [save, resume] where FileManager.default.fileExists(atPath: f.path) {
            let kept = older.appendingPathComponent(f.deletingPathExtension().lastPathComponent + " (before Xbox)." + f.pathExtension)
            try? FileManager.default.removeItem(at: kept)
            try? FileManager.default.moveItem(at: f, to: kept)
        }
        do { try r.body.write(to: save, options: .atomic) } catch { return false }
        // remembered, so the same Xbox play is not offered again
        UserDefaults.standard.set(x.saved.timeIntervalSince1970, forKey: "xboxBrought")
        GVLog.line("continue anywhere: \(g.title) from the Xbox (save, \(r.body.count) bytes)")
        return true
    }

    // whether a play on the Xbox is newer than anything this iPhone has for the game
    func worthOffering(_ x: XboxPoint, _ g: Game) -> Bool {
        guard x.hasSave else { return false }
        if UserDefaults.standard.double(forKey: "xboxBrought") >= x.saved.timeIntervalSince1970 { return false }
        let lib = Library.shared
        let ours = [lib.savesFolder.appendingPathComponent(g.fileStem + ".srm"),
                    lib.statesFolder.appendingPathComponent(g.system.code + " - " + g.fileStem + ".state")]
            .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }.max()
        return ours.map { x.saved > $0.addingTimeInterval(5) } ?? true
    }

    // After a game here: our save to the Xbox. Kept for later when the Xbox cannot be reached now.
    @discardableResult
    func send(_ g: Game) async -> Bool {
        guard link != nil else { return false }
        let save = Library.shared.savesFolder.appendingPathComponent(g.fileStem + ".srm")
        guard let data = try? Data(contentsOf: save), !data.isEmpty, data.count <= 64 << 20 else {
            UserDefaults.standard.removeObject(forKey: "linkPending")
            return true   // nothing to send
        }
        UserDefaults.standard.set(g.id, forKey: "linkPending")
        let q = "&phone=" + VaultLink.enc(VaultLink.phoneName)
        guard let r = await request("POST", "/v1/put?kind=save" + q, body: data, timeout: 30), r.code == 200 else { return false }
        let saved = Int((try? save.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? Date().timeIntervalSince1970)
        let crc = await Task.detached(priority: .utility) { GameCRC.of(g) }.value
        guard let d = await request("POST", "/v1/done?crc=" + String(format: "%08X", crc) + "&system=" + VaultLink.enc(g.system.code) +
                                    "&file=" + VaultLink.enc(g.fileStem) + "&saved=\(saved)" + q, timeout: 15) else { return false }
        GVLog.line("continue anywhere: \(g.title) sent to the Xbox (\(d.code))")
        if d.code == 200 || d.code == 404 {   // 404: not a game of the Xbox's library; nothing to try again
            UserDefaults.standard.removeObject(forKey: "linkPending")
            return d.code == 200
        }
        return false
    }

    // a save that could not go to the Xbox before: sent when it can be reached again
    func sendPending() async {
        guard let id = UserDefaults.standard.string(forKey: "linkPending"),
              let g = Library.shared.games.first(where: { $0.id == id }) else { return }
        await send(g)
    }
}

// The game's CRC-32 as the Xbox counts it (GameVault's NetCrc(path, true)): NES / SNES without their header, else the
// whole file. Zipped games: none (both sides find the game by its file name).
enum GameCRC {
    private static var cache: [String: UInt32] = [:]
    private static let lock = NSLock()

    static func of(_ g: Game) -> UInt32 {
        guard g.zipEntry == nil, g.url.pathExtension.lowercased() != "zip" else { return 0 }
        let size = (try? g.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0, size <= 64 << 20 else { return 0 }
        let key = g.url.path + "|\(size)"
        lock.lock(); let known = cache[key]; lock.unlock()
        if let known { return known }
        guard let d = try? Data(contentsOf: g.url, options: .mappedIfSafe) else { return 0 }
        var skip = 0
        if g.system.code == "NES", d.count > 16, d.prefix(4) == Data([0x4E, 0x45, 0x53, 0x1A]) { skip = 16 }
        if g.system.code == "SNES", d.count % 1024 == 512 { skip = 512 }
        let v = d.withUnsafeBytes { raw -> UInt32 in
            guard let base = raw.bindMemory(to: Bytef.self).baseAddress else { return 0 }
            return UInt32(crc32(0, base + skip, uInt(d.count - skip)))
        }
        lock.lock(); cache[key] = v; lock.unlock()
        return v
    }
}

// A short log on the phone (Library/Caches/gamevault.log, the newest 256 KB), sent with a problem report.
enum GVLog {
    static let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("gamevault.log")
    private static let queue = DispatchQueue(label: "gv.log")

    static func line(_ text: String) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let row = f.string(from: Date()) + " " + text + "\n"
        queue.async {
            if let h = try? FileHandle(forWritingTo: file) {
                h.seekToEndOfFile()
                h.write(Data(row.utf8))
                let size = h.offsetInFile
                try? h.close()
                if size > 256 << 10, let all = try? Data(contentsOf: file) {
                    try? all.suffix(128 << 10).write(to: file, options: .atomic)
                }
            } else {
                try? Data(row.utf8).write(to: file)
            }
        }
    }

    // the report: the phone, the app, and the log
    static func report() -> URL {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("Game Vault iPhone report.txt")
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        var text = "Game Vault for iPhone \(v)\n\(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)\n\n"
        text += (try? String(contentsOf: file, encoding: .utf8)) ?? "(no log yet)"
        try? text.write(to: out, atomically: true, encoding: .utf8)
        return out
    }
}

// Is a newer Game Vault for iPhone out? "latest_ios=" in game-vault-updates/min_version.txt, the same file the Xbox
// and Android Game Vault read. A notice only; the player installs it with SideStore / AltStore.
@MainActor
final class AppUpdate: ObservableObject {
    static let shared = AppUpdate()
    static let releases = URL(string: "https://github.com/skitzellez/game-vault-ios/releases/latest")!
    @Published private(set) var newer: String?

    var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    // nil = the newest is installed; "" = could not be checked
    @discardableResult
    func check() async -> String? {
        var r = URLRequest(url: URL(string: "https://raw.githubusercontent.com/skitzellez/game-vault-updates/main/min_version.txt")!,
                           timeoutInterval: 10)
        r.cachePolicy = .reloadIgnoringLocalCacheData
        guard let got = try? await URLSession.shared.data(for: r) else { return "" }
        let text = String(decoding: got.0, as: UTF8.self)
        guard let line = text.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("latest_ios=") }) else { return nil }
        let v = String(line.dropFirst(11)).trimmingCharacters(in: .whitespaces)
        newer = XboxUpdate.newer(v, current) ? v : nil
        return newer
    }
}
