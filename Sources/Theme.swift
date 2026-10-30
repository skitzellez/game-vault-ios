// Copyright (c) 2026 Skitzelles - part of Game Vault, https://github.com/skitzellez/xbox-game-vault
// PolyForm Noncommercial License 1.0.0: not for sale, and this notice stays in every copy.
// Game Vault for iPhone - colours and type, the same as the Xbox and Android Game Vault.
import SwiftUI

enum Theme {
    static let bg = Color(red: 0x07 / 255, green: 0x0D / 255, blue: 0x18 / 255)
    static let panel = Color(red: 0x11 / 255, green: 0x1D / 255, blue: 0x31 / 255).opacity(0.8)
    static let panelHi = Color(red: 0x17 / 255, green: 0x29 / 255, blue: 0x4A / 255)
    static let blue = Color(red: 0x40 / 255, green: 0xBF / 255, blue: 0xFF / 255)
    static let ink = Color(red: 0xF2 / 255, green: 0xF6 / 255, blue: 0xFB / 255)
    static let dim = Color(red: 0xA9 / 255, green: 0xBA / 255, blue: 0xCD / 255)
    static let warn = Color(red: 1.0, green: 0xC2 / 255, blue: 0x66 / 255)

    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    static func body(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
}

// The dark floor with a soft blue glow at the top, behind every screen.
struct VaultBackground: View {
    var body: some View {
        ZStack {
            Theme.bg
            RadialGradient(colors: [Theme.blue.opacity(0.22), .clear], center: .top, startRadius: 0, endRadius: 520)
            LinearGradient(colors: [.clear, Color.black.opacity(0.5)], startPoint: .center, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}
