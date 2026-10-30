// Copyright (c) 2026 Skitzelles - part of Game Vault, https://github.com/skitzellez/xbox-game-vault
// PolyForm Noncommercial License 1.0.0: not for sale, and this notice stays in every copy.
// Game Vault for iPhone - one game being played: starts its core (host.c), runs it on the screen's refresh, plays its
// sound, reads a controller or the touch buttons, and keeps the player's place: battery saves in Saves, and the whole
// game state in Resume when they leave, so the next start carries on where they were (Start over clears it).
import AVFoundation
import GameController
import QuartzCore
import UIKit

@MainActor
final class Emulator: ObservableObject {
    let game: Game
    @Published var error: String?
    @Published var paused = false
    @Published var hasController = GCController.controllers().contains { $0.extendedGamepad != nil }
    @Published var aspect: CGFloat = 4.0 / 3.0

    var touchMask: UInt16 = 0
    var touchStick = CGPoint.zero   // -1...1, down is +
    weak var layer: CALayer?

    private var link: CADisplayLink?
    private var engine: AVAudioEngine?
    private var running = false
    private var lastTick: CFTimeInterval = 0
    private var due: Double = 0
    private var shownSerial: UInt32 = 0
    private var observers: [NSObjectProtocol] = []
    private var unpacked: URL?
    private var lastSramSave = Date()

    init(game: Game) {
        self.game = game
    }

    private var library: Library { Library.shared }
    private var sramFile: URL { library.savesFolder.appendingPathComponent(game.fileStem + ".srm") }
    private var resumeFile: URL {
        library.statesFolder.appendingPathComponent(game.system.code + " - " + game.fileStem + ".state")
    }

    static func hasResume(_ game: Game) -> Bool {
        FileManager.default.fileExists(atPath: Library.shared.statesFolder
            .appendingPathComponent(game.system.code + " - " + game.fileStem + ".state").path)
    }

    func start() {
        guard !running else { return }
        guard let frameworks = Bundle.main.privateFrameworksURL else { error = "Game Vault is damaged."; return }
        let sys = game.system
        let have = { (names: [String]) in
            names.contains { FileManager.default.fileExists(atPath: self.library.biosFolder.appendingPathComponent($0).path) }
        }
        if !sys.bios.isEmpty && !have(sys.bios) {
            error = "\(sys.name) games need the system's BIOS file (\(sys.bios.joined(separator: " or "))). " +
                "Put it in Files › On My iPhone › Game Vault › BIOS."
            return
        }
        var coreName = sys.core
        if let better = sys.betterCore, have(better.bios) { coreName = better.core }
        let core = frameworks.appendingPathComponent(coreName + ".framework/" + coreName)
        var path = game.url
        if let entry = game.zipEntry {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("game", isDirectory: true)
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let out = dir.appendingPathComponent((entry as NSString).lastPathComponent)
            guard let e = Zip.entries(game.url).first(where: { $0.name == entry }),
                  Zip.extract(game.url, e, to: out) else {
                error = "This .zip could not be opened. Unzip it and try the game file itself."
                return
            }
            path = out
            unpacked = dir
        }
        var why: UnsafePointer<CChar>?
        let rc = gv_load(core.path, path.path, library.biosFolder.path, library.savesFolder.path, &why)
        if rc != 0 {
            error = why.map { String(cString: $0) } ?? "The game could not start."
            return
        }
        running = true
        gv_load_sram(sramFile.path)
        if FileManager.default.fileExists(atPath: resumeFile.path) { gv_load_state(resumeFile.path) }
        aspect = CGFloat(gv_aspect())
        startSound()
        watchControllers()
        let link = CADisplayLink(target: DisplayTarget(self), selector: #selector(DisplayTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        library.played(game)
    }

    // Leaves the game: battery save + resume state written, everything let go.
    func stop() {
        guard running else { return }
        keepPlace()
        link?.invalidate()
        link = nil
        engine?.stop()
        engine = nil
        gv_unload()
        running = false
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
        if let dir = unpacked { try? FileManager.default.removeItem(at: dir) }
    }

    func keepPlace() {
        guard running else { return }
        gv_save_sram(sramFile.path)
        gv_save_state(resumeFile.path)
    }

    func startOver() {
        try? FileManager.default.removeItem(at: resumeFile)
        gv_reset()
        paused = false
    }

    // MARK: picture

    fileprivate func tick(_ link: CADisplayLink) {
        guard running else { return }
        let now = link.timestamp
        let dt = lastTick == 0 ? 0 : min(now - lastTick, 0.1)
        lastTick = now
        if paused { return }
        gv_set_buttons(0, touchMask | controllerMask())
        setSticks()
        let frameTime = 1.0 / gv_fps()
        due += dt
        // keep the sound queue between about 30 and 120 ms: a frame more or less now and then, never a gap
        let queued = Double(gv_audio_queued()) / gv_sample_rate()
        if queued < 0.03 { due += frameTime * 0.25 }
        if queued > 0.12 { due -= frameTime * 0.25 }
        var frames = 0
        while due >= frameTime && frames < 3 {
            gv_run()
            due -= frameTime
            frames += 1
        }
        if due > frameTime * 3 { due = 0 }
        show()
        if Date().timeIntervalSince(lastSramSave) > 30 {
            gv_save_sram(sramFile.path)
            lastSramSave = Date()
        }
    }

    private func show() {
        var w: UInt32 = 0, h: UInt32 = 0, serial: UInt32 = 0
        guard let pixels = gv_frame(&w, &h, &serial), w > 0, h > 0, serial != shownSerial else { return }
        shownSerial = serial
        let bytes = Int(w) * Int(h) * 4
        guard let provider = CGDataProvider(data: Data(bytes: pixels, count: bytes) as CFData),
              let image = CGImage(width: Int(w), height: Int(h), bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: Int(w) * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue |
                                                           CGBitmapInfo.byteOrder32Little.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = image
        CATransaction.commit()
        let a = CGFloat(gv_aspect())
        if abs(a - aspect) > 0.01 { aspect = a }
    }

    // MARK: sound

    private func startSound() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let rate = gv_sample_rate()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { return }
        let node = Emulator.soundNode(format)
        let engine = AVAudioEngine()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            self.engine = engine
        } catch {
            NSLog("Game Vault: sound did not start: \(error)")
        }
    }

