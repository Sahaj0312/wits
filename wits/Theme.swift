//
//  Theme.swift
//  wits
//
//  Design tokens + shared components from the "wits onboarding v4" design.
//

import SwiftUI
import UIKit

// MARK: - Palette

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }

    static let witsBg = Color(light: 0xF3F5F9, dark: 0x131A2C)
    static let witsCard = Color(light: 0xFFFFFF, dark: 0x1D2541)
    static let witsInk = Color(light: 0x1C2740, dark: 0xEDF0F8)
    static let witsMuted = Color(light: 0x1C2740, dark: 0xEDF0F8, lightAlpha: 0.62, darkAlpha: 0.65)
    static let witsFaint = Color(light: 0x1C2740, dark: 0xEDF0F8, lightAlpha: 0.40, darkAlpha: 0.42)
    static let witsLine = Color(light: 0x1C2740, dark: 0xEDF0F8, lightAlpha: 0.10, darkAlpha: 0.13)
    static let witsTint = Color(light: 0x1C2740, dark: 0xEDF0F8, lightAlpha: 0.045, darkAlpha: 0.06)
    static let witsShadow = Color(light: 0x1C2740, dark: 0x000000, lightAlpha: 0.07, darkAlpha: 0.22)
    static let witsAccent = Color(light: 0x17B3A3, dark: 0x1BC7B5)
    static let witsWarm = Color(light: 0xF0795F, dark: 0xFF8A70)

    // Extended palette — every non-domain tint in the app comes from here,
    // never from ad-hoc hex values inside views.
    static let witsSky = Color(light: 0x0E9BD8, dark: 0x38C4F2)
    static let witsViolet = Color(light: 0x7C5CF0, dark: 0xA78BFA)
    static let witsPink = Color(light: 0xE0489A, dark: 0xF472B6)
    static let witsGold = Color(light: 0xE8930C, dark: 0xFFB03B)
    static let witsMustard = Color(light: 0xC9B458, dark: 0xB59F3B)
}

// MARK: - Domain colors
//
// Each cognitive domain owns a color; teal stays reserved for brand + CTAs.
// Applied to library cards, workout rows, heroes, charts, and chips so the
// domain a game trains is legible at a glance everywhere in the app.

extension CognitiveDomain {
    var color: Color {
        switch self {
        case .focus: .witsGold
        case .multitasking: .witsSky
        case .memory: .witsViolet
        case .flexibility: .witsPink
        case .reasoning: Color(light: 0x3D6DE8, dark: 0x6E96FA)
        case .math: .witsWarm
        case .language: Color(light: 0x2FA45C, dark: 0x53CF82)
        }
    }

    /// Deep variant used as the dark end of hero gradients (same hue family,
    /// pulled toward the app's navy so heroes feel like one system).
    var deepColor: Color {
        switch self {
        case .focus: Color(hexAny: 0x4A3208)
        case .multitasking: Color(hexAny: 0x0A3A52)
        case .memory: Color(hexAny: 0x2C2058)
        case .flexibility: Color(hexAny: 0x4A1638)
        case .reasoning: Color(hexAny: 0x16295E)
        case .math: Color(hexAny: 0x4E2016)
        case .language: Color(hexAny: 0x0F3A22)
        }
    }

    /// Mid variant for the top of hero gradients.
    var heroTopColor: Color {
        switch self {
        case .focus: Color(hexAny: 0x8A5E10)
        case .multitasking: Color(hexAny: 0x0E5E80)
        case .memory: Color(hexAny: 0x4A3894)
        case .flexibility: Color(hexAny: 0x7E2760)
        case .reasoning: Color(hexAny: 0x2547A0)
        case .math: Color(hexAny: 0x8A3A28)
        case .language: Color(hexAny: 0x1B6238)
        }
    }
}

extension Color {
    /// Fixed (non-adaptive) color from hex — used where art must read the same
    /// in light and dark mode, e.g. hero gradients.
    init(hexAny: UInt32) {
        self.init(
            red: Double((hexAny >> 16) & 0xFF) / 255,
            green: Double((hexAny >> 8) & 0xFF) / 255,
            blue: Double(hexAny & 0xFF) / 255
        )
    }
}

// MARK: - Type

extension Font {
    /// Heavy display type — reserved for screen titles and hero headlines only.
    static func witsDisplay(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }
    /// Section headings and emphasized rows.
    static func witsHeading(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
    /// Stat values, badges, buttons — semibold, not heavy.
    static func witsValue(_ size: CGFloat = 16) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
    /// Small caps-style labels above values.
    static func witsLabel(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
    static func witsBody(_ size: CGFloat = 16, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

enum WitsMetrics {
    /// Radius scale: chip 12, card 16, panel 20, hero 28. Nothing else.
    static let chipRadius: CGFloat = 12
    static let radius: CGFloat = 16
    static let panelRadius: CGFloat = 20
    static let heroRadius: CGFloat = 28
    static let screenPadding: CGFloat = 24
}

// MARK: - Rise-in animation (ck-rise)

private struct RiseIn: ViewModifier {
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 16)
            .onAppear {
                withAnimation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.46).delay(delay)) {
                    shown = true
                }
            }
    }
}

extension View {
    /// Staggered entrance used across every screen in the design.
    func rise(_ delay: Double = 0) -> some View {
        modifier(RiseIn(delay: delay))
    }

