// Copyright (c) 2026 Skitzelles - part of Game Vault, https://github.com/skitzellez/xbox-game-vault
// PolyForm Noncommercial License 1.0.0: not for sale, and this notice stays in every copy.
// Update my Xbox (player ask 2026-11-14: "how do I auto update everything at once?" on an iPhone). The Xbox cannot
// install apps by itself, and an iPhone app cannot run on a timer in the background, so this is one button: it does
// what the PC setup's and Android's automatic updates do, once, while the app is open. Through the console's Device
// Portal it installs new releases of Game Vault's own apps and puts back one an update lost. Never a test release,
// an older version, or an app the player did not have; nothing while a game runs; an app open on the Xbox is skipped.
import CryptoKit
import Foundation
import Security
import SwiftUI
import UIKit

@MainActor
final class XboxUpdate: ObservableObject {
    static let shared = XboxUpdate()

    // Game Vault's own Xbox apps (same list as Android's XboxUpdate.kt): the min_version.txt key with the newest
    // release, its GitHub project, the release's tag start, the file's name start, and the app's package name
    struct XApp {
        let title, key, repo, tag, file, pkg: String
        var game = true
    }
    static let apps: [XApp] = [
        XApp(title: "Game Vault", key: "latest", repo: "xbox-game-vault", tag: "v", file: "GameVault_", pkg: "GamerDad.GameVault", game: false),
        XApp(title: "xemu (Xbox)", key: "latest_xemu", repo: "xemu-uwp", tag: "uwp-", file: "Xemu_", pkg: "GamerDad.Xemu"),
        XApp(title: "Xenia (Xbox 360)", key: "latest_xenia", repo: "Xenia-GameVault", tag: "gv-", file: "XeniaForGameVault_", pkg: "GamerDad.XeniaForGameVault"),
        XApp(title: "RetroArch", key: "latest_retroarch", repo: "RetroArch-GameVault", tag: "gv-", file: "RetroArch-for-GameVault_", pkg: "GamerDad.RetroArchForGameVault"),
        XApp(title: "Dolphin (GameCube, Wii)", key: "latest_dolphin", repo: "Dolphin-GameVault", tag: "gv-", file: "DolphinForGameVault_", pkg: "GamerDad.DolphinForGameVault"),
        XApp(title: "Cemu (Wii U)", key: "latest_cemu", repo: "Cemu-GameVault", tag: "gv-", file: "CemuForGameVault_", pkg: "GamerDad.CemuForGameVault"),
        XApp(title: "Flash", key: "latest_flash", repo: "Flash-GameVault", tag: "gv-", file: "FlashForGameVault_", pkg: "GamerDad.FlashForGameVault"),
        XApp(title: "OpenBOR", key: "latest_openbor", repo: "OpenBOR-GameVault", tag: "gv-", file: "OpenBORForGameVault_", pkg: "GamerDad.OpenBORForGameVault"),
        XApp(title: "Web", key: "latest_web", repo: "Web-GameVault", tag: "gv-", file: "WebForGameVault_", pkg: "GamerDad.WebForGameVault", game: false),
        XApp(title: "Flycast (NAOMI, Atomiswave)", key: "latest_flycast", repo: "Flycast-GameVault", tag: "gv-", file: "FlycastForGameVault_", pkg: "GamerDad.FlycastForGameVault"),
        XApp(title: "PS Vita", key: "latest_vita", repo: "Vita-GameVault", tag: "gv-", file: "VitaForGameVault_", pkg: "GamerDad.VitaForGameVault"),
    ]
    private static let vclibsURL = "https://github.com/skitzellez/xbox-game-vault/releases/download/runtime-vclibs/Microsoft.VCLibs.x64.14.00.appx"
    private static let versionsURL = "https://raw.githubusercontent.com/skitzellez/game-vault-updates/main/min_version.txt"

    @Published private(set) var busy = false
    @Published private(set) var step = ""                    // what it is doing right now
    @Published private(set) var last: String                 // the last result, with its time

    private let defaults = UserDefaults.standard
    private init() { last = UserDefaults.standard.string(forKey: "xu_last") ?? "" }

    // ---- saved settings: the console, its Device Portal user name, the password in the iPhone's keychain (this
    // device only), the console's certificate, and which apps it had
    var address: String { defaults.string(forKey: "xu_address") ?? "" }
    var user: String { defaults.string(forKey: "xu_user") ?? "" }
    var hasPassword: Bool { Keychain.read() != nil }

