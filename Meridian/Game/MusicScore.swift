import AVFoundation
import Foundation

/// Adaptive score, synthesized at launch. Three stems share one tempo (120 BPM, 2 s bars) and one chord
/// cycle (Dm9 · Cmaj9 · B♭maj9 · Cm9, four bars each), so they always line up and can crossfade freely:
///  - calm (64 s): the original peaceful pads and bells; its second half adds an adventurous horn theme;
///  - tension (32 s): heartbeat drum, pulsing bass ostinato and a string tremolo — enemies are near;
///  - combat (32 s): drums, driving bass, arpeggios and brass stabs — fighting on screen.
/// Notes are rendered event by event into float arrays (fast enough to build in well under a second).
enum MusicScore {
    static let rate = 44_100.0
    static let beat = 0.5
    /// Chord tones (Hz) and bass roots for each 8-second section.
    static let chords: [[Double]] = [[146.8, 174.6, 220.0, 261.6, 329.6], [130.8, 164.8, 196.0, 246.9, 293.7],
                                     [116.5, 146.8, 174.6, 220.0, 261.6], [130.8, 155.6, 196.0, 233.1, 293.7]]
    static let roots: [Double] = [73.4, 65.4, 58.3, 65.4]

    struct Track {
        var s: [Float]
        init(_ seconds: Double) { s = [Float](repeating: 0, count: Int(seconds * MusicScore.rate)) }
        /// Adds a note starting at t0 lasting dur (wrapping round the loop so phrases can cross the seam).
        mutating func add(_ t0: Double, _ dur: Double, _ f: (Double) -> Float) {
            let n = s.count, start = Int(t0 * MusicScore.rate), len = Int(dur * MusicScore.rate)
            for i in 0..<len { s[(start + i) % n] += f(Double(i) / MusicScore.rate) }
        }
        mutating func normalize(_ peak: Float) {
            let m = s.reduce(0) { max($0, abs($1)) }
            guard m > 0 else { return }
            let k = peak / m
            for i in s.indices { s[i] *= k }
        }
    }

    // MARK: Instruments

    nonisolated(unsafe) static var seed: UInt32 = 777
    static func noise() -> Float { seed = seed &* 1664525 &+ 1013904223; return Float(seed >> 8) / Float(1 << 24) * 2 - 1 }
    static func env(_ t: Double, _ attack: Double, _ decay: Double) -> Float { Float(min(1, t / attack) * exp(-decay * t)) }
    static func ar(_ t: Double, _ dur: Double, _ attack: Double, _ release: Double) -> Float {
        Float(min(1, t / attack) * min(1, max(0, dur - t) / release))
    }
    static func sine(_ f: Double, _ t: Double) -> Double { sin(2 * .pi * f * t) }

