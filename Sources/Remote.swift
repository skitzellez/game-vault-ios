// Copyright (c) 2026 Skitzelles - part of Game Vault, https://github.com/skitzellez/xbox-game-vault
// PolyForm Noncommercial License 1.0.0: not for sale, and this notice stays in every copy.
// Game Vault for iPhone - remote play (protocol 1, remote-stream/PROTOCOL.md): the Xbox runs the game, this phone
// shows its picture and sends the controller. Control: POST /v1/remote/play to the Xbox's Game Vault; stream: one TCP
// connection to the emulator, 5-byte headers (type, length LE). The picture is H.264 / HEVC, decoded by the phone's own
// hardware straight onto the screen (AVSampleBufferDisplayLayer), shown the moment it arrives.
import AVFoundation
import CoreMedia
import Foundation
import GameController
import Network
import UIKit

@MainActor
final class RemoteSession: ObservableObject {
    let game: RemoteGame
    @Published var status = "Starting the game on your Xbox…"
    @Published var showing = false     // a picture is on the screen
    @Published var ended: String?      // why the stream stopped (shown to the player)
    @Published var hasController = GCController.controllers().contains { $0.extendedGamepad != nil }

    let layer = AVSampleBufferDisplayLayer()
    var touchButtons: UInt16 = 0       // Xbox controller bits (PROTOCOL.md)
    var touchLT: UInt8 = 0, touchRT: UInt8 = 0
    var touchLeft = CGPoint.zero, touchRight = CGPoint.zero   // -1...1, down is +

    private var connection: NWConnection?
    private var running = false
    private var padTimer: Timer?
    private var lastPad = Data()
    private var lastPadSent = Date.distantPast
    private var seq: UInt32 = 0
    private var decoder = AnnexBDecoder()
    private var decoded: UInt32 = 0, dropped: UInt32 = 0
    private var statsTimer: Timer?

    init(game: RemoteGame) {
        self.game = game
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = UIColor.black.cgColor
    }