    func save(address: String, user: String, password: String?) {
        var a = address.trimmingCharacters(in: .whitespaces)
        for p in ["https://", "http://"] where a.lowercased().hasPrefix(p) { a = String(a.dropFirst(p.count)) }
        a = String(a.split(separator: "/").first ?? "")
        a = String(a.split(separator: ":").first ?? "")
        if a != self.address { defaults.removeObject(forKey: "xu_cert") }   // another console: forget the old certificate
        defaults.set(a, forKey: "xu_address")
        defaults.set(user.trimmingCharacters(in: .whitespaces), forKey: "xu_user")
        if let password, !password.isEmpty { Keychain.write(password) }
    }

    private func setLast(_ text: String) {
        let f = DateFormatter()
        f.dateFormat = "MMM d, HH:mm"
        last = f.string(from: Date()) + ": " + text
        defaults.set(last, forKey: "xu_last")
    }

    // "Check the connection": whether the address and sign-in work
    func check() async -> String {
        guard !address.isEmpty else { return "Enter the Xbox address." }
        guard let pass = Keychain.read() else { return "Enter the Device Portal password." }
        let portal = Portal(host: address, user: user, pass: pass)
        do {
            guard let info = try await portal.get("/api/os/info", timeout: 8) else {
                return "Not reached: check the address, and that Device Portal is on in Dev Home."
            }
            return "Connected: \(info["ComputerName"] as? String ?? "Xbox") (\(info["Platform"] as? String ?? ""))"
        } catch {
            return "Not reached: \(error.localizedDescription)"
        }
    }

    // "Update my Xbox now"
    func run() async {
        guard !busy else { return }
        busy = true
        // keep the screen on and ask iOS for a little time if the player leaves: an upload stops when the app sleeps
        UIApplication.shared.isIdleTimerDisabled = true
        var bg = UIBackgroundTaskIdentifier.invalid
        bg = UIApplication.shared.beginBackgroundTask(withName: "Update my Xbox") {
            UIApplication.shared.endBackgroundTask(bg); bg = .invalid
        }
        defer {
            busy = false
            step = ""
            UIApplication.shared.isIdleTimerDisabled = false
            if bg != .invalid { UIApplication.shared.endBackgroundTask(bg) }
        }
        do { setLast(try await update()) } catch { setLast("stopped: \(error.localizedDescription)") }
    }

    private func update() async throws -> String {
        guard !address.isEmpty else { return "enter the Xbox address first" }
        guard let pass = Keychain.read() else { return "sign-in missing: enter the Device Portal password again" }
        let portal = Portal(host: address, user: user, pass: pass)

        step = "Looking for the Xbox…"
        let info: [String: Any]?
        do { info = try await portal.get("/api/os/info", timeout: 8) } catch Portal.Failure.otherConsole {
            return "the Xbox at \(address) is a different console: check the address"
        } catch Portal.Failure.signIn {
            return "the Xbox refused the user name or password"
        } catch { info = nil }
        guard let info else { return "Xbox not reachable (off, or another address)" }
        guard (info["Platform"] as? String ?? "").contains("Series") else {
            return "only Xbox Series X|S apps are updated from the iPhone"
        }

        // what is open on the console: a running game means nothing is sent now
        var running: [String] = []
        if let list = try await portal.get("/api/resourcemanager/processes")?["Processes"] as? [[String: Any]] {
            running = list.compactMap { $0["PackageFullName"] as? String }.filter { !$0.isEmpty }
        }
        func isRunning(_ pkg: String) -> Bool { running.contains { $0.hasPrefix(pkg + "_") } }
        if let g = Self.apps.first(where: { $0.game && isRunning($0.pkg) }) {
            return "a game is running (\(g.title)): close it on the Xbox and try again"
        }

        step = "Reading the Xbox's apps…"
        guard let pkgs = try await portal.get("/api/app/packagemanager/packages")?["InstalledPackages"] as? [[String: Any]] else {
            return "the Xbox did not list its apps"
        }
        var installed: [String: String] = [:]
        for p in pkgs {
            let full = p["PackageFullName"] as? String ?? ""
            if let a = Self.apps.first(where: { full.hasPrefix($0.pkg + "_") }), let v = p["Version"] as? [String: Any] {
                let n = { (k: String) in (v[k] as? NSNumber)?.intValue ?? 0 }
                installed[a.pkg] = "\(n("Major")).\(n("Minor")).\(n("Build")).\(n("Revision"))"
            }
        }
        // apps the player had: remembered, so one an update lost is put back
        let had = Set(defaults.stringArray(forKey: "xu_had") ?? []).union(installed.keys)
        defaults.set(Array(had), forKey: "xu_had")

        step = "Checking for new releases…"
        guard let versions = try? await Net.text(Self.versionsURL) else { return "no internet" }
        func latest(_ k: String) -> String? {
            versions.split(whereSeparator: \.isNewline).first { $0.hasPrefix(k + "=") }
                .map { String($0.dropFirst(k.count + 1)).trimmingCharacters(in: .whitespaces) }
        }

        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("xbox-updates", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }   // these files are big: never keep them
        var done: [String] = [], failed: [String] = [], busyApps: [String] = []
        var vclibs: URL?
        for a in Self.apps where had.contains(a.pkg) {
            guard let want = latest(a.key) else { continue }
            let have = installed[a.pkg]
            if let have, !Self.newer(want, have) { continue }          // current, or a newer test build
            if have != nil && isRunning(a.pkg) { busyApps.append(a.title); continue }   // open on the Xbox
            let name = "\(a.file)\(want)_x64.appx"
            let file = dir.appendingPathComponent(name)
            step = "Downloading \(a.title) \(want)…"
            guard (try? await Net.download("https://github.com/skitzellez/\(a.repo)/releases/download/\(a.tag)\(want)/\(name)", to: file)) != nil else {
                failed.append(a.title); continue
            }
            if vclibs == nil {
                let v = dir.appendingPathComponent("Microsoft.VCLibs.x64.14.00.appx")
                if (try? await Net.download(Self.vclibsURL, to: v)) == nil { failed.append(a.title); continue }
                vclibs = v
            }
            step = "Installing \(a.title) \(want) on the Xbox…"
            var ok = (try? await portal.install(file, dep: vclibs!, scratch: dir)) ?? false
            if ok {
                // Device Portal installs after the upload: wait for its answer (up to 10 minutes)
                for _ in 0..<300 {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard let st = try? await portal.get("/api/app/packagemanager/state") else { continue }
                    ok = st["Success"] as? Bool ?? false
                    break
                }
            }
            try? FileManager.default.removeItem(at: file)
            if ok { done.append("\(a.title) \(want)") } else { failed.append(a.title) }
        }
        var out: String
        if done.isEmpty && failed.isEmpty { out = "everything on the Xbox is up to date" }
        else if failed.isEmpty { out = "updated " + done.joined(separator: ", ") }
        else {
            out = "updated " + (done.isEmpty ? "nothing" : done.joined(separator: ", "))
                + "; could not update " + failed.joined(separator: ", ") + " (try again)"
        }
        if !busyApps.isEmpty { out += "; close " + busyApps.joined(separator: ", ") + " on the Xbox to update it" }
        return out
    }