    static func horn(_ f: Double, _ dur: Double) -> (Double) -> Float {
        { t in
            let vib = 1 + 0.004 * sin(2 * .pi * 5.2 * t) * min(1, t / 0.4)
            let x = sine(f * vib, t) + 0.5 * sine(2 * f * vib, t) + 0.22 * sine(3 * f * vib, t) + 0.08 * sine(4 * f * vib, t)
            return Float(x) * ar(t, dur, 0.09, 0.35) * 0.09
        }
    }
    static func pluck(_ f: Double, _ amp: Float = 0.06) -> (Double) -> Float {
        { t in Float(sine(f, t) + 0.5 * sine(2 * f, t) * exp(-8 * t) + 0.25 * sine(3 * f, t) * exp(-14 * t)) * env(t, 0.002, 6) * amp }
    }
    static func bass(_ f: Double, _ dur: Double, _ amp: Float = 0.12) -> (Double) -> Float {
        { t in Float(sine(f, t) + 0.45 * sine(2 * f, t) + 0.2 * sine(3 * f, t)) * ar(t, dur, 0.01, 0.06) * Float(exp(-2.5 * t)) * amp }
    }
    static func kick(_ amp: Float = 0.5) -> (Double) -> Float {
        { t in Float(sin(2 * .pi * (48 * t + 90 / 30 * (1 - exp(-30 * t))))) * env(t, 0.002, 9) * amp }
    }
    static func snare(_ amp: Float = 0.25) -> (Double) -> Float {
        var lp: Float = 0
        return { t in
            let n = noise(); lp += (n - lp) * 0.35
            return ((n - lp) * env(t, 0.001, 22) * 1.3 + Float(sine(190, t)) * env(t, 0.001, 26) * 0.6) * amp
        }
    }
    static func hat(_ amp: Float = 0.06) -> (Double) -> Float {
        var lp: Float = 0
        return { t in let n = noise(); lp += (n - lp) * 0.5; return (n - lp) * env(t, 0.001, 70) * amp }
    }
    /// Tom: a short, tight drum with only a hint of pitch drop (no springy glide).
    static func tom(_ f: Double, _ amp: Float = 0.3) -> (Double) -> Float {
        var lp: Float = 0
        return { t in
            let n = noise(); lp += (n - lp) * 0.08
            return (Float(sin(2 * .pi * (f * t + f * 0.08 / 30 * (1 - exp(-30 * t))))) * env(t, 0.002, 14) + lp * env(t, 0.001, 30) * 0.8) * amp
        }
    }
    /// Soft heartbeat thump: a felt-mallet low drum, no pitch glide.
    static func thump(_ amp: Float = 0.3) -> (Double) -> Float {
        var lp: Float = 0
        return { t in
            let n = noise(); lp += (n - lp) * 0.03
            return (Float(sine(52, t)) * env(t, 0.004, 16) + lp * env(t, 0.002, 22) * 1.4) * amp
        }
    }
    static func bell(_ f: Double) -> (Double) -> Float {
        { t in Float(sine(f, t) + 0.3 * sine(f * 2.76, t)) * Float(exp(-1.6 * t)) * 0.06 }
    }

    // MARK: Stems

    static func calm() -> [Float] {
        var tr = Track(64)
        let bells: [(Double, Double)] = [(1.5, 587.3), (5.0, 659.3), (9.5, 880.0), (12.0, 784.0), (17.5, 587.3), (21.0, 698.5), (25.5, 880.0), (29.0, 523.3)]
        for half in 0..<2 {
            let off = Double(half) * 32
            for (ci, ch) in chords.enumerated() {
                let t0 = off + Double(ci) * 8
                for (k, f) in ch.enumerated() {
                    let det = 1 + Double(k) * 0.0007
                    tr.add(t0, 8.6) { t in Float(sine(f * det, t) * 0.6 + sine(f * 1.003, t) * 0.4) * 0.07 * ar(t, 8.6, 2.5, 2.8) }
                }
            }
            // Bells in the first half; the horn theme takes over in the second.
            if half == 0 { for (bt, f) in bells { tr.add(off + bt, 3.5, bell(f)) } }
        }
        // Adventurous horn theme (second half): a rising call answered over each chord.
        let theme: [(Double, Double, Double)] = [
            (32.0, 293.7, 1.5), (33.5, 440.0, 0.5), (34.0, 523.3, 1.0), (35.0, 587.3, 2.5),
            (40.0, 659.3, 1.0), (41.0, 587.3, 0.5), (41.5, 523.3, 0.5), (42.0, 392.0, 2.5),
            (48.0, 349.2, 1.0), (49.0, 466.2, 1.0), (50.0, 587.3, 1.0), (51.0, 523.3, 1.0), (52.0, 440.0, 2.5),
            (56.0, 392.0, 1.0), (57.0, 466.2, 1.0), (58.0, 587.3, 1.5), (59.5, 523.3, 0.5), (60.0, 587.3, 3.6)]
        for (t, f, d) in theme { tr.add(t, d + 0.3, horn(f, d + 0.3)); tr.add(t, d + 0.3, horn(f / 2, d + 0.3)) }
        // Drone and wind across the whole loop.
        var wind: Float = 0
        tr.add(0, 64) { t in
            wind += (noise() - wind) * 0.01
            return Float(sine(73.4, t)) * 0.05 + wind * 0.25 * Float(0.5 + 0.5 * sin(2 * .pi * t / 16))
        }
        tr.normalize(0.55)
        return tr.s
    }

