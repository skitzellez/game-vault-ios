// Copyright (c) 2026 Skitzelles - part of Game Vault, https://github.com/skitzellez/xbox-game-vault
// PolyForm Noncommercial License 1.0.0: not for sale, and this notice stays in every copy.
// Game Vault for iPhone - the link with the Xbox's Game Vault (the same as Game Vault for Android's): scanned once from
// the Xbox (Options > Network > Continue on your phone), it gives the Xbox's address, Game Vault's port and a 256-bit
// key. Every request carries the key; only home-network addresses are accepted.
import Foundation
import SwiftUI
import UIKit

struct XboxLink: Codable, Equatable {
    let host: String
    let port: Int
    let key: String
    let name: String
}

struct RemoteGame: Identifiable, Hashable {
    let id: String
    let title: String
    let system: String
    let art: String?
}

@MainActor
final class VaultLink: ObservableObject {
    static let shared = VaultLink()
    @Published private(set) var link: XboxLink?
    @Published private(set) var games: [RemoteGame] = []
    @Published private(set) var console = ""
    @Published private(set) var reachable = false

    private let storeKey = "xboxLink"

    init() {
        if let data = UserDefaults.standard.data(forKey: storeKey) {
            link = try? JSONDecoder().decode(XboxLink.self, from: data)
        }
    }

    // gamevault://link?h=192.168.1.20&p=8672&k=<64 hex>&n=<console name>
    @discardableResult
    func accept(_ url: URL) -> Bool {
        guard url.scheme == "gamevault", url.host == "link",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return false }
        func q(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let h = q("h"), VaultLink.privateIPv4(h),
              let p = q("p").flatMap(Int.init), (1024...65535).contains(p),
              let k = q("k"), k.count == 64, k.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { return false }
        let l = XboxLink(host: h, port: p, key: k, name: String((q("n") ?? "Xbox").prefix(40)))
        link = l
        if let data = try? JSONEncoder().encode(l) { UserDefaults.standard.set(data, forKey: storeKey) }
        Task { await refresh() }
        return true
    }

    func unlink() {
        link = nil
        games = []
        reachable = false
        UserDefaults.standard.removeObject(forKey: storeKey)
    }

    static func privateIPv4(_ h: String) -> Bool {
        let b = h.split(separator: ".").compactMap { Int($0) }
        guard b.count == 4, b.allSatisfy({ (0...255).contains($0) }) else { return false }
        return b[0] == 10 || (b[0] == 172 && (16...31).contains(b[1])) || (b[0] == 192 && b[1] == 168)
    }

    static var phoneName: String { String(UIDevice.current.name.prefix(40)) }

    static func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
    }

    // One request to the Xbox's Game Vault; nil when it cannot be reached.
    func request(_ method: String, _ path: String, timeout: TimeInterval = 4) async -> (code: Int, body: Data)? {
        guard let l = link, let url = URL(string: "http://\(l.host):\(l.port)\(path)") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue(l.key, forHTTPHeaderField: "X-GV-Key")
        req.setValue("close", forHTTPHeaderField: "Connection")
        if method == "POST" { req.httpBody = Data() }
        guard let got = try? await URLSession.shared.data(for: req),
              let http = got.1 as? HTTPURLResponse else { return nil }
        return (http.statusCode, got.0)
    }

    // The Xbox's games that can be played from here (FROM XBOX shelf).
    func refresh() async {
        guard link != nil else { return }
        guard let r = await request("GET", "/v1/remote/games?phone=" + VaultLink.enc(VaultLink.phoneName)),
              r.code == 200,
              let json = try? JSONSerialization.jsonObject(with: r.body) as? [String: Any] else {
            reachable = false
            return
        }
        reachable = true
        console = json["console"] as? String ?? link?.name ?? "Xbox"
        let list = json["games"] as? [[String: Any]] ?? []
        games = list.compactMap { g in
            guard let id = g["id"] as? String, let title = g["title"] as? String else { return nil }
            return RemoteGame(id: id, title: title, system: g["system"] as? String ?? "", art: g["art"] as? String)
        }
    }

    private var artCache: [String: UIImage] = [:]

    func art(_ game: RemoteGame) async -> UIImage? {
        if let img = artCache[game.id] { return img }
        guard let path = game.art, let r = await request("GET", path, timeout: 8), r.code == 200,
              let img = UIImage(data: r.body) else { return nil }
        let small = Art.shrink(img)
        artCache[game.id] = small
        return small
    }
}

// A box on the FROM XBOX shelf: the Xbox's own box art, else the title on the system's colour.
struct RemoteCoverView: View {
    let game: RemoteGame
    @State private var image: UIImage?

    var body: some View {
        let accent = Systems.byCode(game.system)?.accent ?? Color(red: 0.16, green: 0.78, blue: 0.22)
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [accent.opacity(0.55), Theme.panelHi], startPoint: .topLeading,
                               endPoint: .bottomTrailing)
                Text(game.title).font(Theme.body(14)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                    .padding(8)
            }
        }
        .aspectRatio(0.75, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(accent.opacity(0.35), lineWidth: 1))
        .task(id: game.id) { image = await VaultLink.shared.art(game) }
    }
}
