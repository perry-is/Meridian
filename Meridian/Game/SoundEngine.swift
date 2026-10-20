import AVFoundation
import CoreGraphics
import Foundation

/// Fully synthesized audio: every effect and the ambient score are generated at launch (no external assets).
/// Effects are spatialised against the camera (pan + distance attenuation) and throttled per sound.
final class SoundEngine {
    static let shared: SoundEngine? = SoundEngine()

    private let engine = AVAudioEngine()
    private let sfxMixer = AVAudioMixerNode()
    private let musicMixer = AVAudioMixerNode()
    private var voices: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private let music = AVAudioPlayerNode()
    private var buffers: [String: [AVAudioPCMBuffer]] = [:]
    private var lastPlayed: [String: Double] = [:]
    private let format: AVAudioFormat
    private var started = false
    private var busyUntil: [Double] = []
    private var windowStart = 0.0
    private var windowCount = 0
    private let queue = DispatchQueue(label: "meridian.audio", qos: .userInitiated)
    private let rate: Double = 44_100

    /// Camera position and visible half-width in scene points (set by the scene each frame).
    var listener = CGPoint.zero
    var hearing: CGFloat = 900

    var master: Float { didSet { save(); apply() } }
    var sfxVolume: Float { didSet { save(); apply() } }
    var musicVolume: Float { didSet { save(); apply() } }

    private init?() {
        guard let f = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else { return nil }
        format = f
        let d = UserDefaults.standard
        master = d.object(forKey: "vol.master") as? Float ?? 0.8
        sfxVolume = d.object(forKey: "vol.sfx") as? Float ?? 0.8
        musicVolume = d.object(forKey: "vol.music") as? Float ?? 0.45
        generate()
        setup()
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(master, forKey: "vol.master"); d.set(sfxVolume, forKey: "vol.sfx"); d.set(musicVolume, forKey: "vol.music")
    }

    private func apply() {
        sfxMixer.outputVolume = sfxVolume
        musicMixer.outputVolume = musicVolume
        engine.mainMixerNode.outputVolume = master
    }

