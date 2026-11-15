// Copyright (c) 2026 Skitzelles - part of Game Vault, https://github.com/skitzellez/xbox-game-vault
// PolyForm Noncommercial License 1.0.0: not for sale, and this notice stays in every copy.
// Game Vault for iPhone - Settings > Edit touch controls (like Android's Controls.kt): pick a system, then its buttons
// are shown on the screen as in a game. Drag one to move it, pinch it (or use the size bar) to make it bigger or
// smaller, Remove takes it away, Add brings back any one, Reset goes back to the start. The phone held sideways and
// upright each keep their own layout: turn the phone to edit the other one.
import SwiftUI

struct ControlsEditorList: View {
    @ObservedObject private var store = PadStore.shared
    @State private var editing: Entry?

    struct Entry: Identifiable {
        let id: String       // the system code (the layout's name in PadStore)
        let name: String
        let layout: PadLayout
    }

    private var entries: [Entry] {
        Systems.all.map { Entry(id: $0.code, name: $0.name, layout: $0.pad) } +
            [Entry(id: "\(PadLayout.xbox)", name: "Xbox (FROM XBOX, remote play)", layout: .xbox)]
    }

    var body: some View {
        List(entries) { e in
            Button { editing = e } label: {
                HStack {
                    Text(e.name).foregroundStyle(.primary)
                    Spacer()
                    if store.edited(e.id) { Text("Changed").font(.footnote).foregroundStyle(.secondary) }
                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                }
            }
        }
        .navigationTitle("Touch controls")
        .fullScreenCover(item: $editing) { e in ControlsEditor(entry: e) }
    }
}

struct ControlsEditor: View {
    let entry: ControlsEditorList.Entry
    @ObservedObject private var store = PadStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String?

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            let pad = TouchPad(layout: entry.layout, landscape: landscape, onChange: { _ in }, system: entry.id,
                               editing: true, selected: $selected)
            ZStack {
                Color.black.ignoresSafeArea()
                // where the game's picture goes
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.panel)
                        .overlay(Text("Game picture").font(Theme.body(14)).foregroundStyle(Theme.dim))
                        .aspectRatio(4 / 3, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: landscape ? .infinity : geo.size.height * 0.48)
                    if !landscape { Spacer(minLength: 0) }
                }
                pad
                VStack(spacing: 8) {
                    toolbar(pad: pad, landscape: landscape)
                    Spacer()
                }
            }
        }
        .statusBarHidden()
    }

    private func toolbar(pad: TouchPad, landscape: Bool) -> some View {
        let hidden = pad.controls.filter { store.item(entry.id, landscape, $0.key).hidden }
        let name = pad.controls.first { $0.key == selected }?.name
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(entry.name + (landscape ? " · Sideways" : " · Upright"))
                    .font(Theme.body(14)).foregroundStyle(Theme.ink).lineLimit(1)
                Spacer()
                Menu {
                    ForEach(hidden, id: \.key) { c in
                        Button(c.name) { store.change(entry.id, landscape, c.key) { $0.hidden = false } }
                    }
                } label: { chip("Add", "plus") }
                .disabled(hidden.isEmpty)
                Button { store.reset(entry.id, landscape); selected = nil } label: { chip("Reset", "arrow.counterclockwise") }
                Button { dismiss() } label: { chip("Done", "checkmark", strong: true) }
            }
            if let key = selected, let name {
                HStack(spacing: 12) {
                    Text(name).font(Theme.body(13)).foregroundStyle(Theme.blue)
                    Image(systemName: "minus.magnifyingglass").foregroundStyle(Theme.dim)
                    Slider(value: Binding(
                        get: { Double(store.item(entry.id, landscape, key).scale) },
                        set: { v in store.change(entry.id, landscape, key) { $0.scale = CGFloat(v) } }),
                           in: 0.5...2.2)
                    Image(systemName: "plus.magnifyingglass").foregroundStyle(Theme.dim)
                    Button {
                        store.change(entry.id, landscape, key) { $0.hidden = true }
                        selected = nil
                    } label: { chip("Remove", "trash") }
                }
            } else {
                Text("Drag a button to move it. Tap it, then pinch or use the bar to resize it. Turn the phone to edit the other way round.")
                    .font(Theme.body(12)).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
            }
        }
        .padding(12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private func chip(_ text: String, _ icon: String, strong: Bool = false) -> some View {
        Label(text, systemImage: icon)
            .font(Theme.body(13))
            .foregroundStyle(strong ? .black : Theme.ink)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(strong ? Theme.blue : Color.white.opacity(0.1), in: Capsule())
    }
}