    // Made outside the main actor: the sound thread calls this block, and it must not be tied to the main thread.
    nonisolated static func soundNode(_ format: AVAudioFormat) -> AVAudioSourceNode {
        let scratch = UnsafeMutablePointer<Int16>.allocate(capacity: 16384 * 2)
        return AVAudioSourceNode(format: format) { _, _, frameCount, list -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(list)
            let want = min(Int(frameCount), 16384)
            let got = gv_audio_read(scratch, want)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            for i in 0..<Int(frameCount) {
                if i < got {
                    left[i] = Float(scratch[i * 2]) / 32768
                    right[i] = Float(scratch[i * 2 + 1]) / 32768
                } else {
                    left[i] = 0
                    right[i] = 0
                }
            }
            return noErr
        }
    }

    // MARK: controllers

    private func watchControllers() {
        let nc = NotificationCenter.default
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.hasController = GCController.controllers().contains { $0.extendedGamepad != nil }
                }
            })
        }
    }

    // The sticks: a controller's two, else the touch stick on the left.
    private func setSticks() {
        func axis(_ v: Float) -> Int16 { Int16(max(-32767, min(32767, v * 32767))) }
        var left = (x: Float(touchStick.x), y: Float(touchStick.y))
        var right = (x: Float(0), y: Float(0))
        for c in GCController.controllers() {
            guard let p = c.extendedGamepad else { continue }
            let lx = p.leftThumbstick.xAxis.value, ly = -p.leftThumbstick.yAxis.value
            if abs(lx) > abs(left.x) || abs(ly) > abs(left.y) { left = (lx, ly) }
            right = (p.rightThumbstick.xAxis.value, -p.rightThumbstick.yAxis.value)
        }
        gv_set_analog(0, 0, axis(left.x), axis(left.y))
        gv_set_analog(0, 1, axis(right.x), axis(right.y))
    }

    // A touch on the picture, 0...1 across and down (the DS bottom screen); nil = finger up.
    func touchScreen(_ at: CGPoint?) {
        guard let p = at else {
            gv_set_pointer(0, 0, 0)
            return
        }
        func scale(_ v: CGFloat) -> Int16 { Int16(max(-32767, min(32767, (v * 2 - 1) * 32767))) }
        gv_set_pointer(scale(p.x), scale(p.y), 1)
    }

    private func controllerMask() -> UInt16 {
        let stickIsDpad = !game.system.analog
        var mask: UInt16 = 0
        for c in GCController.controllers() {
            guard let p = c.extendedGamepad else { continue }
            func set(_ on: Bool, _ bit: Int) { if on { mask |= 1 << UInt16(bit) } }
            // the bottom face button is libretro's B, the right one A: the usual RetroArch layout
            set(p.buttonA.isPressed, 0)
            set(p.buttonX.isPressed, 1)
            set(p.buttonOptions?.isPressed ?? false, 2)
            set(p.buttonMenu.isPressed, 3)
            let sx = stickIsDpad ? p.leftThumbstick.xAxis.value : 0
            let sy = stickIsDpad ? p.leftThumbstick.yAxis.value : 0
            set(p.dpad.up.isPressed || sy > 0.5, 4)
            set(p.dpad.down.isPressed || sy < -0.5, 5)
            set(p.dpad.left.isPressed || sx < -0.5, 6)
            set(p.dpad.right.isPressed || sx > 0.5, 7)
            set(p.buttonB.isPressed, 8)
            set(p.buttonY.isPressed, 9)
            set(p.leftShoulder.isPressed, 10)
            set(p.rightShoulder.isPressed, 11)
            set(p.leftTrigger.isPressed, 12)
            set(p.rightTrigger.isPressed, 13)
            set(p.leftThumbstickButton?.isPressed ?? false, 14)
            set(p.rightThumbstickButton?.isPressed ?? false, 15)
            // both stick buttons together: Game Vault's menu (the Xbox controller's own Home button is the phone's)
            if (p.leftThumbstickButton?.isPressed ?? false) && (p.rightThumbstickButton?.isPressed ?? false) {
                paused = true
                return 0
            }
        }
        return mask
    }
}

// CADisplayLink keeps its target alive; this small object stops it from keeping the Emulator alive too.
private final class DisplayTarget: NSObject {
    weak var emulator: Emulator?
    init(_ e: Emulator) { emulator = e }
    @MainActor @objc func tick(_ link: CADisplayLink) {
        if let e = emulator { e.tick(link) } else { link.invalidate() }
    }
}
