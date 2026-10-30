// Copyright (c) 2026 Skitzelles - part of Game Vault, https://github.com/skitzellez/xbox-game-vault
// PolyForm Noncommercial License 1.0.0: not for sale, and this notice stays in every copy.
// Game Vault for iPhone - the remote play screen: the Xbox's picture, an Xbox controller on the glass (hidden while a
// real controller is connected), and Game Vault's menu (the X button) to go back to the game or quit it.
import AVFoundation
import SwiftUI
import UIKit

struct RemoteView: View {
    @StateObject private var session: RemoteSession
    @Environment(\.dismiss) private var dismiss
    @State private var menu = false

    init(game: RemoteGame) {
        _session = StateObject(wrappedValue: RemoteSession(game: game))
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                if landscape || session.hasController {
                    picture.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        picture.frame(maxWidth: .infinity).aspectRatio(16 / 9, contentMode: .fit)
                        Spacer(minLength: 0)
                    }
                }
                if !session.showing && session.ended == nil {
                    VStack(spacing: 14) {
                        ProgressView().tint(Theme.blue).scaleEffect(1.3)
                        Text(session.status).font(Theme.body(15)).foregroundStyle(Theme.dim)
                        Text(session.game.title).font(Theme.title(20)).foregroundStyle(Theme.ink)
                    }
                    .padding(.bottom, landscape ? 0 : geo.size.height * 0.4)
                }
                if !session.hasController && session.ended == nil {
                    TouchPad(layout: .xbox, landscape: landscape,
                             onChange: { session.setTouch($0) },
                             onStick: { session.touchLeft = CGPoint(x: $0, y: $1) },
                             onStick2: { session.touchRight = CGPoint(x: $0, y: $1) })
                }
                VStack {
                    HStack {
                        Spacer()
                        Button { menu = true } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: 44, height: 44)
                                .background(.white.opacity(0.08), in: Circle())
                        }
                        .padding(.trailing, 12)
                    }
                    Spacer()
                }
                if menu { menuPanel }
                if let why = session.ended { endPanel(why) }
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            session.start()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            session.stop()
        }
    }

    private var picture: some View {
        VideoLayerView(layer: session.layer)
    }

    private var menuPanel: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(session.game.title).font(Theme.title(22)).foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                Text("PLAYING ON YOUR XBOX").font(Theme.body(13)).tracking(1.5)
                    .foregroundStyle(Color(red: 0.16, green: 0.78, blue: 0.22))
                MenuButton(title: "Back to the game", icon: "play.fill", accent: Theme.blue) { menu = false }
                MenuButton(title: "Quit the game", icon: "xmark", accent: Theme.dim) {
                    session.quit()
                    dismiss()
                }
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func endPanel(_ why: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "tv").font(.system(size: 34)).foregroundStyle(Theme.blue)
            Text(why).font(Theme.body(16)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            MenuButton(title: "Back", icon: "chevron.left", accent: Theme.blue) { dismiss() }
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

extension RemoteSession {
    // The touch buttons give libretro bits (TouchPad); the Xbox wants its own (PROTOCOL.md), triggers as 0-255.
    func setTouch(_ retro: UInt16) {
        let map: [(Int, Int)] = [(0, 0), (8, 1), (1, 2), (9, 3), (10, 4), (11, 5), (2, 6), (3, 7), (14, 8), (15, 9),
                                 (4, 10), (5, 11), (6, 12), (7, 13)]
        var x: UInt16 = 0
        for (from, to) in map where retro & (1 << UInt16(from)) != 0 { x |= 1 << UInt16(to) }
        touchButtons = x
        touchLT = retro & (1 << 12) != 0 ? 255 : 0
        touchRT = retro & (1 << 13) != 0 ? 255 : 0
    }
}

// The decoded picture: the session's display layer, sized to the view.
struct VideoLayerView: UIViewRepresentable {
    let layer: AVSampleBufferDisplayLayer

    final class Host: UIView {
        var video: AVSampleBufferDisplayLayer?
        override func layoutSubviews() {
            super.layoutSubviews()
            video?.frame = bounds
        }
    }

    func makeUIView(context: Context) -> Host {
        let v = Host()
        v.backgroundColor = .black
        v.video = layer
        v.layer.addSublayer(layer)
        return v
    }

    func updateUIView(_ view: Host, context: Context) {
        view.setNeedsLayout()
    }
}
