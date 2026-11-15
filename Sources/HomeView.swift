// Copyright (c) 2026 Skitzelles - part of Game Vault, https://github.com/skitzellez/xbox-game-vault
// PolyForm Noncommercial License 1.0.0: not for sale, and this notice stays in every copy.
// Game Vault for iPhone - the home screen, like the Xbox and Android Game Vault: CONTINUE with the last game, recently
// played, then a shelf of box art per system. Tap a box for its page (Play, Start over). No games yet: one button to
// pick the folder they are in. Linked with an Xbox: CONTINUE FROM YOUR XBOX brings the save of what the Xbox played
// last, and after a game here its save goes to the Xbox (Continue.swift).
import SwiftUI
import UniformTypeIdentifiers

@main
struct GameVaultApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(.dark)
                .onOpenURL { url in VaultLink.shared.accept(url) }
        }
    }
}

struct HomeView: View {
    @ObservedObject private var library = Library.shared
    @ObservedObject private var xbox = VaultLink.shared
    @ObservedObject private var appUpdate = AppUpdate.shared
    @Environment(\.scenePhase) private var phase
    @State private var playing: Game?
    @State private var lastPlaying: Game?
    @State private var details: Game?
    @State private var remote: RemoteGame?
    @State private var picking = false
    @State private var showFolders = false
    @State private var searching = false
    @State private var query = ""
    @State private var fromXbox: XboxOffer?
    @State private var bringing = false

    struct XboxOffer {
        let point: XboxPoint
        let game: Game
    }