    private func setup() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        engine.attach(sfxMixer); engine.attach(musicMixer); engine.attach(music)
        engine.connect(sfxMixer, to: engine.mainMixerNode, format: format)
        engine.connect(musicMixer, to: engine.mainMixerNode, format: format)
        engine.connect(music, to: musicMixer, format: format)
        for _ in 0..<20 {
            let v = AVAudioPlayerNode()
            engine.attach(v)
            engine.connect(v, to: sfxMixer, format: format)
            voices.append(v)
        }
        busyUntil = Array(repeating: 0, count: voices.count)
        apply()
        do { try engine.start(); started = true } catch { started = false }
        // Voices run permanently; playback is just queueing buffers onto an idle voice.
        if started { voices.forEach { $0.play() } }
        if started, let m = buffers["music"]?.first {
            music.scheduleBuffer(m, at: nil, options: .loops)
            music.volume = 0.9
            music.play()
        }
    }

    // MARK: Playback

    func play(_ name: String, at p: CGPoint?, volume: Float = 1, minGap: Double = 0.06) {
        guard started, let set = buffers[name], !set.isEmpty else { return }
        let now = CACurrentMediaTime()
        if let last = lastPlayed[name], now - last < minGap { return }
        var vol = volume, pan: Float = 0
        if let p = p {
            let dx = p.x - listener.x, dy = p.y - listener.y
            let d = hypot(dx, dy)
            if d > hearing * 1.6 { return }
            vol *= Float(max(0.08, 1 - d / (hearing * 1.6)))
            pan = Float(max(-0.85, min(0.85, dx / hearing)))
        }
        // Global budget keeps huge battles from flooding the mixer (and the main thread).
        if now - windowStart > 0.1 { windowStart = now; windowCount = 0 }
        guard windowCount < 14 else { return }
        guard let vi = (0..<voices.count).first(where: { busyUntil[($0 + nextVoice) % voices.count] <= now }).map({ ($0 + nextVoice) % voices.count }) else { return }
        windowCount += 1
        lastPlayed[name] = now
        nextVoice = (vi + 1) % voices.count
        let buf = set[Int.random(in: 0..<set.count)]
        busyUntil[vi] = now + Double(buf.frameLength) / rate + 0.01
        let v = voices[vi]
        queue.async {
            v.volume = vol
            v.pan = pan
            v.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
        }
    }

    func shot(_ style: String, at p: CGPoint?) {
        let key: String
        switch style {
        case "bullet": key = "gun"
        case "rocket", "missile": key = "rocket"
        case "shell", "bomb": key = "cannon"
        case "arc": key = "zap"
        case "rail": key = "rail"
        case "pulse", "beam", "flak": key = "pulse"
        case "acid", "spore": key = "acid"
        case "spine": key = "spine"
        case "claw": key = "slash"
        case "quake": key = "quake"
        default: key = "gun"
        }
        play(key, at: p, volume: 0.55, minGap: 0.07)
    }

    func explosion(big: Bool, at p: CGPoint?) { play(big ? "boom" : "pop", at: p, volume: big ? 1 : 0.7, minGap: big ? 0.12 : 0.08) }

    // MARK: Synthesis

    private var seed: UInt32 = 12345
    private func noise() -> Float { seed = seed &* 1664525 &+ 1013904223; return Float(seed >> 8) / Float(1 << 24) * 2 - 1 }

    private func make(_ dur: Double, _ f: (Double, Double) -> Float) -> AVAudioPCMBuffer {
        let n = AVAudioFrameCount(dur * rate)
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n)!
        b.frameLength = n
        let out = b.floatChannelData![0]
        for i in 0..<Int(n) {
            let t = Double(i) / rate
            out[i] = max(-1, min(1, f(t, t / dur)))
        }
        // De-click: short fade in/out.
        let fade = min(Int(n) / 4, 64)
        for i in 0..<fade { let g = Float(i) / Float(fade); out[i] *= g; out[Int(n) - 1 - i] *= g }
        return b
    }

    private func env(_ x: Double, attack: Double = 0.01, decay: Double = 6) -> Float { Float(min(1, x / attack) * exp(-decay * x)) }

    private func generate() {
        var lp: Float = 0, lp2: Float = 0
        func lowpass(_ x: Float, _ k: Float) -> Float { lp += (x - lp) * k; return lp }
        func lowpass2(_ x: Float, _ k: Float) -> Float { lp2 += (x - lp2) * k; return lp2 }
        // Concord gun: crack + thump.
        buffers["gun"] = (0..<3).map { v in
            make(0.16) { t, x in
                let crack = self.noise() * self.env(t, attack: 0.001, decay: 55)
                let thump = Float(sin(2 * .pi * (140 - 300 * t) * t)) * self.env(t, attack: 0.002, decay: 30)
                return (crack * 0.7 + thump * 0.6) * (0.9 + Float(v) * 0.05)
            }
        }
        buffers["rocket"] = [make(0.5) { t, x in
            let n = lowpass(self.noise(), Float(0.05 + 0.25 * x))
            return n * 2.2 * Float(sin(.pi * x)) * 0.9
        }]
        buffers["cannon"] = [make(0.6) { t, _ in
            let body = Float(sin(2 * .pi * (70 - 40 * t) * t)) * self.env(t, attack: 0.003, decay: 7)
            return body * 0.9 + lowpass(self.noise(), 0.1) * self.env(t, attack: 0.001, decay: 12) * 1.2
        }]
        buffers["zap"] = (0..<2).map { v in
            make(0.18) { t, x in
                let f = 900.0 + 600 * sin(2 * .pi * 40 * t) + Double(v) * 120
                let sq: Float = sin(2 * .pi * f * t) > 0 ? 0.5 : -0.5
                return (sq * 0.6 + self.noise() * 0.35) * self.env(t, attack: 0.002, decay: 16)
            }
        }
        buffers["rail"] = [make(0.4) { t, _ in
            let f = 2400 * exp(-6 * t) + 180
            return Float(sin(2 * .pi * f * t)) * self.env(t, attack: 0.002, decay: 7) * 0.7 + self.noise() * self.env(t, attack: 0.001, decay: 40) * 0.5
        }]
        buffers["pulse"] = [make(0.16) { t, _ in
            let f = 700 - 1800 * t
            return Float(sin(2 * .pi * f * t) + 0.4 * sin(4 * .pi * f * t)) * self.env(t, attack: 0.002, decay: 18) * 0.55
        }]
        buffers["acid"] = [make(0.28) { t, x in
            let w = Float(sin(2 * .pi * (220 + 120 * sin(30 * t)) * t))
            return (lowpass(self.noise(), 0.15) * 1.6 + w * 0.3) * self.env(t, attack: 0.01, decay: 9)
        }]
        buffers["spine"] = [make(0.12) { t, x in
            lowpass2(self.noise(), Float(0.6 - 0.5 * x)) * self.env(t, attack: 0.002, decay: 22) * 1.2
        }]
        buffers["slash"] = [make(0.16) { t, x in
            let n = self.noise() - lowpass(self.noise(), 0.3)
            return n * Float(sin(.pi * x)) * 0.9
        }]
        buffers["quake"] = [make(0.7) { t, _ in
            Float(sin(2 * .pi * 45 * t)) * self.env(t, attack: 0.02, decay: 4) + lowpass(self.noise(), 0.04) * self.env(t, attack: 0.01, decay: 5) * 2
        }]
        buffers["pop"] = (0..<2).map { v in
            make(0.45) { t, _ in
                let n = lowpass(self.noise(), Float(0.18 + Double(v) * 0.05))
                return n * 2.0 * self.env(t, attack: 0.002, decay: 9) + Float(sin(2 * .pi * (90 - 60 * t) * t)) * self.env(t, attack: 0.003, decay: 10) * 0.6
            }
        }
        buffers["boom"] = [make(1.4) { t, _ in
            let n = lowpass(self.noise(), 0.06) * 3.0 * self.env(t, attack: 0.004, decay: 3.2)
            let sub = Float(sin(2 * .pi * (55 - 25 * t) * t)) * self.env(t, attack: 0.005, decay: 3.5)
            let crackle = self.noise() * self.env(t, attack: 0.001, decay: 20) * 0.5
            return n + sub * 0.8 + crackle
        }]
        // Interface.
        func tone(_ f: Double, _ dur: Double, _ amp: Float = 0.35) -> AVAudioPCMBuffer {
            make(dur) { t, _ in Float(sin(2 * .pi * f * t) + 0.25 * sin(4 * .pi * f * t)) * self.env(t, attack: 0.004, decay: 1 / dur * 4) * amp }
        }
        func seq(_ notes: [Double], _ step: Double, _ amp: Float = 0.3) -> AVAudioPCMBuffer {
            make(step * Double(notes.count) + 0.35) { t, _ in
                var s: Float = 0
                for (i, f) in notes.enumerated() {
                    let lt = t - Double(i) * step
                    if lt > 0 { s += Float(sin(2 * .pi * f * lt) + 0.3 * sin(2 * .pi * f * 2 * lt)) * self.env(lt, attack: 0.005, decay: 7) }
                }
                return s * amp
            }
        }
        buffers["click"] = [tone(1400, 0.05, 0.22)]
        buffers["confirm"] = [seq([880, 1320], 0.045, 0.22)]
        buffers["denied"] = [make(0.18) { t, _ in (Float(sin(2 * .pi * 180 * t)) > 0 ? 0.25 : -0.25) * self.env(t, attack: 0.003, decay: 14) }]
        buffers["cancel"] = [seq([660, 440], 0.05, 0.2)]
        buffers["move"] = [seq([520, 780], 0.04, 0.18)]
        buffers["attack"] = [seq([600, 450, 600], 0.035, 0.2)]
        buffers["built"] = [seq([523, 659, 784, 1047], 0.08, 0.25)]
        buffers["ready"] = [seq([784, 1047], 0.07, 0.22)]
        buffers["capture"] = [seq([392, 523, 659, 784], 0.09, 0.28)]
        buffers["alert"] = [seq([740, 554, 740, 554], 0.12, 0.25)]
        buffers["emp"] = [make(0.6) { t, _ in Float(sin(2 * .pi * (300 + 200 * sin(40 * t)) * t)) * self.env(t, attack: 0.01, decay: 5) * 0.5 }]
        buffers["victory"] = [seq([523, 659, 784, 1047, 1319], 0.14, 0.3)]
        buffers["defeat"] = [seq([440, 349, 294, 220], 0.2, 0.3)]
        buffers["music"] = [score()]
    }

    /// 32-second ambient loop: slow minor-ninth pads over a drone, with sparse pentatonic bell notes.
    private func score() -> AVAudioPCMBuffer {
        let dur = 32.0
        let chords: [[Double]] = [[146.8, 174.6, 220.0, 261.6, 329.6], [130.8, 164.8, 196.0, 246.9, 293.7],
                                  [116.5, 146.8, 174.6, 220.0, 261.6], [130.8, 155.6, 196.0, 233.1, 293.7]]
        let bells: [(Double, Double)] = [(1.5, 587.3), (5.0, 659.3), (9.5, 880.0), (12.0, 784.0), (17.5, 587.3), (21.0, 698.5), (25.5, 880.0), (29.0, 523.3)]
        var wind: Float = 0
        return make(dur) { t, _ in
            let ci = Int(t / 8) % 4
            let local = t.truncatingRemainder(dividingBy: 8)
            let fadeIn = min(1, local / 2.5), fadeOut = min(1, (8 - local) / 2.5)
            let shape = Float(fadeIn * fadeOut)
            var s: Float = 0
            for (k, f) in chords[ci].enumerated() {
                let det = 1 + Double(k) * 0.0007
                s += Float(sin(2 * .pi * f * det * t) * 0.6 + sin(2 * .pi * f * 1.003 * t) * 0.4) * 0.07
            }
            s *= shape
            s += Float(sin(2 * .pi * 73.4 * t)) * 0.05                                   // drone
            for (bt, f) in bells where t >= bt && t < bt + 3.5 {
                let lt = t - bt
                s += Float(sin(2 * .pi * f * lt) + 0.3 * sin(2 * .pi * f * 2.76 * lt)) * Float(exp(-1.6 * lt)) * 0.06
            }
            wind += (self.noise() - wind) * 0.01
            s += wind * 0.25 * Float(0.5 + 0.5 * sin(2 * .pi * t / 16))
            // Seamless loop edges.
            let edge = Float(min(1, t / 1.0, (dur - t) / 1.0))
            return s * edge
        }
    }
}
