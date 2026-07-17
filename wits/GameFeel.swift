//
//  GameFeel.swift
//  wits
//
//  The "juice" layer, one place every game calls to feel alive. Restrained
//  outcome samples, haptics, and SwiftUI modifiers for screen shake, colour
//  flash, and particle bursts. Routine interactions stay haptic-only.
//

import SwiftUI
import AVFoundation
import UIKit

// MARK: - Events

enum FeelEvent {
    case correct(combo: Int)     // pitch rises with the combo
    case wrong
    case nearMiss                // "so close", feels almost, still counts as a miss
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

    private static let soundEnabledKey = "wits.soundEffectsEnabled"
    private static let hapticsEnabledKey = "wits.hapticsEnabled"

    var soundEnabled = GameFeel.storedBool(GameFeel.soundEnabledKey, defaultValue: true) {
        didSet {
            UserDefaults.standard.set(soundEnabled, forKey: Self.soundEnabledKey)
            if soundEnabled, audioClients > 0 {
                audio.start()
            } else if !soundEnabled {
                audio.stop()
            }
        }
    }
    var hapticsEnabled = GameFeel.storedBool(GameFeel.hapticsEnabledKey, defaultValue: true) {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: Self.hapticsEnabledKey) }
    }

    private let haptics = HapticBox()
    private let audio = SampleSoundBank()
    private var audioClients = 0

    private init() {}

    private static func storedBool(_ key: String, defaultValue: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil
            ? defaultValue
            : UserDefaults.standard.bool(forKey: key)
    }

    /// Prepare haptics + start the audio engine. Call when a game host appears.
    func warmUp() {
        haptics.prepare()
        audioClients += 1
        if soundEnabled { audio.start() }
    }

    /// Release the audio session once the last nested game host dismisses.
    func teardown() {
        audioClients = max(0, audioClients - 1)
        if audioClients == 0 { audio.stop() }
    }

    /// Light haptic for UI moments outside gameplay (count-ups, reveals).
    func uiTick(_ intensity: CGFloat = 0.5) {
        haptics.impact(.light, intensity: intensity)
    }

    /// Quiet feedback for navigation and secondary controls.
    func uiTap() {
        haptics.impact(.light, intensity: 0.55)
    }

    /// A crisp detent for changing a discrete option or tutorial page.
    func uiSelection() {
        haptics.select()
    }

    /// A soft landing for a successful board move with no scored outcome.
    /// Call once per committed move, never for continuous drag updates.
    func uiMove(_ intensity: CGFloat = 0.5) {
        haptics.impact(.soft, intensity: intensity)
    }

    /// Slightly firmer feedback reserved for primary actions such as Play.
    func uiPrimary() {
        haptics.impact(.medium, intensity: 0.68)
    }

    /// Prime UI feedback without starting the audio engine.
    func prepareUIHaptics() {
        haptics.prepare()
    }

    /// Success haptic for UI celebrations that already have an outcome cue.
    func uiSuccess() {
        haptics.notify(.success)
    }

    func play(_ e: FeelEvent) {
        switch e {
        case .correct(let combo):
            haptics.impact(.light, intensity: 0.7)
            // Routine correct actions stay haptic-only. A sound is reserved
            // for a few memorable streak thresholds, keeping play quiet.
            guard soundEnabled, [3, 6, 10].contains(combo) else { return }
            // Keep the variation narrow so later streaks do not become shrill.
            let rates: [Float] = [0.96, 0.99, 1.02, 1.05, 1.09, 1.12]
            audio.play(["correct_1", "correct_2"],
                       volume: 0.11,
                       rate: rates[min(max(combo, 0), rates.count - 1)],
                       cooldown: 0.12)
        case .wrong:
            haptics.notify(.error)
        case .nearMiss:
            haptics.impact(.soft, intensity: 0.6)
        case .timeout:
            haptics.impact(.rigid)
        case .lifeLost(let remaining):
            haptics.notify(remaining <= 0 ? .error : .warning)
            if soundEnabled { audio.play(["life_lost"], volume: 0.12, cooldown: 0.40) }
        case .levelUp:
            haptics.impact(.medium)
            if soundEnabled { audio.play(["level_up"], volume: 0.14, cooldown: 0.50) }
        case .comboMilestone:
            haptics.impact(.heavy)
            if soundEnabled { audio.play(["combo"], volume: 0.14, cooldown: 0.35) }
        case .newBest:
            haptics.notify(.success)
            if soundEnabled { audio.play(["new_best"], volume: 0.16, cooldown: 0.50) }
        case .gameOver:
            haptics.notify(.error)
            if soundEnabled { audio.play(["game_over"], volume: 0.13, cooldown: 0.50) }
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
    private let selection = UISelectionFeedbackGenerator()
    private let note = UINotificationFeedbackGenerator()

    func prepare() {
        [light, medium, heavy, rigid, soft].forEach { $0.prepare() }
        selection.prepare()
        note.prepare()
    }

    func impact(_ s: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat = 1) {
        guard GameFeel.shared.hapticsEnabled else { return }
        let generator = gen(for: s)
        generator.impactOccurred(intensity: intensity)
        generator.prepare()
    }

    func notify(_ t: UINotificationFeedbackGenerator.FeedbackType) {
        guard GameFeel.shared.hapticsEnabled else { return }
        note.notificationOccurred(t)
        note.prepare()
    }

    func select() {
        guard GameFeel.shared.hapticsEnabled else { return }
        selection.selectionChanged()
        selection.prepare()
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

// MARK: - Preloaded one-shot player

@MainActor
private final class SampleSoundBank {
    private static let sampleNames = [
        "correct_1", "correct_2", "life_lost", "level_up", "combo",
        "new_best", "game_over"
    ]

    private var players: [String: [AVAudioPlayer]] = [:]
    private var nextPlayer: [String: Int] = [:]
    private var lastVariant: [String: String] = [:]
    private var lastPlayedAt: [String: TimeInterval] = [:]
    private var loaded = false
    private var started = false

    func start() {
        guard !started else { return }
        loadIfNeeded()
        do {
            // .ambient → respects the mute switch and mixes with the user's music.
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            started = true
        } catch {
            started = false
        }
    }

    func stop() {
        guard started else { return }
        players.values.flatMap { $0 }.forEach { $0.stop() }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        started = false
    }

    func play(_ names: [String],
              volume: Float,
              rate: Float = 1,
              cooldown: TimeInterval = 0) {
        if !started { start() }
        guard started, !names.isEmpty else { return }

        let cueKey = names.joined(separator: "|")
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastPlayedAt[cueKey], now - last < cooldown { return }
        lastPlayedAt[cueKey] = now

        // Outcome cues share one voice. A stronger event replaces a weaker
        // one instead of stacking multiple transients on the same action.
        players.values.flatMap { $0 }.filter(\.isPlaying).forEach { $0.stop() }

        var candidates = names.filter { players[$0] != nil }
        guard !candidates.isEmpty else { return }
        if candidates.count > 1, let previous = lastVariant[cueKey] {
            candidates.removeAll { $0 == previous }
        }
        let name = candidates.randomElement() ?? names[0]
        lastVariant[cueKey] = name

        guard let pool = players[name], !pool.isEmpty else { return }
        let index = nextPlayer[name, default: 0] % pool.count
        nextPlayer[name] = index + 1
        let player = pool[index]
        player.stop()
        player.currentTime = 0
        player.volume = volume
        player.enableRate = true
        player.rate = min(2, max(0.5, rate))
        player.play()
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        for name in Self.sampleNames {
            guard let url = Bundle.main.url(forResource: name,
                                            withExtension: "wav",
                                            subdirectory: "Audio/SFX")
                    ?? Bundle.main.url(forResource: name, withExtension: "wav") else {
                continue
            }
            let pool = (0..<2).compactMap { _ -> AVAudioPlayer? in
                guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
                player.prepareToPlay()
                return player
            }
            if !pool.isEmpty { players[name] = pool }
        }
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
