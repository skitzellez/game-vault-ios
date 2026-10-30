// Copyright (c) 2026 Skitzelles - part of Game Vault, https://github.com/skitzellez/xbox-game-vault
// PolyForm Noncommercial License 1.0.0: not for sale, and this notice stays in every copy.
// Game Vault for iPhone - the touch buttons: a d-pad on the left, the system's own buttons on the right (named and
// placed like on its controller), Start/Select in the middle, shoulder buttons at the top corners. Every finger is its
// own touch, so the d-pad and a button can be held together. A light tap of the phone on each press.
import SwiftUI
import UIKit

private enum Bit {
    static let b = 0, y = 1, select = 2, start = 3, up = 4, down = 5, left = 6, right = 7
    static let a = 8, x = 9, l = 10, r = 11, l2 = 12, r2 = 13
}

private struct FaceButton {
    let label: String
    let bit: Int
    let offset: CGSize   // from the middle of the button cluster, in button sizes
}

struct TouchPad: View {
    let layout: PadLayout
    let landscape: Bool
    let onChange: (UInt16) -> Void

    @State private var held: [String: UInt16] = [:]   // per control: the bits its finger holds

    var body: some View {
        let size: CGFloat = landscape ? 62 : 68
        VStack {
            if !shoulders.isEmpty {
                HStack {
                    VStack(spacing: 8) { ForEach(shoulders.filter { $0.left }, id: \.label) { shoulder($0) } }
                    Spacer()
                    VStack(spacing: 8) { ForEach(shoulders.filter { !$0.left }, id: \.label) { shoulder($0) } }
                }
                .padding(.horizontal, 18)
                .padding(.top, landscape ? 12 : 0)
            }
            Spacer()
            HStack(alignment: .bottom) {
                dpad(size: size * 2.4)
                Spacer()
                if !landscape { startSelect }
                Spacer()
                face(size: size)
            }
            .padding(.horizontal, 18)
            if landscape { startSelect.padding(.bottom, 6) }
        }
        .padding(.bottom, landscape ? 10 : 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    // MARK: pieces

    private struct Shoulder { let label: String; let bit: Int; let left: Bool }

    private var shoulders: [Shoulder] {
        switch layout {
        case .gba, .snes, .virtualBoy:
            return [Shoulder(label: "L", bit: Bit.l, left: true), Shoulder(label: "R", bit: Bit.r, left: false)]
        case .playstation:
            return [Shoulder(label: "L1", bit: Bit.l, left: true), Shoulder(label: "L2", bit: Bit.l2, left: true),
                    Shoulder(label: "R1", bit: Bit.r, left: false), Shoulder(label: "R2", bit: Bit.r2, left: false)]
        default:
            return []
        }
    }

    private var faces: [FaceButton] {
        switch layout {
        case .twoButtons, .gba, .virtualBoy:
            return [FaceButton(label: "B", bit: Bit.b, offset: CGSize(width: -0.6, height: 0.35)),
                    FaceButton(label: "A", bit: Bit.a, offset: CGSize(width: 0.6, height: -0.35))]
        case .snes:
            return [FaceButton(label: "X", bit: Bit.x, offset: CGSize(width: 0, height: -1)),
                    FaceButton(label: "A", bit: Bit.a, offset: CGSize(width: 1, height: 0)),
                    FaceButton(label: "B", bit: Bit.b, offset: CGSize(width: 0, height: 1)),
                    FaceButton(label: "Y", bit: Bit.y, offset: CGSize(width: -1, height: 0))]
        case .playstation:
            return [FaceButton(label: "△", bit: Bit.x, offset: CGSize(width: 0, height: -1)),
                    FaceButton(label: "○", bit: Bit.a, offset: CGSize(width: 1, height: 0)),
                    FaceButton(label: "✕", bit: Bit.b, offset: CGSize(width: 0, height: 1)),
                    FaceButton(label: "□", bit: Bit.y, offset: CGSize(width: -1, height: 0))]
        case .genesis:   // Genesis Plus GX: A = libretro Y, B = B, C = A
            return [FaceButton(label: "A", bit: Bit.y, offset: CGSize(width: -1.1, height: 0.45)),
                    FaceButton(label: "B", bit: Bit.b, offset: CGSize(width: 0, height: 0)),
                    FaceButton(label: "C", bit: Bit.a, offset: CGSize(width: 1.1, height: -0.45))]
        case .atari:
            return [FaceButton(label: "FIRE", bit: Bit.b, offset: .zero)]
        }
    }

    private func face(size: CGFloat) -> some View {
        let box = size * 3.2
        return ZStack {
            ForEach(faces, id: \.label) { f in
                PadButton(label: f.label, size: size, round: true) { press("face-" + f.label, $0 ? f.bit : nil) }
                    .offset(x: f.offset.width * size * 1.05, y: f.offset.height * size * 1.05)
            }
        }
        .frame(width: box, height: box)
    }

    private func shoulder(_ s: Shoulder) -> some View {
        PadButton(label: s.label, size: 50, round: false) { press("sh-" + s.label, $0 ? s.bit : nil) }
    }

    private var startSelect: some View {
        HStack(spacing: 14) {
            PadButton(label: "SELECT", size: 30, round: false, wide: true) { press("select", $0 ? Bit.select : nil) }
            PadButton(label: "START", size: 30, round: false, wide: true) { press("start", $0 ? Bit.start : nil) }
        }
    }

    private func dpad(size: CGFloat) -> some View {
        DPad(size: size) { dirs in
            var bits: UInt16 = 0
            for d in dirs { bits |= 1 << UInt16(d) }
            set("dpad", bits)
        }
    }

    private func press(_ key: String, _ bit: Int?) {
        set(key, bit.map { 1 << UInt16($0) } ?? 0)
    }

    private func set(_ key: String, _ bits: UInt16) {
        let before = held[key] ?? 0
        held[key] = bits
        if bits & ~before != 0 { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6) }
        onChange(held.values.reduce(0, |))
    }
}

private struct PadButton: View {
    let label: String
    let size: CGFloat
    let round: Bool
    var wide = false
    let onPress: (Bool) -> Void
    @State private var down = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: round ? size / 2 : 10, style: .continuous)
        Text(label)
            .font(.system(size: wide ? 11 : (label.count > 2 ? 13 : size * 0.36), weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(down ? 1 : 0.75))
            .frame(width: wide ? 76 : (round ? size : 64), height: wide ? size : (round ? size : 40))
            .background(shape.fill(Color.white.opacity(down ? 0.32 : 0.12)))
            .overlay(shape.stroke(Theme.blue.opacity(down ? 0.9 : 0.35), lineWidth: 1.5))
            .contentShape(shape)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !down { down = true; onPress(true) } }
                .onEnded { _ in down = false; onPress(false) })
    }
}

