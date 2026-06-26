//
//  GameFeel.swift
//  wits
//
//  The "juice" layer — one place every game calls to feel alive. Synthesised
//  sound effects (no asset files), haptics, and SwiftUI modifiers for screen
//  shake, colour flash, and particle bursts. A game fires a single
//  `GameFeel.shared.play(event)` at its correct/wrong/etc. sites — no signature
//  or environment changes across the 13 games.
//

import SwiftUI
import AVFoundation
import UIKit
import os

// MARK: - Events

enum FeelEvent {
    case correct(combo: Int)     // pitch rises with the combo
    case wrong
    case nearMiss                // "so close" — feels almost, still counts as a miss
    case timeout
    case lifeLost(remaining: Int)
    case levelUp                 // survival escalation tier crossed
    case comboMilestone(Int)     // every N in a row
    case newBest
    case gameOver
}

// MARK: - Dispatch

@MainActor
final class GameFeel {
    static let shared = GameFeel()

    var soundEnabled = true
    var hapticsEnabled = true

    private let haptics = HapticBox()
    private let synth = ToneSynth()

    private init() {}

    /// Prepare haptics + start the audio engine. Call when a game host appears.
    func warmUp() {
        haptics.prepare()
        if soundEnabled { synth.start() }
    }

    /// Release the audio session. Call when the host dismisses.
    func teardown() {
        synth.stop()
    }

    func play(_ e: FeelEvent) {
        switch e {
        case .correct(let combo):
            haptics.impact(.light, intensity: 0.7)
            // semitone-per-combo rise, capped so it doesn't get shrill
            let steps = Double(min(combo, 12))
            synth.blip(freq: 620 * pow(2.0, steps / 12.0), wave: .sine, ms: 70, gain: 0.45)
        case .wrong:
            haptics.notify(.error)
            synth.blip(freq: 150, wave: .square, ms: 170, gain: 0.5)
        case .nearMiss:
            haptics.impact(.soft, intensity: 0.6)
            synth.sweep(from: 540, to: 360, ms: 130, wave: .triangle, gain: 0.4)
        case .timeout:
            haptics.impact(.rigid)
            synth.blip(freq: 196, wave: .square, ms: 140, gain: 0.45)
        case .lifeLost(let remaining):
            haptics.notify(remaining <= 0 ? .error : .warning)
            synth.sweep(from: 440, to: 130, ms: 300, wave: .sawtooth, gain: 0.55)
        case .levelUp:
            haptics.impact(.medium)
            synth.arpeggio([523, 659, 784], stepMs: 55, wave: .sine, gain: 0.4)
        case .comboMilestone:
            haptics.impact(.heavy)
            synth.arpeggio([659, 784, 988], stepMs: 45, wave: .sine, gain: 0.45)
        case .newBest:
            haptics.notify(.success)
            synth.arpeggio([784, 988, 1175, 1568], stepMs: 70, wave: .sine, gain: 0.5)
        case .gameOver:
            haptics.notify(.error)
            synth.sweep(from: 330, to: 90, ms: 520, wave: .sawtooth, gain: 0.55)
        }
    }
}

// MARK: - Haptics

@MainActor
final class HapticBox {
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let note = UINotificationFeedbackGenerator()

    func prepare() {
        [light, medium, heavy, rigid, soft].forEach { $0.prepare() }
        note.prepare()
    }

    func impact(_ s: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat = 1) {
        guard GameFeel.shared.hapticsEnabled else { return }
        gen(for: s).impactOccurred(intensity: intensity)
    }

    func notify(_ t: UINotificationFeedbackGenerator.FeedbackType) {
        guard GameFeel.shared.hapticsEnabled else { return }
        note.notificationOccurred(t)
    }

    private func gen(for s: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        switch s {
        case .medium: medium
        case .heavy: heavy
        case .rigid: rigid
        case .soft: soft
        default: light
        }
    }
}

// MARK: - Tone synth (AVAudioEngine + source node, no asset files)

enum Wave: Sendable { case sine, square, triangle, sawtooth }

/// A single playing tone — value type the audio render callback advances.
/// `nonisolated` because the project defaults types to @MainActor, but this is
/// touched on the realtime audio thread.
private nonisolated struct Voice: Sendable {
    var phase: Double = 0
    let startFreq: Double
    let endFreq: Double
    let wave: Wave
    var cursor: Int = 0
    let total: Int
    let attack: Int
    let release: Int
    let gain: Double

    var isDead: Bool { cursor >= total }

    mutating func nextSample(sampleRate: Double) -> Float {
        guard cursor < total else { return 0 }
        let t = Double(cursor) / Double(total)
        let f = startFreq + (endFreq - startFreq) * t
        phase += 2 * .pi * f / sampleRate
        if phase > 2 * .pi { phase -= 2 * .pi }
        let raw: Double
        switch wave {
        case .sine: raw = sin(phase)
        case .square: raw = sin(phase) >= 0 ? 1 : -1
        case .triangle: raw = (2 / .pi) * asin(sin(phase))
        case .sawtooth: raw = 2 * (phase / (2 * .pi)) - 1
        }
        var env = 1.0
        if cursor < attack {
            env = Double(cursor) / Double(max(1, attack))
        } else if cursor > total - release {
            env = Double(total - cursor) / Double(max(1, release))
        }
        cursor += 1
        return Float(raw * env * gain)
    }
}