    func start() {
        guard !running else { return }
        running = true
        Task { await begin() }
        padTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sendPad() }
        }
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sendStats() }
        }
    }

    // Leaves: the game on the Xbox is closed too (QUIT), as when quitting on the TV.
    func quit() {
        send(0x22, Data())
        stop()
    }

    func stop() {
        running = false
        padTimer?.invalidate()
        statsTimer?.invalidate()
        padTimer = nil
        statsTimer = nil
        let c = connection
        connection = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { c?.cancel() }
    }

    private func begin() async {
        let link = VaultLink.shared
        let path = "/v1/remote/play?id=\(VaultLink.enc(game.id))&w=1280&h=720&phone=\(VaultLink.enc(VaultLink.phoneName))"
        guard let r = await link.request("POST", path, timeout: 30) else {
            finish("The Xbox did not answer. Is Game Vault open on it, and this iPhone on the same Wi-Fi?")
            return
        }
        switch r.code {
        case 200: break
        case 409: finish("Another phone is already playing from this Xbox."); return
        case 404: finish("The Xbox does not have this game any more."); return
        default: finish("The Xbox could not start this game."); return
        }
        guard let json = try? JSONSerialization.jsonObject(with: r.body) as? [String: Any],
              let port = json["port"] as? Int, let token = json["token"] as? String,
              let host = link.link?.host else {
            finish("The Xbox's answer was not understood.")
            return
        }
        status = "Waiting for the picture…"
        // the emulator may still be starting (or a network game being copied): keep trying for 3 minutes
        let deadline = Date().addingTimeInterval(180)
        while running && Date() < deadline {
            if await connect(host: host, port: port, token: token) { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        if running { finish("The game did not start streaming on the Xbox.") }
    }

    // One try: true when the stream ran (it is over when this returns), false when it could not connect.
    private func connect(host: String, port: Int, token: String) async -> Bool {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let c = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: UInt16(port)),
                             using: NWParameters(tls: nil, tcp: tcp))
        let ready: Bool = await withCheckedContinuation { cont in
            var done = false
            c.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if !done { done = true; cont.resume(returning: true) }
                case .failed, .cancelled, .waiting:
                    if !done { done = true; cont.resume(returning: false) }
                default: break
                }
            }
            c.start(queue: .global(qos: .userInteractive))
        }
        guard ready else {
            c.cancel()
            return false
        }
        connection = c
        send(0x01, Data("GVRP1 \(token)".utf8))
        await readLoop(c)
        return true
    }

    private func readLoop(_ c: NWConnection) async {
        while running {
            guard let head = await read(c, 5) else { break }
            let type = head[0]
            let length = Int(head[1]) | Int(head[2]) << 8 | Int(head[3]) << 16 | Int(head[4]) << 24
            guard length <= 8 << 20 else { break }
            let body = length > 0 ? await read(c, length) : Data()
            guard let body else { break }
            handle(type, body)
        }
        if running { finish(ended ?? "The connection to the Xbox was lost.") }
    }

    private func read(_ c: NWConnection, _ count: Int) async -> Data? {
        await withCheckedContinuation { cont in
            c.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, complete, error in
                if let data, data.count == count { cont.resume(returning: data) }
                else { cont.resume(returning: nil) }
                _ = complete
                _ = error
            }
        }
    }

    private func handle(_ type: UInt8, _ body: Data) {
        switch type {
        case 0x10:   // VIDEO_CONFIG: codec u8, width u16, height u16, fps u8
            guard body.count >= 6 else { return }
            decoder = AnnexBDecoder(hevc: body[body.startIndex] == 2)
        case 0x11:   // VIDEO: pts u64, flags u8, Annex B
            guard body.count > 9 else { return }
            let nal = body.subdata(in: (body.startIndex + 9)..<body.endIndex)
            if layer.status == .failed {
                layer.flush()
                decoder.needKey = true
                send(0x21, Data())
            }
            if let sample = decoder.sample(nal) {
                layer.enqueue(sample)
                decoded &+= 1
                if !showing { showing = true }
            } else if decoder.needKey {
                dropped &+= 1
            }
        case 0x1F:   // END
            ended = String(decoding: body, as: UTF8.self)
            finish(ended?.isEmpty == false ? ended! : "The game was closed on the Xbox.")
        default:
            break    // RUMBLE, sound: later
        }
    }

    private func finish(_ why: String) {
        ended = why
        stop()
    }

    private func send(_ type: UInt8, _ body: Data) {
        guard let c = connection else { return }
        var msg = Data([type])
        var n = UInt32(body.count).littleEndian
        msg.append(Data(bytes: &n, count: 4))
        msg.append(body)
        c.send(content: msg, completion: .idempotent)
    }

    // PAD: buttons u16, lt u8, rt u8, lx ly rx ry i16 (up is +), seq u32; on every change and every 100 ms.
    private func sendPad() {
        guard connection != nil else { return }
        var buttons = touchButtons
        var lt = touchLT, rt = touchRT
        var lx = Float(touchLeft.x), ly = Float(-touchLeft.y), rx = Float(touchRight.x), ry = Float(-touchRight.y)
        for c in GCController.controllers() {
            guard let p = c.extendedGamepad else { continue }
            func set(_ on: Bool, _ bit: Int) { if on { buttons |= 1 << UInt16(bit) } }
            set(p.buttonA.isPressed, 0); set(p.buttonB.isPressed, 1); set(p.buttonX.isPressed, 2)
            set(p.buttonY.isPressed, 3); set(p.leftShoulder.isPressed, 4); set(p.rightShoulder.isPressed, 5)
            set(p.buttonOptions?.isPressed ?? false, 6); set(p.buttonMenu.isPressed, 7)
            set(p.leftThumbstickButton?.isPressed ?? false, 8); set(p.rightThumbstickButton?.isPressed ?? false, 9)
            set(p.dpad.up.isPressed, 10); set(p.dpad.down.isPressed, 11)
            set(p.dpad.left.isPressed, 12); set(p.dpad.right.isPressed, 13)
            lt = max(lt, UInt8(p.leftTrigger.value * 255))
            rt = max(rt, UInt8(p.rightTrigger.value * 255))
            if abs(p.leftThumbstick.xAxis.value) + abs(p.leftThumbstick.yAxis.value) > abs(lx) + abs(ly) {
                lx = p.leftThumbstick.xAxis.value
                ly = p.leftThumbstick.yAxis.value
            }
            if abs(p.rightThumbstick.xAxis.value) + abs(p.rightThumbstick.yAxis.value) > abs(rx) + abs(ry) {
                rx = p.rightThumbstick.xAxis.value
                ry = p.rightThumbstick.yAxis.value
            }
        }
        func axis(_ v: Float) -> Int16 { Int16(max(-32767, min(32767, v * 32767))) }
        var state = Data()
        func put<T: FixedWidthInteger>(_ v: T) { var le = v.littleEndian; state.append(Data(bytes: &le, count: MemoryLayout<T>.size)) }
        put(buttons); put(lt); put(rt); put(axis(lx)); put(axis(ly)); put(axis(rx)); put(axis(ry))
        let now = Date()
        guard state != lastPad || now.timeIntervalSince(lastPadSent) >= 0.1 else { return }
        lastPad = state
        lastPadSent = now
        seq &+= 1
        var body = state
        var s = seq.littleEndian
        body.append(Data(bytes: &s, count: 4))
        send(0x20, body)
    }

    private func sendStats() {
        var body = Data()
        var d = decoded.littleEndian, x = dropped.littleEndian, delay = UInt16(0)
        body.append(Data(bytes: &d, count: 4))
        body.append(Data(bytes: &x, count: 4))
        body.append(Data(bytes: &delay, count: 2))
        send(0x23, body)
    }
}

