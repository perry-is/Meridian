import AVFoundation
import Foundation
import QuartzCore
import MeridianCore

/// Unit radio chatter: short subtitled lines, voiced as synthesized radio babble (no recorded speech).
///  - Concord: formant "speech" through a radio band-pass with squelch clicks.
///  - Lattice: monotone, bit-crushed and ring-modulated, bracketed by chirps.
///  - Brood: clicking chitter over a low growl.
/// Units say very little: a line now and then on selection or orders, never on every tap.
@MainActor
final class Radio: ObservableObject {
    struct Line: Identifiable {
        let id = UUID()
        let unitType: Int
        let speaker: String
        let text: String
        let faction: Faction
        /// Media time the audio starts.
        let start: Double
        let duration: Double
        /// Syllable (start, length) offsets from `start`, for mouth sync.
        let syllables: [(Double, Double)]
    }

    enum Kind { case select, move, attack, hurt, poke }

    @Published private(set) var line: Line? = nil
    /// Units are quiet for now (the radio babble broke the game's calm); lines still show as subtitles
    /// and still drive the portrait's mouth. Set true to hear the synthesized chatter again.
    static var voiceEnabled = false
    private var lastSpoke = -100.0
    private var lastSelectType = -1
    private var lastSelectAt = -100.0
    private var pokes = 0
    private var counter = 0

    /// Mouth opening for a portrait of `unitType` at media time `now`.
    func mouth(at now: Double, unitType: Int) -> CGFloat {
        guard let l = line, l.unitType == unitType else { return 0 }
        let t = now - l.start
        guard t >= 0, t <= l.duration else { return 0 }
        for (i, s) in l.syllables.enumerated() where t >= s.0 && t < s.0 + s.1 {
            let u = (t - s.0) / s.1
            let amp = 0.65 + 0.35 * PortraitArt.hash(i, l.unitType)
            return CGFloat(pow(sin(.pi * u), 0.6) * amp)
        }
        return 0
    }

    /// Decides whether this unit speaks now, picks a line and voices it.
    func chatter(_ kind: Kind, unit d: UnitDef, type: Int, faction: Faction) {
        let now = CACurrentMediaTime()
        var kind = kind
        var chance = 0.0, gap = 0.0
        switch kind {
        case .select:
            if type == lastSelectType && now - lastSelectAt < 1.6 { pokes += 1 } else { pokes = 0 }
            let fresh = type != lastSelectType || now - lastSelectAt > 12
            lastSelectType = type; lastSelectAt = now
            if pokes >= 4 { kind = .poke; pokes = 0; chance = 1; gap = 1 }
            else { chance = fresh ? 0.6 : 0.15; gap = 3.5 }
        case .hurt: chance = 1; gap = 3
        case .move, .attack: chance = 0.3; gap = 6
        case .poke: chance = 1; gap = 1
        }
        guard now - lastSpoke > gap, Double.random(in: 0..<1) < chance else { return }
        let options = RadioLines.lines(kind, unit: d, faction: faction)
        guard !options.isEmpty else { return }
        counter += 1
        let text = options[(Int.random(in: 0..<1000) + counter) % options.count]
        lastSpoke = now
        let seed = UInt32(truncatingIfNeeded: type &* 7919 &+ counter)
        let pitch = RadioVoice.pitch(d)
        DispatchQueue.global(qos: .userInitiated).async {
            let v = RadioVoice.synth(text, faction: faction, pitch: pitch, seed: seed)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let start = CACurrentMediaTime() + 0.03
                if Radio.voiceEnabled { SoundEngine.shared?.playRadio(v.samples) }
                let l = Line(unitType: type, speaker: d.name, text: text, faction: faction, start: start, duration: v.duration, syllables: v.syllables)
                self.line = l
                DispatchQueue.main.asyncAfter(deadline: .now() + v.duration + 1.8) { [weak self] in
                    if self?.line?.id == l.id { self?.line = nil }
                }
            }
        }
    }
}

// MARK: - Lines