/// Lock-guarded pool of active voices. Safe to touch from the audio thread.
private nonisolated final class VoicePool: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [Voice]())

    func add(_ v: Voice) {
        lock.withLock { voices in
            if voices.count < 12 { voices.append(v) }
        }
    }

    func render(into abl: UnsafeMutablePointer<AudioBufferList>, frames: Int, sampleRate: Double) {
        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        lock.withLock { voices in
            for frame in 0..<frames {
                var s: Float = 0
                for i in voices.indices { s += voices[i].nextSample(sampleRate: sampleRate) }
                if s > 1 { s = 1 } else if s < -1 { s = -1 }
                for buffer in buffers {
                    if let data = buffer.mData {
                        data.assumingMemoryBound(to: Float.self)[frame] = s
                    }
                }
            }
            voices.removeAll { $0.isDead }
        }
    }
}

@MainActor
final class ToneSynth {
    private let engine = AVAudioEngine()
    private let sampleRate = 44_100.0
    private let pool = VoicePool()
    private var node: AVAudioSourceNode?
    private var started = false

    func start() {
        guard !started else { return }
        let sr = sampleRate
        let pool = self.pool
        let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        let node = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            pool.render(into: audioBufferList, frames: Int(frameCount), sampleRate: sr)
            return noErr
        }
        self.node = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        do {
            // .ambient → respects the mute switch and mixes with the user's music.
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            engine.prepare()
            try engine.start()
            started = true
        } catch {
            started = false
        }
        // Observer fires on the main queue → safe to assume main-actor isolation.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                guard self.started else { return }
                try? self.engine.start()
            }
        }
    }

    func stop() {
        guard started else { return }
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        started = false
    }

    func blip(freq: Double, wave: Wave, ms: Double, attack: Double = 0.004, release: Double = 0.05, gain: Double = 0.45) {
        addVoice(from: freq, to: freq, ms: ms, wave: wave, attack: attack, release: release, gain: gain)
    }

    func sweep(from: Double, to: Double, ms: Double, wave: Wave, gain: Double) {
        addVoice(from: from, to: to, ms: ms, wave: wave, attack: 0.004, release: 0.05, gain: gain)
    }

    func arpeggio(_ freqs: [Double], stepMs: Double, wave: Wave, gain: Double) {
        for (i, f) in freqs.enumerated() {
            let delay = Double(i) * stepMs / 1000
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.blip(freq: f, wave: wave, ms: stepMs + 40, gain: gain)
            }
        }
    }

    private func addVoice(from: Double, to: Double, ms: Double, wave: Wave, attack: Double, release: Double, gain: Double) {
        guard started else { return }
        let total = max(1, Int(ms / 1000 * sampleRate))
        let voice = Voice(
            startFreq: from, endFreq: to, wave: wave,
            total: total,
            attack: Int(attack * sampleRate),
            release: Int(release * sampleRate),
            gain: gain
        )
        pool.add(voice)
    }
}

// MARK: - Per-game reporting

extension GameConfig {
    /// Single call site a game uses for each decision.
    @MainActor
    func report(_ kind: TrialOutcome.Kind, points: Int = 0, combo: Int = 0) {
        switch kind {
        case .hit: GameFeel.shared.play(.correct(combo: combo))
        case .miss: GameFeel.shared.play(.wrong)
        case .nearMiss: GameFeel.shared.play(.nearMiss)
        case .timeout: GameFeel.shared.play(.timeout)
        }
    }
}

// MARK: - Visual juice modifiers

/// Decaying screen shake. Bump `trigger` to fire. Apply to the play area only.
struct WitsShake: ViewModifier {
    var trigger: Int
    var intensity: CGFloat = 8
    @State private var phase: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .offset(x: sin(phase * .pi * 6) * intensity * (1 - phase))
            .onChange(of: trigger) { _, _ in
                phase = 0
                withAnimation(.linear(duration: 0.32)) { phase = 1 }
            }
    }
}

/// Full-bleed colour flash that fades out. Bump `trigger` to fire.
struct WitsFlash: ViewModifier {
    var color: Color
    var trigger: Int
    @State private var opacity: Double = 0

    func body(content: Content) -> some View {
        content.overlay(
            color.opacity(opacity).ignoresSafeArea().allowsHitTesting(false)
        )
        .onChange(of: trigger) { _, _ in
            opacity = 0.32
            withAnimation(.easeOut(duration: 0.35)) { opacity = 0 }
        }
    }
}

extension View {
    func witsShake(trigger: Int, intensity: CGFloat = 8) -> some View {
        modifier(WitsShake(trigger: trigger, intensity: intensity))
    }
    func witsFlash(_ color: Color, trigger: Int) -> some View {
        modifier(WitsFlash(color: color, trigger: trigger))
    }
}

/// A cheap, asset-free particle puff (radiating dots that fade), for combo
/// milestones / new-best moments. Bump `trigger` to fire.
struct BurstView: View {
    var trigger: Int
    var color: Color = .witsAccent
    var count = 12
    @State private var fire = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<count, id: \.self) { i in
                    let angle = Double(i) / Double(count) * 2 * .pi
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                        .offset(x: fire ? cos(angle) * 70 : 0,
                                y: fire ? sin(angle) * 70 : 0)
                        .opacity(fire ? 0 : 1)
                        .animation(.easeOut(duration: 0.6), value: fire)
                }
            }
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            fire = false
            DispatchQueue.main.async {
                fire = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { fire = false }
            }
        }
    }
}
