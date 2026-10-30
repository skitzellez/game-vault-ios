// Copyright (c) 2026 Skitzelles - part of Game Vault, https://github.com/skitzellez/xbox-game-vault
// PolyForm Noncommercial License 1.0.0: not for sale, and this notice stays in every copy.
// Game Vault for iPhone - box art from thumbnails.libretro.com, the same source as the Xbox and Android Game Vault.
// The file's own name is tried first; else the closest name in the server's list for that system (region kept when
// it can be). Pictures are kept in Caches; a game with no picture is remembered so it is not asked again each start.
import SwiftUI
import UIKit

actor Art {
    static let shared = Art()
    private static let server = "https://thumbnails.libretro.com/"
    private let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("covers", isDirectory: true)
    private var lists: [String: [String]] = [:]   // system -> names on the server (without .png)
    private var memory: [String: UIImage] = [:]
    private var missing = Set<String>()

    func cover(_ game: Game) async -> UIImage? {
        let key = game.system.code + "/" + game.fileStem
        if let img = memory[key] { return img }
        if missing.contains(key) { return nil }
        let dir = cache.appendingPathComponent(game.system.code, isDirectory: true)
        let file = dir.appendingPathComponent(Art.safe(game.fileStem) + ".png")
        let none = dir.appendingPathComponent(Art.safe(game.fileStem) + ".none")
        if let img = UIImage(contentsOfFile: file.path) { return keep(key, img) }
        if FileManager.default.fileExists(atPath: none.path) { missing.insert(key); return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var names = [Art.safe(game.artName ?? game.fileStem)]
        if let match = await bestMatch(game), match != names[0] { names.append(match) }
        for name in names {
            guard let url = URL(string: Art.server + Art.path(game.system.thumbs) + "/Named_Boxarts/" +
                                Art.path(name) + ".png"),
                  let got = try? await URLSession.shared.data(from: url),
                  (got.1 as? HTTPURLResponse)?.statusCode == 200,
                  let img = UIImage(data: got.0) else { continue }
            let small = Art.shrink(img)
            if let png = small.pngData() { try? png.write(to: file) }
            return keep(key, small)
        }
        if await online() { FileManager.default.createFile(atPath: none.path, contents: nil) }
        missing.insert(key)
        return nil
    }

    private func keep(_ key: String, _ img: UIImage) -> UIImage {
        memory[key] = img
        return img
    }

    private func online() async -> Bool {
        guard let url = URL(string: Art.server) else { return false }
        return (try? await URLSession.shared.data(from: url)) != nil
    }

    private func bestMatch(_ game: Game) async -> String? {
        let list = await names(game.system)
        if list.isEmpty { return nil }
        let want = Art.key(game.title)
        let region = Art.region(game.fileStem)
        let same = list.filter { Art.key(Library.cleanTitle($0)) == want }
        if let r = region, let hit = same.first(where: { Art.region($0) == r }) { return hit }
        return same.first
    }

    private func names(_ system: GameSystem) async -> [String] {
        if let l = lists[system.code] { return l }
        let file = cache.appendingPathComponent(system.code + ".list")
        var text = try? String(contentsOf: file, encoding: .utf8)
        if text == nil, let url = URL(string: Art.server + Art.path(system.thumbs) + "/Named_Boxarts/"),
           let got = try? await URLSession.shared.data(from: url) {
            let html = String(decoding: got.0, as: UTF8.self)
            var out: [String] = []
            var rest = html[...]
            while let a = rest.range(of: "href=\"") {
                rest = rest[a.upperBound...]
                guard let b = rest.firstIndex(of: "\"") else { break }
                let href = String(rest[..<b])
                if href.hasSuffix(".png"), let name = href.dropLast(4).removingPercentEncoding {
                    out.append(name)
                }
                rest = rest[b...]
            }
            text = out.joined(separator: "\n")
            try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            if !out.isEmpty { try? text?.write(to: file, atomically: true, encoding: .utf8) }
        }
        let l = (text ?? "").split(separator: "\n").map(String.init)
        lists[system.code] = l
        return l
    }

    // the characters the server's names use "_" for
    static func safe(_ s: String) -> String {
        String(s.map { "&*/:`<>?\\|\"".contains($0) ? "_" : $0 })
    }

    static func path(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "&?#+"))) ?? s
    }

    static func key(_ title: String) -> String {
        title.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func region(_ name: String) -> String? {
        for r in ["USA", "Europe", "Japan", "World"] where name.contains(r) { return r }
        return nil
    }

    static func shrink(_ img: UIImage) -> UIImage {
        let maxSide: CGFloat = 480
        let scale = min(1, maxSide / max(img.size.width, img.size.height))
        if scale >= 1 { return img }
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

// A game's box, or its name on the system's colour while there is no picture.
struct CoverView: View {
    let game: Game
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [game.system.accent.opacity(0.55), Theme.panelHi],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(game.title)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .padding(8)
            }
        }
        .aspectRatio(0.75, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(game.system.accent.opacity(0.35), lineWidth: 1))
        .task(id: game.id) { image = await Art.shared.cover(game) }
    }
}