enum RadioLines {
    static func lines(_ kind: Radio.Kind, unit d: UnitDef, faction: Faction) -> [String] {
        let role = d.role, air = d.domain == .air
        switch faction {
        case .humans:
            switch kind {
            case .select:
                if role == "worker" { return ["Tools ready.", "What are we building?", "Engineer here.", "Got a job?"] }
                if role == "support" { return ["Who's hurt?", "Doc's here.", "Medic, standing by."] }
                if role == "infiltration" { return ["...", "Unseen.", "Say the word."] }
                if role == "heavy" { return ["Bastion, rolling.", "Armor's ready.", "Main gun loaded."] }
                if role == "siege" { return ["Tubes ready.", "Give me coordinates."] }
                if air { return ["Wheels up.", "Skies are clear.", "On station."] }
                if role == "scout" { return ["Eyes open.", "Pathfinder here."] }
                return ["Go ahead.", "Standing by.", "Yes, Commander?", "Ready."]
            case .move:
                if air { return ["Vectoring.", "Inbound.", "Coming about."] }
                if role == "worker" { return ["On my way.", "Got it."] }
                return ["Moving.", "On it.", "Heading out.", "Copy that.", "Roger."]
            case .attack:
                if role == "heavy" || role == "siege" { return ["Firing!", "Shot out.", "Main gun, fire!"] }
                if role == "support" { return ["Covering fire!"] }
                return ["Engaging.", "Weapons free.", "Contact!", "Taking the shot."]
            case .hurt: return ["Taking fire!", "I'm hit.", "Need a medic!"]
            case .poke: return ["Still here.", "Yes, I hear you.", "Commander, please.", "Radio's fine, sir."]
            }
        case .machines:
            switch kind {
            case .select:
                if role == "worker" { return ["Fabricator online.", "Specify construct.", "Awaiting schematic."] }
                if role == "support" { return ["Repair protocol ready.", "Diagnostics active."] }
                if role == "heavy" { return ["Bulwark online.", "Armor nominal."] }
                return ["Online.", "Awaiting directive.", "Unit active.", "Listening."]
            case .move: return ["Vector accepted.", "Relocating.", "Path computed.", "Affirmative."]
            case .attack: return ["Target acquired.", "Executing.", "Hostile flagged.", "Discharging."]
            case .hurt: return ["Integrity failing.", "Damage critical.", "Hull breach."]
            case .poke: return ["Repeated input detected.", "Query redundant.", "Please stop.", "Error: patience."]
            }
        case .aliens:
            switch kind {
            case .select:
                if role == "worker" { return ["We weave.", "Shape the bloom.", "Hungry hands."] }
                if role == "support" { return ["We mend.", "Grow again."] }
                if role == "heavy" { return ["We are mountain.", "Crush."] }
                return ["We hear.", "The hive stirs.", "Hungry.", "Speak, mind."]
            case .move: return ["We go.", "Scuttling.", "Through the grass.", "Yes."]
            case .attack: return ["Prey!", "Feast.", "Rend them.", "Break shell."]
            case .hurt: return ["It burns.", "Shell cracked.", "Pain."]
            case .poke: return ["Why poke us.", "We bite.", "Stop.", "Annoyed hive."]
            }
        }
    }
}

// MARK: - Synthesis

enum RadioVoice {
    static let rate = 44_100.0