// Annex B access units (start codes) -> CMSampleBuffers the display layer decodes: parameter sets make the format,
// the rest go length-prefixed. Nothing is shown until a key frame with its parameter sets came.
struct AnnexBDecoder {
    var hevc = false
    var needKey = true
    private var format: CMVideoFormatDescription?
    private var params: [Data] = []

    init(hevc: Bool = false) { self.hevc = hevc }

    mutating func sample(_ au: Data) -> CMSampleBuffer? {
        var sets: [Data] = []
        var frame = Data()
        var key = false
        for nal in AnnexBDecoder.units(au) where !nal.isEmpty {
            let b = nal[nal.startIndex]
            let type = hevc ? Int(b >> 1) & 0x3F : Int(b) & 0x1F
            if hevc {
                if type == 32 || type == 33 || type == 34 { sets.append(nal); continue }
                if type == 35 { continue }   // access unit delimiter
                if (16...21).contains(type) { key = true }
            } else {
                if type == 7 || type == 8 { sets.append(nal); continue }
                if type == 9 { continue }
                if type == 5 { key = true }
            }
            var len = UInt32(nal.count).bigEndian
            frame.append(Data(bytes: &len, count: 4))
            frame.append(nal)
        }
        if !sets.isEmpty && sets != params {
            params = sets
            format = AnnexBDecoder.makeFormat(sets, hevc: hevc)
        }
        if needKey && !key { return nil }
        guard let format, !frame.isEmpty else { return nil }
        needKey = false

        var block: CMBlockBuffer?
        let size = frame.count
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: size,
                                                 blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
                                                 offsetToData: 0, dataLength: size, flags: 0,
                                                 blockBufferOut: &block) == noErr, let block else { return nil }
        let copied = frame.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0,
                                          dataLength: size)
        }
        guard copied == noErr else { return nil }
        var sample: CMSampleBuffer?
        var sizes = [size]
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
                                        sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil,
                                        sampleSizeEntryCount: 1, sampleSizeArray: &sizes,
                                        sampleBufferOut: &sample) == noErr, let sample else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }

    static func units(_ data: Data) -> [Data] {
        let bytes = [UInt8](data)
        var out: [Data] = []
        var start = -1
        var i = 0
        while i + 2 < bytes.count {
            if bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 1 {
                if start >= 0 {
                    var end = i
                    if end > start && bytes[end - 1] == 0 { end -= 1 }   // 4-byte start code
                    out.append(Data(bytes[start..<end]))
                }
                i += 3
                start = i
            } else {
                i += 1
            }
        }
        if start >= 0 && start < bytes.count { out.append(Data(bytes[start...])) }
        return out
    }

    static func makeFormat(_ sets: [Data], hevc: Bool) -> CMVideoFormatDescription? {
        let buffers = sets.map { [UInt8]($0) }
        var format: CMVideoFormatDescription?
        let status: OSStatus = withPointers(buffers) { ptrs, sizes in
            if hevc {
                return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                    allocator: kCFAllocatorDefault, parameterSetCount: ptrs.count, parameterSetPointers: ptrs,
                    parameterSetSizes: sizes, nalUnitHeaderLength: 4, extensions: nil, formatDescriptionOut: &format)
            }
            return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                allocator: kCFAllocatorDefault, parameterSetCount: ptrs.count, parameterSetPointers: ptrs,
                parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &format)
        }
        return status == noErr ? format : nil
    }

    private static func withPointers<R>(_ buffers: [[UInt8]],
                                        _ body: ([UnsafePointer<UInt8>], [Int]) -> R) -> R {
        let copies = buffers.map { b -> UnsafeMutablePointer<UInt8> in
            let p = UnsafeMutablePointer<UInt8>.allocate(capacity: max(1, b.count))
            p.initialize(from: b, count: b.count)
            return p
        }
        defer { copies.forEach { $0.deallocate() } }
        return body(copies.map { UnsafePointer($0) }, buffers.map(\.count))
    }
}
