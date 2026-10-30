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
    var scale: CGFloat = 1
}

struct TouchPad: View {
    let layout: PadLayout
    let landscape: Bool
    let onChange: (UInt16) -> Void
    var onStick: (CGFloat, CGFloat) -> Void = { _, _ in }   // -1...1, down is +
    var onStick2: (CGFloat, CGFloat) -> Void = { _, _ in }  // the right stick (remote play)

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
                leftSide(size: size)
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
        case .xbox:
            return [Shoulder(label: "LT", bit: Bit.l2, left: true), Shoulder(label: "LB", bit: Bit.l, left: true),
                    Shoulder(label: "RT", bit: Bit.r2, left: false), Shoulder(label: "RB", bit: Bit.r, left: false)]
        case .gba, .snes, .virtualBoy, .psp, .ds:
            return [Shoulder(label: "L", bit: Bit.l, left: true), Shoulder(label: "R", bit: Bit.r, left: false)]
        case .n64:   // Mupen64Plus-Next: Z = L2, L = Select, R = R2
            return [Shoulder(label: "Z", bit: Bit.l2, left: true), Shoulder(label: "L", bit: Bit.select, left: true),
                    Shoulder(label: "R", bit: Bit.r2, left: false)]
        case .saturn:
            return [Shoulder(label: "L", bit: Bit.l2, left: true), Shoulder(label: "R", bit: Bit.r2, left: false)]
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
        case .n64:       // A = B, B = Y; C buttons: up = X, down = A, left = L, right = R
            return [FaceButton(label: "A", bit: Bit.b, offset: CGSize(width: -0.35, height: 0.75)),
                    FaceButton(label: "B", bit: Bit.y, offset: CGSize(width: -1.25, height: 0.15)),
                    FaceButton(label: "▲", bit: Bit.x, offset: CGSize(width: 0.85, height: -1.45), scale: 0.62),
                    FaceButton(label: "▼", bit: Bit.a, offset: CGSize(width: 0.85, height: -0.35), scale: 0.62),
                    FaceButton(label: "◀", bit: Bit.l, offset: CGSize(width: 0.3, height: -0.9), scale: 0.62),
                    FaceButton(label: "▶", bit: Bit.r, offset: CGSize(width: 1.4, height: -0.9), scale: 0.62)]
        case .xbox:      // the Xbox's own places: Y top, B right, A bottom, X left
            return [FaceButton(label: "Y", bit: Bit.x, offset: CGSize(width: 0, height: -1)),
                    FaceButton(label: "B", bit: Bit.a, offset: CGSize(width: 1, height: 0)),
                    FaceButton(label: "A", bit: Bit.b, offset: CGSize(width: 0, height: 1)),
                    FaceButton(label: "X", bit: Bit.y, offset: CGSize(width: -1, height: 0))]
        case .snes, .ds:
            return [FaceButton(label: "X", bit: Bit.x, offset: CGSize(width: 0, height: -1)),
                    FaceButton(label: "A", bit: Bit.a, offset: CGSize(width: 1, height: 0)),
                    FaceButton(label: "B", bit: Bit.b, offset: CGSize(width: 0, height: 1)),
                    FaceButton(label: "Y", bit: Bit.y, offset: CGSize(width: -1, height: 0))]
        case .playstation, .psp:
            return [FaceButton(label: "△", bit: Bit.x, offset: CGSize(width: 0, height: -1)),
                    FaceButton(label: "○", bit: Bit.a, offset: CGSize(width: 1, height: 0)),
                    FaceButton(label: "✕", bit: Bit.b, offset: CGSize(width: 0, height: 1)),
                    FaceButton(label: "□", bit: Bit.y, offset: CGSize(width: -1, height: 0))]
        case .genesis:   // Genesis Plus GX: A = libretro Y, B = B, C = A
            return [FaceButton(label: "A", bit: Bit.y, offset: CGSize(width: -1.1, height: 0.45)),
                    FaceButton(label: "B", bit: Bit.b, offset: CGSize(width: 0, height: 0)),
                    FaceButton(label: "C", bit: Bit.a, offset: CGSize(width: 1.1, height: -0.45))]
        case .saturn:    // Yabause / Beetle Saturn: A = B, B = A, C = R, X = Y, Y = X, Z = L
            return [FaceButton(label: "X", bit: Bit.y, offset: CGSize(width: -1.1, height: -0.55)),
                    FaceButton(label: "Y", bit: Bit.x, offset: CGSize(width: 0, height: -0.85)),
                    FaceButton(label: "Z", bit: Bit.l, offset: CGSize(width: 1.1, height: -1.15)),
                    FaceButton(label: "A", bit: Bit.b, offset: CGSize(width: -1.1, height: 0.65)),
                    FaceButton(label: "B", bit: Bit.a, offset: CGSize(width: 0, height: 0.35)),
                    FaceButton(label: "C", bit: Bit.r, offset: CGSize(width: 1.1, height: 0.05))]
        case .arcade:    // FinalBurn Neo: punches on top (Y X L), kicks below (B A R)
            return [FaceButton(label: "1", bit: Bit.y, offset: CGSize(width: -1.1, height: -0.55)),
                    FaceButton(label: "2", bit: Bit.x, offset: CGSize(width: 0, height: -0.85)),
                    FaceButton(label: "3", bit: Bit.l, offset: CGSize(width: 1.1, height: -1.15)),
                    FaceButton(label: "4", bit: Bit.b, offset: CGSize(width: -1.1, height: 0.65)),
                    FaceButton(label: "5", bit: Bit.a, offset: CGSize(width: 0, height: 0.35)),
                    FaceButton(label: "6", bit: Bit.r, offset: CGSize(width: 1.1, height: 0.05))]
        case .atari:
            return [FaceButton(label: "FIRE", bit: Bit.b, offset: .zero)]
        }
    }

    @ViewBuilder
    private func face(size: CGFloat) -> some View {
        if layout == .xbox {
            VStack(spacing: 10) {
                AnalogStick(size: size * 1.7, onChange: onStick2)
                faceButtons(size: size)
            }
        } else {
            faceButtons(size: size)
        }
    }

    private func faceButtons(size: CGFloat) -> some View {
        let box = size * 3.2
        return ZStack {
            ForEach(faces, id: \.label) { f in
                PadButton(label: f.label, size: size * f.scale, round: true) {
                    press("face-" + f.label, $0 ? f.bit : nil)
                }
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
            if layout != .saturn && layout != .n64 {
                PadButton(label: layout == .arcade ? "COIN" : layout == .xbox ? "VIEW" : "SELECT", size: 30,
                          round: false, wide: true) {
                    press("select", $0 ? Bit.select : nil)
                }
            }
            PadButton(label: layout == .xbox ? "MENU" : "START", size: 30, round: false, wide: true) {
                press("start", $0 ? Bit.start : nil)
            }
        }
    }

    @ViewBuilder
    private func leftSide(size: CGFloat) -> some View {
        switch layout {
        case .n64:
            AnalogStick(size: size * 2.4, onChange: onStick)
        case .psp, .xbox:
            VStack(spacing: 10) {
                AnalogStick(size: size * 1.7, onChange: onStick)
                dpad(size: size * 2.0)
            }
        default:
            dpad(size: size * 2.4)
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

// A thumbstick: the knob follows the finger inside the ring; the middle is still.
private struct AnalogStick: View {
    let size: CGFloat
    let onChange: (CGFloat, CGFloat) -> Void
    @State private var knob: CGSize = .zero

    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.06))
            Circle().stroke(Theme.blue.opacity(0.3), lineWidth: 1.5)
            Circle()
                .fill(Color.white.opacity(knob == .zero ? 0.18 : 0.32))
                .overlay(Circle().stroke(Theme.blue.opacity(0.7), lineWidth: 1.5))
                .frame(width: size * 0.42, height: size * 0.42)
                .offset(knob)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in
                let r = size * 0.38
                var dx = v.location.x - size / 2, dy = v.location.y - size / 2
                let d = hypot(dx, dy)
                if d > r { dx *= r / d; dy *= r / d }
                knob = CGSize(width: dx, height: dy)
                onChange(dx / r, dy / r)
            }
            .onEnded { _ in
                knob = .zero
                onChange(0, 0)
            })
    }
}