    /// Voice pitch per unit: crews of heavy machines and big creatures speak lower.
    static func pitch(_ d: UnitDef) -> Double {
        let h = Double(hnoise(d.id.count, Int(d.id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }), 3))
        var p = 120 + h * 70
        if ["heavy", "siege"].contains(d.role) { p *= 0.78 }
        if d.role == "scout" || d.role == "fast" { p *= 1.12 }
        return p
    }

    struct Voiced { var samples: [Float]; var duration: Double; var syllables: [(Double, Double)] }

    private struct Rng {
        var s: UInt32
        mutating func next() -> Double { s = s &* 1664525 &+ 1013904223; return Double(s >> 8) / Double(1 << 24) }
        mutating func noise() -> Float { Float(next() * 2 - 1) }
    }

    /// Two-pole resonator (band-pass) state.
    private struct Reso {
        var b1 = 0.0, b2 = 0.0, a0 = 0.0, y1 = 0.0, y2 = 0.0
        mutating func set(_ f: Double, _ bw: Double) {
            let r = exp(-.pi * bw / RadioVoice.rate)
            b1 = 2 * r * cos(2 * .pi * f / RadioVoice.rate); b2 = -r * r; a0 = 1 - r
        }
        mutating func run(_ x: Double) -> Double { let y = a0 * x + b1 * y1 + b2 * y2; y2 = y1; y1 = y; return y }
    }

    static func synth(_ text: String, faction: Faction, pitch: Double, seed: UInt32) -> Voiced {
        var rng = Rng(s: seed | 1)
        // Syllable plan from the text: roughly one per vowel group, a pause between words.
        var plan: [(Double, Double)] = []
        let lead = faction == .aliens ? 0.04 : 0.07
        var t = lead
        let words = text.split(whereSeparator: { $0 == " " }).map(String.init)
        for (wi, w) in words.enumerated() {
            var groups = 0, inVowel = false
            for c in w.lowercased() { let v = "aeiouy".contains(c); if v && !inVowel { groups += 1 }; inVowel = v }
            groups = max(1, min(4, groups))
            if w.allSatisfy({ $0 == "." }) { t += 0.5; continue }
            for _ in 0..<groups {
                let d: Double
                switch faction {
                case .machines: d = 0.085
                case .aliens: d = 0.06 + rng.next() * 0.07
                case .humans: d = 0.08 + rng.next() * 0.08
                }
                plan.append((t, d))
                t += d + (faction == .machines ? 0.03 : 0.025 + rng.next() * 0.03)
            }
            if wi < words.count - 1 { t += 0.07 }
        }
        let tail = faction == .aliens ? 0.08 : 0.12
        let total = t + tail
        let n = Int(total * rate)
        var out = [Float](repeating: 0, count: n)

        let vowels: [(Double, Double)] = [(730, 1090), (530, 1840), (290, 2250), (570, 840), (320, 900), (650, 1500)]
        var f1 = Reso(), f2 = Reso(), f3 = Reso()
        var phase = 0.0
        for (si, s) in plan.enumerated() {
            let v = vowels[Int(rng.next() * Double(vowels.count)) % vowels.count]
            f1.set(v.0, 90); f2.set(v.1, 120); f3.set(2600, 200)
            let i0 = Int(s.0 * rate), len = Int(s.1 * rate)
            let last = si == plan.count - 1
            let step = faction == .machines ? [1.0, 1.122, 0.891][Int(rng.next() * 3) % 3] : 1.0
            let clickRate = 35 + rng.next() * 40
            let reso = 1100 + rng.next() * 1300
            var click = Reso(); click.set(reso, 260)
            var growl = Reso(); growl.set(420, 140)
            let burst = rng.next() < 0.5
            for k in 0..<len where i0 + k < n {
                let lt = Double(k) / rate
                let u = Double(k) / Double(len)
                let env = min(1, lt / 0.012) * min(1, (s.1 - lt) / 0.03)
                var x = 0.0
                switch faction {
                case .humans:
                    let f0 = pitch * (1 + 0.06 * sin(u * .pi)) * (last ? 1 - 0.18 * u : 1)
                    phase += f0 / rate; if phase >= 1 { phase -= 1 }
                    let src = phase * 2 - 1
                    x = f1.run(src) * 1.0 + f2.run(src) * 0.7 + f3.run(src) * 0.25
                    if burst && lt < 0.018 { x += Double(rng.noise()) * 0.35 * (1 - lt / 0.018) }
                case .machines:
                    let f0 = pitch * 0.9 * step
                    phase += f0 / rate; if phase >= 1 { phase -= 1 }
                    let src = phase < 0.5 ? 1.0 : -1.0
                    x = f1.run(src) * 0.9 + f2.run(src) * 0.8
                    x *= 0.7 + 0.3 * sin(2 * .pi * 70 * lt)
                case .aliens:
                    let ct = (lt * clickRate).truncatingRemainder(dividingBy: 1)
                    let imp = ct < 0.08 ? Double(rng.noise()) : 0
                    x = click.run(imp) * 6
                    phase += pitch * 0.5 * (1 + 0.05 * sin(lt * 38)) / rate; if phase >= 1 { phase -= 1 }
                    x += growl.run(phase * 2 - 1) * 0.6
                }
                out[i0 + k] += Float(x * env)
            }
        }
        // Radio treatment.
        var hp = 0.0, hpx = 0.0, lp1 = 0.0, lp2 = 0.0
        let hpk = exp(-2 * .pi * (faction == .aliens ? 160 : 380) / rate)
        let lpk = 1 - exp(-2 * .pi * (faction == .aliens ? 3200 : 2700) / rate)
        var hold: Float = 0
        for i in 0..<n {
            var x = Double(out[i])
            hp = hpk * (hp + x - hpx); hpx = x; x = hp
            lp1 += (x - lp1) * lpk; lp2 += (lp1 - lp2) * lpk; x = lp2
            if faction == .machines {
                if i % 7 == 0 { hold = Float((x * 10).rounded() / 10) }
                x = Double(hold)
            }
            x = tanh(x * 2.4)
            let tt = Double(i) / rate
            let inTx = tt > lead * 0.5 && tt < total - tail * 0.3
            if inTx { x += Double(rng.noise()) * (faction == .aliens ? 0.012 : 0.022) }
            out[i] = Float(x)
        }
        // Squelch / chirps at the edges.
        func addNoise(_ t0: Double, _ dur: Double, _ amp: Float) {
            let a = Int(t0 * rate), b = min(n, a + Int(dur * rate))
            guard a < b else { return }
            for i in a..<b { let u = Float(i - a) / Float(b - a); out[i] += rng.noise() * amp * (1 - u) }
        }
        func addTone(_ t0: Double, _ dur: Double, _ f: Double, _ amp: Float) {
            let a = Int(t0 * rate), b = min(n, a + Int(dur * rate))
            guard a < b else { return }
            for i in a..<b { let lt = Double(i - a) / rate; out[i] += Float(sin(2 * .pi * f * lt)) * amp * Float(min(1, (dur - lt) / 0.01)) }
        }
        switch faction {
        case .humans: addNoise(0, 0.035, 0.3); addNoise(total - tail, 0.09, 0.22)
        case .machines: addTone(0, 0.03, 1480, 0.16); addTone(0.035, 0.03, 1860, 0.16); addTone(total - tail * 0.8, 0.05, 920, 0.14)
        case .aliens: addNoise(0, 0.05, 0.08)
        }
        let peak = out.reduce(Float(0)) { max($0, abs($1)) }
        if peak > 0 { let g = 0.62 / peak; for i in 0..<n { out[i] *= g } }
        return Voiced(samples: out, duration: total, syllables: plan)
    }
}


