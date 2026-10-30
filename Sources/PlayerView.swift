// Copyright (c) 2026 Skitzelles - part of Game Vault, https://github.com/skitzellez/xbox-game-vault
// PolyForm Noncommercial License 1.0.0: not for sale, and this notice stays in every copy.
// Game Vault for iPhone - the game screen: the picture as big as it fits, the touch buttons for that system (hidden
// while a controller is connected), and Game Vault's menu (the pause button, or both stick buttons on a controller).
import SwiftUI
import UIKit

struct PlayerView: View {
    @StateObject private var emu: Emulator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase

    init(game: Game) {
        _emu = StateObject(wrappedValue: Emulator(game: game))
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                if landscape || emu.hasController {
                    screen.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        screen.frame(maxWidth: .infinity).frame(height: geo.size.height * 0.48)
                        Spacer(minLength: 0)
                    }
                }
                if !emu.hasController && emu.error == nil {
                    TouchPad(layout: emu.game.system.pad, landscape: landscape) { emu.touchMask = $0 }
                }
                VStack {
                    HStack {
                        Spacer()
                        Button { emu.paused = true } label: {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: 44, height: 44)
                                .background(.white.opacity(0.08), in: Circle())
                        }
                        .padding(.trailing, 12)
                    }
                    Spacer()
                }
                if emu.paused { menu }
                if let error = emu.error { problem(error) }
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { emu.start() }
        .onDisappear { emu.stop() }
        .onChange(of: phase) { p in
            if p != .active {
                emu.keepPlace()
                emu.paused = true
            }
        }
    }

    private var screen: some View {
        GameScreen(emu: emu).aspectRatio(emu.aspect, contentMode: .fit)
    }

    private var menu: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(emu.game.title).font(Theme.title(22)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                Text(emu.game.system.name.uppercased()).font(Theme.body(13)).foregroundStyle(emu.game.system.accent)
                MenuButton(title: "Resume", icon: "play.fill", accent: Theme.blue) { emu.paused = false }
                MenuButton(title: "Start over", icon: "arrow.counterclockwise", accent: Theme.dim) { emu.startOver() }
                MenuButton(title: "Save and quit", icon: "xmark", accent: Theme.dim) {
                    emu.stop()
                    dismiss()
                }
                Text("Your place is kept: next time the game carries on from here.")
                    .font(Theme.body(12)).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func problem(_ text: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 34)).foregroundStyle(Theme.warn)
            Text(text).font(Theme.body(16)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            MenuButton(title: "Back", icon: "chevron.left", accent: Theme.blue) { dismiss() }
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct MenuButton: View {
    let title: String
    let icon: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon).frame(width: 22)
                Text(title).font(Theme.body(17))
                Spacer()
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 18)
            .frame(height: 50)
            .background(accent.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(accent.opacity(0.5), lineWidth: 1))
        }
    }
}

// The picture: a plain layer the emulator puts each frame into, scaled without smoothing (sharp pixels).
struct GameScreen: UIViewRepresentable {
    let emu: Emulator

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        view.layer.magnificationFilter = .nearest
        view.layer.contentsGravity = .resize
        emu.layer = view.layer
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        emu.layer = view.layer
    }
}
