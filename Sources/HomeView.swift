// Copyright (c) 2026 Skitzelles - part of Game Vault, https://github.com/skitzellez/xbox-game-vault
// PolyForm Noncommercial License 1.0.0: not for sale, and this notice stays in every copy.
// Game Vault for iPhone - the home screen, like the Xbox and Android Game Vault: CONTINUE with the last game, then a
// shelf of box art per system. Tap a box to play. No games yet: one button to pick the folder they are in.
import SwiftUI
import UniformTypeIdentifiers

@main
struct GameVaultApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(.dark)
        }
    }
}

struct HomeView: View {
    @ObservedObject private var library = Library.shared
    @State private var playing: Game?
    @State private var picking = false
    @State private var showFolders = false

    var body: some View {
        ZStack {
            VaultBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    if library.games.isEmpty {
                        empty
                    } else {
                        if let last = library.recentGames.first { continueCard(last) }
                        ForEach(library.bySystem, id: \.0.code) { entry in shelf(entry.0, entry.1) }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .refreshable { await library.scan() }
        }
        .task { await library.scan() }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { library.addFolder(url) }
        }
        .sheet(isPresented: $showFolders) { FoldersView(picking: $picking) }
        .fullScreenCover(item: $playing, onDismiss: { Task { await library.scan() } }) { game in
            PlayerView(game: game)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("GAME VAULT")
                    .font(Theme.title(30))
                    .tracking(3)
                    .foregroundStyle(LinearGradient(colors: [.white, Theme.blue], startPoint: .top,
                                                    endPoint: .bottom))
                    .shadow(color: Theme.blue.opacity(0.5), radius: 10)
                Text(library.scanning ? "Looking for games…" : "\(library.games.count) games")
                    .font(Theme.body(13)).foregroundStyle(Theme.dim)
            }
            Spacer()
            Button { showFolders = true } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 46, height: 46)
                    .background(Theme.panel, in: Circle())
                    .overlay(Circle().stroke(Theme.blue.opacity(0.4), lineWidth: 1))
            }
        }
        .padding(.top, 12)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add your games").font(Theme.title(22)).foregroundStyle(Theme.ink)
            Text("Pick the folder your games are in: iCloud Drive, a USB drive or a folder on this iPhone. Game Vault finds every game inside it and sorts them by system.")
                .font(Theme.body(15)).foregroundStyle(Theme.dim)
            MenuButton(title: "Pick my games folder", icon: "folder", accent: Theme.blue) { picking = true }
            Text("Or copy games into Files › On My iPhone › Game Vault › Games.")
                .font(Theme.body(13)).foregroundStyle(Theme.dim)
            Text("Plays NES, Super Nintendo, Game Boy, Game Boy Color, Game Boy Advance, PlayStation, Genesis, Master System, Game Gear, TurboGrafx-16, Atari 2600, Lynx and Virtual Boy.")
                .font(Theme.body(12)).foregroundStyle(Theme.dim.opacity(0.8))
        }
        .padding(20)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func continueCard(_ game: Game) -> some View {
        Button { playing = game } label: {
            HStack(spacing: 16) {
                CoverView(game: game).frame(width: 96)
                VStack(alignment: .leading, spacing: 6) {
                    Text("CONTINUE").font(Theme.body(12)).tracking(2).foregroundStyle(Theme.blue)
                    Text(game.title).font(Theme.title(20)).foregroundStyle(Theme.ink).lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(game.system.name).font(Theme.body(13)).foregroundStyle(game.system.accent)
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text(Emulator.hasResume(game) ? "Carry on" : "Play")
                    }
                    .font(Theme.body(15))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Theme.blue, in: Capsule())
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(height: 158)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.blue.opacity(0.35)))
        }
        .buttonStyle(.plain)
    }

    private func shelf(_ system: GameSystem, _ games: [Game]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(system.name.uppercased()).font(Theme.body(15)).tracking(1.5).foregroundStyle(system.accent)
                Text("\(games.count)").font(Theme.body(13)).foregroundStyle(Theme.dim)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(games) { game in
                        Button { playing = game } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                CoverView(game: game).frame(width: 118)
                                Text(game.title).font(Theme.body(12)).foregroundStyle(Theme.ink).lineLimit(2)
                                    .frame(width: 118, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { playing = game } label: { Label("Play", systemImage: "play.fill") }
                            if Emulator.hasResume(game) {
                                Button(role: .destructive) {
                                    try? FileManager.default.removeItem(at: Library.shared.statesFolder
                                        .appendingPathComponent(game.system.code + " - " + game.fileStem + ".state"))
                                } label: { Label("Start over next time", systemImage: "arrow.counterclockwise") }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct FoldersView: View {
    @ObservedObject private var library = Library.shared
    @Binding var picking: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("On My iPhone › Game Vault › Games", systemImage: "iphone")
                    ForEach(library.folders, id: \.self) { url in
                        Label(url.lastPathComponent, systemImage: "folder")
                    }
                    .onDelete { rows in rows.map { library.folders[$0] }.forEach(library.removeFolder) }
                } header: {
                    Text("Game folders")
                } footer: {
                    Text("Swipe a folder to stop using it. Your games stay where they are. BIOS files (only some systems need them) go in On My iPhone › Game Vault › BIOS.")
                }
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { picking = true }
                } label: { Label("Add a folder", systemImage: "plus") }
            }
            .navigationTitle("Folders")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