extension RadioVoice {
    /// Development: writes a reel of sample lines per faction (one WAV each) for listening.
    static func writeSamples(to dir: URL) {
        let data = GameData.shared
        for f in Faction.allCases {
            var reel: [Float] = []
            for (k, u) in data.unitIDs(f).prefix(6).enumerated() {
                let d = data.units[u]
                let kinds: [Radio.Kind] = [.select, .move, .attack]
                let opts = RadioLines.lines(kinds[k % 3], unit: d, faction: f)
                let v = synth(opts[k % opts.count], faction: f, pitch: pitch(d), seed: UInt32(k * 97 + 5))
                reel += v.samples + [Float](repeating: 0, count: Int(rate * 0.5))
                print("RADIO \(f.rawValue) \(d.name): \(opts[k % opts.count]) \(String(format: "%.2fs", v.duration))")
            }
            guard let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
                  let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(reel.count)),
                  let file = try? AVAudioFile(forWriting: dir.appendingPathComponent("radio_\(f.rawValue).wav"), settings: fmt.settings) else { continue }
            buf.frameLength = AVAudioFrameCount(reel.count)
            for i in 0..<reel.count { buf.floatChannelData![0][i] = max(-1, min(1, reel[i])) }
            try? file.write(from: buf)
            let rms = (reel.reduce(0) { $0 + $1 * $1 } / Float(reel.count)).squareRoot()
            print(String(format: "RADIO reel %@ %.1fs rms=%.3f nan=%d", f.rawValue, Double(reel.count) / rate, rms, reel.contains { $0.isNaN } ? 1 : 0))
        }
    }
}
