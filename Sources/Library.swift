// Copyright (c) 2026 Skitzelles - part of Game Vault, https://github.com/skitzellez/xbox-game-vault
// PolyForm Noncommercial License 1.0.0: not for sale, and this notice stays in every copy.
// Game Vault for iPhone - finding the games. Two places: Game Vault's own folder (Files > On My iPhone > Game Vault >
// Games, also where a Mac or PC copies games through Finder / iTunes), and any folders the player picks once in the
// Files app (iCloud Drive, a USB drive, a network share); those are kept as bookmarks so they stay readable.
import Foundation
import SwiftUI

struct Game: Identifiable, Hashable {
    let url: URL
    let title: String
    let system: GameSystem
    var zipEntry: String? = nil   // the game file inside a .zip

    var id: String { url.path }
    var fileStem: String { url.deletingPathExtension().lastPathComponent }
}

@MainActor
final class Library: ObservableObject {
    @Published private(set) var games: [Game] = []
    @Published private(set) var scanning = false
    @Published private(set) var folders: [URL] = []
    @Published private(set) var recent: [String] = []   // game ids, newest first

    static let shared = Library()

    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    var gamesFolder: URL { documents.appendingPathComponent("Games", isDirectory: true) }
    var biosFolder: URL { documents.appendingPathComponent("BIOS", isDirectory: true) }
    var savesFolder: URL { documents.appendingPathComponent("Saves", isDirectory: true) }
    var statesFolder: URL { documents.appendingPathComponent("Resume", isDirectory: true) }

    private let bookmarksKey = "folders"
    private let recentKey = "recent"

    init() {
        for dir in [gamesFolder, biosFolder, savesFolder, statesFolder] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        recent = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
        folders = loadBookmarks()
    }

    var bySystem: [(GameSystem, [Game])] {
        Systems.all.compactMap { s in
            let list = games.filter { $0.system.code == s.code }
            return list.isEmpty ? nil : (s, list)
        }
    }

    var recentGames: [Game] {
        recent.compactMap { id in games.first { $0.id == id } }
    }

    func played(_ game: Game) {
        recent.removeAll { $0 == game.id }
        recent.insert(game.id, at: 0)
        if recent.count > 12 { recent.removeLast(recent.count - 12) }
        UserDefaults.standard.set(recent, forKey: recentKey)
    }

    // MARK: folders the player picked

    func addFolder(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        guard let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return }
        var list = UserDefaults.standard.array(forKey: bookmarksKey) as? [Data] ?? []
        list.append(data)
        UserDefaults.standard.set(list, forKey: bookmarksKey)
        if !folders.contains(url) { folders.append(url) }
        Task { await scan() }
    }

    func removeFolder(_ url: URL) {
        guard let i = folders.firstIndex(of: url) else { return }
        url.stopAccessingSecurityScopedResource()
        folders.remove(at: i)
        var list = UserDefaults.standard.array(forKey: bookmarksKey) as? [Data] ?? []
        if i < list.count { list.remove(at: i) }
        UserDefaults.standard.set(list, forKey: bookmarksKey)
        Task { await scan() }
    }

    private func loadBookmarks() -> [URL] {
        let list = UserDefaults.standard.array(forKey: bookmarksKey) as? [Data] ?? []
        var urls: [URL] = []
        var fresh: [Data] = []
        for data in list {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil,
                                     bookmarkDataIsStale: &stale) else { continue }
            _ = url.startAccessingSecurityScopedResource()   // held for the app's life
            urls.append(url)
            fresh.append(stale ? (try? url.bookmarkData()) ?? data : data)
        }
        UserDefaults.standard.set(fresh, forKey: bookmarksKey)
        return urls
    }

    // MARK: the search

    func scan() async {
        scanning = true
        let roots = [gamesFolder] + folders
        let found = await Task.detached(priority: .userInitiated) { Library.find(in: roots) }.value
        games = found
        scanning = false
    }

    nonisolated static func find(in roots: [URL]) -> [Game] {
        var out: [Game] = []
        var seen = Set<String>()
        let fm = FileManager.default
        for root in roots {
            guard let walk = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                           options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            var files: [URL] = []
            for case let url as URL in walk {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { continue }
                files.append(url)
            }
            // a disc's index (.cue / .m3u) stands for its tracks; an .m3u stands for the discs it lists
            let listed = Set(files.filter { ["cue", "m3u"].contains($0.pathExtension.lowercased()) }
                .flatMap { referencedFiles($0) })
            for url in files where !seen.contains(url.path) && !listed.contains(url.standardizedFileURL.path) {
                let ext = url.pathExtension.lowercased()
                let folders = url.deletingLastPathComponent().path.dropFirst(root.path.count)
                    .split(separator: "/").map(String.init)
                var game: Game?
                if ext == "zip" {
                    game = zipGame(url, folders)
                } else if let s = Systems.byExtension(ext) {
                    game = Game(url: url, title: cleanTitle(url.deletingPathExtension().lastPathComponent), system: s)
                } else if ext == "bin", let s = Systems.byFolders(folders), s.code != "PS1" {
                    game = Game(url: url, title: cleanTitle(url.deletingPathExtension().lastPathComponent), system: s)
                }
                if let g = game {
                    seen.insert(url.path)
                    out.append(g)
                }
            }
        }
        return out.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    nonisolated static func zipGame(_ url: URL, _ folders: [String]) -> Game? {
        let entries = Zip.entries(url).filter { !$0.name.hasSuffix("/") }
        let hint = Systems.byFolders(folders)
        for e in entries {
            let ext = (e.name as NSString).pathExtension.lowercased()
            if let s = Systems.byExtension(ext), s.code != "PS1" {
                return Game(url: url, title: cleanTitle(url.deletingPathExtension().lastPathComponent), system: s,
                            zipEntry: e.name)
            }
            if ext == "bin", let s = hint, s.code != "PS1" {
                return Game(url: url, title: cleanTitle(url.deletingPathExtension().lastPathComponent), system: s,
                            zipEntry: e.name)
            }
        }
        return nil
    }

    // The files a .cue or .m3u names, as full paths.
    nonisolated static func referencedFiles(_ list: URL) -> [String] {
        guard let text = (try? String(contentsOf: list, encoding: .utf8))
                ?? (try? String(contentsOf: list, encoding: .isoLatin1)) else { return [] }
        let dir = list.deletingLastPathComponent()
        var out: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            var name: String?
            if list.pathExtension.lowercased() == "cue" {
                guard line.uppercased().hasPrefix("FILE") else { continue }
                if let a = line.firstIndex(of: "\""), let b = line.lastIndex(of: "\""), a < b {
                    name = String(line[line.index(after: a)..<b])
                }
            } else if !line.isEmpty && !line.hasPrefix("#") {
                name = line
            }
            if let n = name { out.append(dir.appendingPathComponent(n).standardizedFileURL.path) }
        }
        return out
    }

    // "Super Mario World (USA) [!]" -> "Super Mario World"
    nonisolated static func cleanTitle(_ stem: String) -> String {
        var s = stem.replacingOccurrences(of: "_", with: " ")
        s = s.replacingOccurrences(of: "\\s*[\\(\\[][^\\)\\]]*[\\)\\]]", with: "", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? stem : s
    }
}