    var body: some View {
        ZStack {
            VaultBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    if let v = appUpdate.newer { updateBanner(v) }
                    if searching {
                        searchResults
                    } else {
                        if let offer = fromXbox { xboxContinueCard(offer) }
                        if xbox.link != nil { remoteShelf }
                        if library.games.isEmpty {
                            empty
                        } else {
                            if let last = library.recentGames.first { continueCard(last) }
                            if library.recentGames.count > 1 {
                                shelf("RECENTLY PLAYED", Theme.blue, Array(library.recentGames.dropFirst()))
                            }
                            ForEach(library.bySystem, id: \.0.code) { entry in
                                shelf(entry.0.name.uppercased(), entry.0.accent, entry.1)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .refreshable {
                await library.scan()
                await linkCheck()
            }
        }
        .task {
            await library.scan()
            await linkCheck()
        }
        .task { await appUpdate.check() }
        .onChange(of: phase) { p in
            if p == .active && playing == nil { Task { await linkCheck() } }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { library.addFolder(url) }
        }
        .sheet(isPresented: $showFolders) { FoldersView(picking: $picking) }
        .sheet(item: $details) { game in
            GameDetailsView(game: game) {
                details = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { play(game) }
            }
        }
        .fullScreenCover(item: $playing, onDismiss: {
            let g = lastPlaying
            Task {
                await library.scan()
                if let g { await xbox.send(g) }   // its save to the Xbox: "Continue from your phone" there
            }
        }) { game in
            PlayerView(game: game)
        }
        .fullScreenCover(item: $remote) { game in
            RemoteView(game: game)
        }
    }

    private func play(_ g: Game) {
        lastPlaying = g
        playing = g
    }

    // the FROM XBOX shelf, what the Xbox played last, and a save still to send
    private func linkCheck() async {
        guard xbox.link != nil else { fromXbox = nil; return }
        await xbox.refresh()
        guard xbox.reachable else { return }
        await xbox.sendPending()
        if let x = await xbox.last(), let g = await xbox.findHere(x, in: library.games), xbox.worthOffering(x, g) {
            fromXbox = XboxOffer(point: x, game: g)
        } else {
            fromXbox = nil
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
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
            if !library.games.isEmpty {
                RoundIcon(name: "magnifyingglass") { searching = true }
            }
            RoundIcon(name: "gearshape.fill") { showFolders = true }
        }
        .padding(.top, 12)
    }

    private func updateBanner(_ v: String) -> some View {
        Link(destination: AppUpdate.releases) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill").font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Game Vault for iPhone \(v) is out").font(Theme.body(15))
                    Text("Tap to get it, then install it with SideStore or AltStore.").font(Theme.body(12))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
            }
            .foregroundStyle(Theme.ink)
            .padding(14)
            .background(Theme.blue.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.blue.opacity(0.5)))
        }
    }

    // CONTINUE FROM YOUR XBOX: the save of the game the Xbox played last comes here, then the game starts
    private func xboxContinueCard(_ offer: XboxOffer) -> some View {
        let green = Color(red: 0.16, green: 0.78, blue: 0.22)
        let g = offer.game
        return Button {
            guard !bringing else { return }
            bringing = true
            Task {
                let ok = await xbox.bring(offer.point, g)
                bringing = false
                fromXbox = nil
                if ok { play(g) }
            }
        } label: {
            HStack(spacing: 16) {
                CoverView(game: g).frame(width: 84)
                VStack(alignment: .leading, spacing: 6) {
                    Text("CONTINUE FROM YOUR XBOX").font(Theme.body(12)).tracking(1.5).foregroundStyle(green)
                    Text(g.title).font(Theme.title(19)).foregroundStyle(Theme.ink).lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("Played on the Xbox " + offer.point.saved.formatted(.relative(presentation: .named)))
                        .font(Theme.body(12)).foregroundStyle(Theme.dim)
                    HStack(spacing: 6) {
                        if bringing { ProgressView().tint(.black) } else { Image(systemName: "play.fill") }
                        Text(bringing ? "Getting it…" : "Continue")
                    }
                    .font(Theme.body(15)).foregroundStyle(.black)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(green, in: Capsule())
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(green.opacity(0.45)))
        }
        .buttonStyle(.plain)
    }

    private var searchResults: some View {
        let found = query.trimmingCharacters(in: .whitespaces).isEmpty ? [] : library.search(query)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.dim)
                TextField("Search games", text: $query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .foregroundStyle(Theme.ink)
                Button("Done") { searching = false; query = "" }.foregroundStyle(Theme.blue)
            }
            .font(Theme.body(16))
            .padding(12)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if !query.isEmpty && found.isEmpty {
                Text("No game matches \"\(query)\"").font(Theme.body(14)).foregroundStyle(Theme.dim)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], alignment: .leading, spacing: 14) {
                ForEach(found) { game in
                    Button { details = game } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            CoverView(game: game)
                            Text(game.title).font(Theme.body(12)).foregroundStyle(Theme.ink).lineLimit(2)
                            Text(game.system.name).font(Theme.body(11)).foregroundStyle(game.system.accent).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add your games").font(Theme.title(22)).foregroundStyle(Theme.ink)
            Text("Pick the folder your games are in: iCloud Drive, a USB drive or a folder on this iPhone. Game Vault finds every game inside it and sorts them by system.")
                .font(Theme.body(15)).foregroundStyle(Theme.dim)
            MenuButton(title: "Pick my games folder", icon: "folder", accent: Theme.blue) { picking = true }
            Text("Or copy games into Files › On My iPhone › Game Vault › Games.")
                .font(Theme.body(13)).foregroundStyle(Theme.dim)
            Text("Plays " + Systems.all.map(\.name).joined(separator: ", ") + ".")
                .font(Theme.body(12)).foregroundStyle(Theme.dim.opacity(0.8))
        }
        .padding(20)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // FROM XBOX: the linked Xbox's games, played there and shown here (remote play).
    private var remoteShelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("FROM XBOX").font(Theme.body(15)).tracking(1.5)
                    .foregroundStyle(Color(red: 0.16, green: 0.78, blue: 0.22))
                Text(xbox.reachable ? xbox.console : "not reachable").font(Theme.body(13)).foregroundStyle(Theme.dim)
            }
            if !xbox.reachable {
                Text("Open Game Vault on the Xbox and keep this iPhone on the same Wi-Fi, then pull down to refresh.")
                    .font(Theme.body(13)).foregroundStyle(Theme.dim)
            } else if xbox.games.isEmpty {
                Text("No games on the Xbox can be played from here yet.").font(Theme.body(13)).foregroundStyle(Theme.dim)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(xbox.games) { game in
                            Button { remote = game } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    RemoteCoverView(game: game).frame(width: 118)
                                    Text(game.title).font(Theme.body(12)).foregroundStyle(Theme.ink).lineLimit(2)
                                        .frame(width: 118, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func continueCard(_ game: Game) -> some View {
        Button { play(game) } label: {
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

    private func shelf(_ name: String, _ accent: Color, _ games: [Game]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(Theme.body(15)).tracking(1.5).foregroundStyle(accent)
                Text("\(games.count)").font(Theme.body(13)).foregroundStyle(Theme.dim)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(games) { game in
                        Button { details = game } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                CoverView(game: game).frame(width: 118)
                                Text(game.title).font(Theme.body(12)).foregroundStyle(Theme.ink).lineLimit(2)
                                    .frame(width: 118, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { play(game) } label: { Label("Play", systemImage: "play.fill") }
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

private struct RoundIcon: View {
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 46, height: 46)
                .background(Theme.panel, in: Circle())
                .overlay(Circle().stroke(Theme.blue.opacity(0.4), lineWidth: 1))
        }
    }
}

// A game's page, like Android's details: the box, the system, when it was last played, Play (or Carry on) and Start
// over.
struct GameDetailsView: View {
    let game: Game
    let onPlay: () -> Void
    @State private var hasResume = false

    var body: some View {
        ZStack {
            VaultBackground()
            ScrollView {
                VStack(spacing: 18) {
                    CoverView(game: game)
                        .frame(width: 190)
                        .shadow(color: game.system.accent.opacity(0.55), radius: 24)
                        .padding(.top, 30)
                    VStack(spacing: 6) {
                        Text(game.title).font(Theme.title(24)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                        Text(game.system.name.uppercased()).font(Theme.body(13)).tracking(1.5)
                            .foregroundStyle(game.system.accent)
                        Text(lastPlayedText).font(Theme.body(13)).foregroundStyle(Theme.dim)
                    }
                    VStack(spacing: 12) {
                        MenuButton(title: hasResume ? "Carry on" : "Play", icon: "play.fill", accent: Theme.blue, action: onPlay)
                        if hasResume {
                            MenuButton(title: "Start over", icon: "arrow.counterclockwise", accent: Theme.dim) {
                                try? FileManager.default.removeItem(at: Library.shared.statesFolder
                                    .appendingPathComponent(game.system.code + " - " + game.fileStem + ".state"))
                                onPlay()
                            }
                        }
                    }
                    .frame(maxWidth: 420)
                    Text(game.url.lastPathComponent).font(Theme.body(11)).foregroundStyle(Theme.dim.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
            }
        }
        .onAppear { hasResume = Emulator.hasResume(game) }
    }

    private var lastPlayedText: String {
        guard let d = Library.shared.lastPlayed(game) else { return "Not played yet" }
        return "Last played " + d.formatted(.relative(presentation: .named))
    }
}

struct FoldersView: View {
    @ObservedObject private var library = Library.shared
    @ObservedObject private var xbox = VaultLink.shared
    @ObservedObject private var appUpdate = AppUpdate.shared
    @Binding var picking: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var updateText = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("On My iPhone › Game Vault › Games", systemImage: "iphone")
                    ForEach(library.folders, id: \.self) { url in
                        Label(url.lastPathComponent, systemImage: "folder")
                    }
                    .onDelete { rows in rows.map { library.folders[$0] }.forEach(library.removeFolder) }
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { picking = true }
                    } label: { Label("Add a folder", systemImage: "plus") }
                    Button {
                        Task { await library.scan() }
                    } label: {
                        Label(library.scanning ? "Looking for games…" : "Search for games now", systemImage: "arrow.clockwise")
                    }
                } header: {
                    Text("Game folders")
                } footer: {
                    Text("Swipe a folder to stop using it. Your games stay where they are. BIOS files (only some systems need them) go in On My iPhone › Game Vault › BIOS.")
                }
                Section {
                    NavigationLink {
                        ControlsEditorList()
                    } label: { Label("Edit touch controls", systemImage: "hand.tap") }
                } footer: {
                    Text("Move, resize, add or remove the buttons on the screen, for each system.")
                }
                Section {
                    if let l = xbox.link {
                        Label("\(l.name) (\(l.host))", systemImage: "xbox.logo")
                        Button("Unlink this Xbox", role: .destructive) { xbox.unlink() }
                    } else {
                        Text("On the Xbox, open Game Vault › Options › Network › Continue on your phone, and scan the code with this iPhone's camera.")
                    }
                    NavigationLink {
                        XboxUpdateView()
                    } label: { Label("Update my Xbox", systemImage: "arrow.down.circle") }
                } header: {
                    Text("Your Xbox")
                } footer: {
                    Text("Linked, the Xbox's games show on FROM XBOX (the Xbox plays them, this iPhone is the screen and controller), and saves go back and forth: stop a game on one and carry on on the other. Same Wi-Fi only. Update my Xbox installs new Game Vault releases on the Xbox.")
                }
                Section {
                    Button {
                        updateText = "Checking…"
                        Task {
                            let r = await appUpdate.check()
                            if r == nil { updateText = "You have the newest version." }
                            else if r == "" { updateText = "Could not reach GitHub. Check the internet connection." }
                            else { updateText = "Version \(r ?? "") is out." }
                        }
                    } label: { Label("Check for updates", systemImage: "arrow.triangle.2.circlepath") }
                    if !updateText.isEmpty { Text(updateText).font(.footnote) }
                    if appUpdate.newer != nil {
                        Link(destination: AppUpdate.releases) { Label("Get the new version", systemImage: "arrow.down.circle") }
                    }
                    Link(destination: URL(string: "https://discord.gg/RmhhWgguvw")!) {
                        Label("Join the Game Vault Discord", systemImage: "bubble.left.and.bubble.right")
                    }
                    ShareLink(item: GVLog.report()) {
                        Label("Send a problem report", systemImage: "ladybug")
                    }
                } header: {
                    Text("Help")
                } footer: {
                    Text("Game Vault for iPhone \(appUpdate.current) · Copyright © 2026 Skitzelles")
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