    /// Three-tier elevation so shadows carry meaning: `.flat` for quiet inline
    /// blocks, `.raised` for standard cards, `.hero` for the one primary card
    /// on a screen.
    func cardSurface(radius: CGFloat = WitsMetrics.radius,
                     elevation: WitsElevation = .raised) -> some View {
        modifier(CardSurface(radius: radius, elevation: elevation))
    }
}

enum WitsElevation { case flat, raised, hero }

private struct CardSurface: ViewModifier {
    let radius: CGFloat
    let elevation: WitsElevation

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch elevation {
        case .flat:
            content
                .background(Color.witsTint, in: shape)
        case .raised:
            content
                .background(Color.witsCard, in: shape)
                .overlay(shape.strokeBorder(Color.witsLine, lineWidth: 1))
                .shadow(color: .witsShadow, radius: 8, y: 4)
        case .hero:
            content
                .background(Color.witsCard, in: shape)
                .overlay(shape.strokeBorder(Color.witsLine, lineWidth: 1))
                .shadow(color: .witsShadow, radius: 18, y: 10)
        }
    }
}

// MARK: - Logo mark

struct LogoBlob: View {
    var size: CGFloat
    var breathe = false
    @State private var animating = false

    var body: some View {
        Image("WitsMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .rotationEffect(.degrees(breathe && animating ? 4 : breathe ? -4 : 0))
            .scaleEffect(breathe && animating ? 1.04 : 1)
            .onAppear {
                guard breathe else { return }
                withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) {
                    animating = true
                }
            }
    }
}

struct Wordmark: View {
    var body: some View {
        Text("wits")
            .font(.system(size: 21, weight: .heavy, design: .rounded))
            .foregroundStyle(Color.witsInk)
    }
}

/// Small accent "wits" brandmark — sits above each page's title so the brand is
/// present on every screen.
struct WitsBrandMark: View {
    var body: some View {
        Text("wits")
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .foregroundStyle(Color.witsAccent)
            .kerning(0.5)
    }
}

// MARK: - CTA

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

enum TactileFeedback {
    case tap
    case selection
    case primary

    @MainActor
    fileprivate func play() {
        switch self {
        case .tap: GameFeel.shared.uiTap()
        case .selection: GameFeel.shared.uiSelection()
        case .primary: GameFeel.shared.uiPrimary()
        }
    }
}

/// Opt-in tactile button treatment for meaningful UI controls. Keeping this
/// separate from `PressScale` prevents every routine gameplay tap from buzzing.
struct TactilePressScale: ButtonStyle {
    var feedback: TactileFeedback = .tap

    func makeBody(configuration: Configuration) -> some View {
        TactilePressScaleBody(configuration: configuration, feedback: feedback)
    }
}

private struct TactilePressScaleBody: View {
    let configuration: ButtonStyle.Configuration
    let feedback: TactileFeedback

    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.6),
                       value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed { feedback.play() }
            }
    }
}

struct Cta: View {
    var title: String
    var dimmed = false
    var tint: Color = .witsAccent
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    LinearGradient(colors: [tint.opacity(0.92), tint],
                                   startPoint: .top, endPoint: .bottom),
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(TactilePressScale(feedback: .primary))
        .shadow(color: tint.opacity(dimmed ? 0 : 0.35), radius: 9, y: 6)
        .opacity(dimmed ? 0.4 : 1)
        .animation(.easeOut(duration: 0.2), value: dimmed)
    }
}

struct QuietButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.witsFaint)
                .padding(.vertical, 6)
        }
    }
}

// MARK: - Progress bar

struct ProgressTrack: View {
    var fraction: Double
    var animated = true
    var tint: Color = .witsAccent
    var track: Color = .witsLine

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, geo.size.width * fraction))
            }
        }
        .frame(height: 6)
        .animation(animated ? .timingCurve(0.2, 0.8, 0.3, 1, duration: 0.28) : nil, value: fraction)
    }
}

// MARK: - Answer row (quiz options)

struct AnswerRow: View {
    var label: String
    var sub: String? = nil
    var picked: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.witsInk)
                        .multilineTextAlignment(.leading)
                    if let sub {
                        Text(sub)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.witsMuted)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle()
                        .fill(picked ? Color.witsAccent : Color.witsTint)
                        .frame(width: 22, height: 22)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(picked ? .white : .clear)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 17)
            .frame(minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous)
                    .fill(Color.witsCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous)
                    .strokeBorder(picked ? Color.witsAccent : .clear, lineWidth: 1.5)
            )
            .shadow(color: .witsShadow, radius: 10, y: 6)
        }
        .buttonStyle(TactilePressScale(feedback: .selection))
        .animation(.easeOut(duration: 0.12), value: picked)
    }
}

// MARK: - Plan item (numbered step card)

struct PlanItem: View {
    var number: Int
    var title: String
    var sub: String

    var body: some View {
        HStack(spacing: 14) {
            Text("\(number)")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsAccent)
                .frame(width: 38, height: 38)
                .background(Color.witsAccent.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.witsInk)
                Text(sub)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.witsMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

// MARK: - Flow layout (goal chips)

struct FlowLayout: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.map { $0.height }.reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var height: CGFloat = 0
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var current = Row()
        var x: CGFloat = 0
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
                x = 0
            }
            current.indices.append(i)
            current.height = max(current.height, size.height)
            x += size.width + spacing
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