    nonisolated static func newer(_ a: String, _ b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}

// ---- the console's Device Portal: https on port 11443 with the console's own certificate. The first one seen is
// remembered and only that one is trusted afterwards.
private final class Portal: NSObject, URLSessionDelegate {
    enum Failure: LocalizedError {
        case otherConsole, signIn
        var errorDescription: String? {
            switch self {
            case .otherConsole: return "this is not the Xbox saved before"
            case .signIn: return "the Xbox refused the user name or password"
            }
        }
    }
    let host: String
    private let auth: String
    private var cookies: [String: String] = [:]
    private var certMismatch = false
    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpShouldSetCookies = false
        c.httpCookieAcceptPolicy = .never
        c.timeoutIntervalForResource = 3600
        return URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }()

    init(host: String, user: String, pass: String) {
        self.host = host
        auth = "Basic " + Data("\(user):\(pass)".utf8).base64EncodedString()
    }
    deinit { session.invalidateAndCancel() }

    func urlSession(_ s: URLSession, didReceive ch: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard ch.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              ch.protectionSpace.host == host, let trust = ch.protectionSpace.serverTrust,
              let cert = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else {
            completionHandler(.performDefaultHandling, nil); return
        }
        let fp = SHA256.hash(data: SecCertificateCopyData(cert) as Data).map { String(format: "%02x", $0) }.joined()
        let d = UserDefaults.standard
        if let known = d.string(forKey: "xu_cert"), known != fp {
            certMismatch = true
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        d.set(fp, forKey: "xu_cert")
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    private func request(_ path: String, timeout: TimeInterval) -> URLRequest {
        var r = URLRequest(url: URL(string: "https://\(host):11443\(path)")!, timeoutInterval: timeout)
        r.setValue(auth, forHTTPHeaderField: "Authorization")
        if !cookies.isEmpty { r.setValue(cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie") }
        return r
    }
    private func keepCookies(_ resp: URLResponse) {
        guard let h = resp as? HTTPURLResponse, let url = h.url,
              let fields = h.allHeaderFields as? [String: String] else { return }
        for c in HTTPCookie.cookies(withResponseHeaderFields: fields, for: url) { cookies[c.name] = c.value }
    }
    private func send(_ work: () async throws -> (Data, URLResponse)) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, resp) = try await work()
            keepCookies(resp)
            guard let h = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if h.statusCode == 401 { throw Failure.signIn }
            return (data, h)
        } catch {
            if certMismatch { throw Failure.otherConsole }
            throw error
        }
    }

    func get(_ path: String, timeout: TimeInterval = 15) async throws -> [String: Any]? {
        let r = request(path, timeout: timeout)
        let (data, h) = try await send { try await session.data(for: r) }
        guard h.statusCode == 200 else { return nil }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // the package and the runtime it needs, as Device Portal's install form. The form is written to a file first so
    // a 600 MB app is never held in memory.
    func install(_ file: URL, dep: URL, scratch: URL) async throws -> Bool {
        let boundary = "gv\(UInt64(Date().timeIntervalSince1970 * 1000))"
        let body = scratch.appendingPathComponent("upload.form")
        FileManager.default.createFile(atPath: body.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: body) }
        let out = try FileHandle(forWritingTo: body)
        for (i, (name, f)) in [("f", file), ("dep", dep)].enumerated() {
            if i > 0 { out.write(Data("\r\n".utf8)) }
            out.write(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(f.lastPathComponent)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
            let input = try FileHandle(forReadingFrom: f)
            while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty { out.write(chunk) }
            try input.close()
        }
        out.write(Data("\r\n--\(boundary)--\r\n".utf8))
        try out.close()
        // the file can go now: only the form is sent
        try? FileManager.default.removeItem(at: file)

        let name = file.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? file.lastPathComponent
        var r = request("/api/app/packagemanager/package?package=\(name)", timeout: 300)
        r.httpMethod = "POST"
        r.setValue(cookies["CSRF-Token"] ?? "", forHTTPHeaderField: "X-CSRF-Token")
        r.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let req = r
        let (_, h) = try await send { try await session.upload(for: req, fromFile: body) }
        return (200...299).contains(h.statusCode)
    }
}

// ---- downloads from GitHub
private enum Net {
    static func text(_ url: String) async throws -> String {
        var r = URLRequest(url: URL(string: url)!, timeoutInterval: 20)
        r.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, resp) = try await URLSession.shared.data(for: r)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return String(decoding: data, as: UTF8.self)
    }
    static func download(_ url: String, to dest: URL) async throws {
        let (tmp, resp) = try await URLSession.shared.download(from: URL(string: url)!)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            try? FileManager.default.removeItem(at: tmp); throw URLError(.badServerResponse)
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
    }
}

// ---- the Device Portal password: in the keychain, this iPhone only, never in a backup
private enum Keychain {
    private static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                               kSecAttrService as String: "gv_xbox_portal",
                                               kSecAttrAccount as String: "portal"]
    static func read() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func write(_ text: String) {
        SecItemDelete(query as CFDictionary)
        var q = query
        q[kSecValueData as String] = Data(text.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
}

// ---- the screen: Settings › Update my Xbox
struct XboxUpdateView: View {
    @ObservedObject private var up = XboxUpdate.shared
    @State private var address = ""
    @State private var user = ""
    @State private var password = ""
    @State private var checkText = ""
    @State private var checking = false

    var body: some View {
        Form {
            Section {
                Text("The Xbox can't update Game Vault by itself. Tap Update my Xbox now and this iPhone installs every new release of Game Vault and its emulators on it. Saves and settings stay. Keep this screen open until it's done. BETA.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                TextField("Xbox address (for example 192.168.0.25)", text: $address)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Device Portal user name", text: $user)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField(up.hasPassword ? "Device Portal password (saved; type to change)" : "Device Portal password",
                            text: $password)
                Button {
                    up.save(address: address, user: user, password: password)
                    password = ""
                    checking = true
                    Task { checkText = await up.check(); checking = false }
                } label: { Text(checking ? "Checking…" : "Check the connection") }
                .disabled(checking || up.busy || address.isEmpty)
                if !checkText.isEmpty { Text(checkText).font(.footnote) }
            } header: { Text("Your Xbox") } footer: {
                Text("On the Xbox, open Dev Home: the address is at the top; the user name and password are in Remote Access Settings (the ones you use on the 192 page). Same Wi-Fi as this iPhone.")
            }
            Section {
                Button {
                    up.save(address: address, user: user, password: password)
                    password = ""
                    Task { await up.run() }
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text(up.busy ? "Updating…" : "Update my Xbox now").bold()
                        Spacer()
                        if up.busy { ProgressView() }
                    }
                }
                .disabled(up.busy || address.isEmpty)
                if up.busy && !up.step.isEmpty { Text(up.step).font(.footnote) }
                if !up.last.isEmpty { Text("Last time: " + up.last).font(.footnote).foregroundStyle(.secondary) }
            } footer: {
                Text("Only when no game is running on the Xbox. Use Wi-Fi: some apps are big (RetroArch is about 600 MB).")
            }
        }
        .navigationTitle("Update my Xbox")
        .onAppear {
            address = up.address
            user = up.user
            // the linked Xbox (Continue on your phone) already gives its address
            if address.isEmpty, let l = VaultLink.shared.link { address = l.host }
        }
    }
}