// One touch area for all four directions: the angle from the middle picks one direction or a diagonal.
private struct DPad: View {
    let size: CGFloat
    let onChange: ([Int]) -> Void
    @State private var dirs: [Int] = []

    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.06))
            Circle().stroke(Theme.blue.opacity(0.3), lineWidth: 1.5)
            ForEach(0..<4) { i in
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: size * 0.13))
                    .foregroundStyle(.white.opacity(lit(i) ? 1 : 0.55))
                    .offset(y: -size * 0.33)
                    .rotationEffect(.degrees(Double(i) * 90))
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in
                let dx = v.location.x - size / 2, dy = v.location.y - size / 2
                var now: [Int] = []
                if hypot(dx, dy) > size * 0.12 {
                    let angle = atan2(-dy, dx) * 180 / .pi   // 0 = right, 90 = up
                    if angle > 22.5 && angle < 157.5 { now.append(4) }
                    if angle < -22.5 && angle > -157.5 { now.append(5) }
                    if angle > 112.5 || angle < -112.5 { now.append(6) }
                    if angle < 67.5 && angle > -67.5 { now.append(7) }
                }
                if now != dirs { dirs = now; onChange(now) }
            }
            .onEnded { _ in dirs = []; onChange([]) })
    }

    // arrow i: 0 up, 1 right, 2 down, 3 left
    private func lit(_ i: Int) -> Bool { dirs.contains([4, 7, 5, 6][i]) }
}