    static func tension() -> [Float] {
        var tr = Track(32)
        for bar in 0..<16 {
            let t0 = Double(bar) * 2, ci = bar / 4
            // Heartbeat: lub-dub on beat one.
            tr.add(t0, 0.4, thump(0.34)); tr.add(t0 + 0.32, 0.4, thump(0.2))
            // Bass ostinato in eighths on the root, accenting the bar.
            for e in 0..<8 { let f = roots[ci] * (e == 6 ? 1.5 : 1); tr.add(t0 + Double(e) * 0.25, 0.24, bass(f, 0.24, e % 4 == 0 ? 0.11 : 0.07)) }
        }
        // String tremolo on the chord's fifth and ninth, swelling through each section.
        for ci in 0..<4 {
            for f in [chords[ci][2] * 2, chords[ci][4] * 2] {
                tr.add(Double(ci) * 8, 8.2) { t in Float(sine(f, t) * 0.7 + sine(f * 1.004, t) * 0.3) * Float(0.85 + 0.15 * sin(2 * .pi * 0.5 * t)) * ar(t, 8.2, 3, 1.4) * 0.03 }
            }
        }
        tr.normalize(0.5)
        return tr.s
    }

    static func combat() -> [Float] {
        var tr = Track(32)
        for bar in 0..<16 {
            let t0 = Double(bar) * 2, ci = bar / 4
            // Drums.
            for b in [0.0, 1.0, 1.75] { tr.add(t0 + b, 0.4, kick()) }
            for b in [0.5, 1.5] { tr.add(t0 + b, 0.3, snare()) }
            for e in 0..<8 { tr.add(t0 + Double(e) * 0.25, 0.08, hat(e % 2 == 0 ? 0.07 : 0.04)) }
            if bar % 4 == 3 { for (k, f) in [180.0, 150, 120, 95].enumerated() { tr.add(t0 + 1.0 + Double(k) * 0.25, 0.4, tom(f)) } }
            // Driving octave bass.
            for e in 0..<8 { tr.add(t0 + Double(e) * 0.25, 0.22, bass(roots[ci] * (e % 2 == 0 ? 1 : 2), 0.22, 0.13)) }
            // Sixteenth-note arpeggio high over the chord.
            let ch = chords[ci]
            for s16 in 0..<8 { tr.add(t0 + Double(s16) * 0.25, 0.3, pluck(ch[[0, 2, 4, 2, 1, 3, 4, 3][s16]] * 2, 0.045)) }
            // Brass stabs at the top of every other bar.
            if bar % 2 == 0 { for f in ch.prefix(3) { tr.add(t0, 0.45, horn(f, 0.45)) } }
        }
        tr.normalize(0.6)
        return tr.s
    }

    /// Development: renders each stem (and a calm→tension→combat preview mix) to WAV files.
    static func writeWAVs(to dir: URL) {
        let t0 = Date()
        let stems: [(String, [Float])] = [("calm", calm()), ("tension", tension()), ("combat", combat())]
        print(String(format: "MUSIC generated in %.2fs", Date().timeIntervalSince(t0)))
        func write(_ name: String, _ s: [Float]) {
            guard let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
                  let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(s.count)),
                  let file = try? AVAudioFile(forWriting: dir.appendingPathComponent(name + ".wav"), settings: fmt.settings) else { return }
            buf.frameLength = AVAudioFrameCount(s.count)
            for i in 0..<s.count { buf.floatChannelData![0][i] = max(-1, min(1, s[i])) }
            try? file.write(from: buf)
            let rms = (s.reduce(0) { $0 + $1 * $1 } / Float(s.count)).squareRoot()
            print(String(format: "MUSIC %@ %.1fs rms=%.3f", name, Double(s.count) / rate, rms))
        }
        for (n, s) in stems { write(n, s) }
        // Preview: 32 s calm, then tension fades in, then combat, then back down — as in play.
        let calmS = stems[0].1, ten = stems[1].1, com = stems[2].1, n = Int(96 * rate)
        var mix = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / rate
            let tens = Float(min(1, max(0, (t - 28) / 4)) * min(1, max(0, (90 - t) / 8)))
            let comb = Float(min(1, max(0, (t - 56) / 2)) * min(1, max(0, (86 - t) / 7)))
            mix[i] = calmS[i % calmS.count] * (0.95 - 0.35 * comb) + ten[i % ten.count] * 0.75 * tens * (1 - 0.4 * comb) + com[i % com.count] * 0.85 * comb
        }
        write("preview", mix)
    }
}
