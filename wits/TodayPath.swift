//
//  TodayPath.swift
//  wits
//
//  The Today screen as a Duolingo-style journey: a vertical winding path of
//  day-nodes from day one onward. Completed days are filled, today is the live
//  node you tap to train, and upcoming days sit locked below.
//

import SwiftUI

struct WorkoutPathView: View {
    @Environment(AppModel.self) private var app
    /// Tapped the live (today) node — start / resume the workout.
    var onStart: () -> Void
    static let liveScrollID = "workout-path-live-node"

    @State private var pulse = false
    @State private var selected: DayNode?

    private let spacing: CGFloat = 92
    private let futurePreview = 12   // a long road ahead, like the duolingo map

    struct DayNode: Identifiable {
        enum State { case done, doneToday, today, inProgress, partial, missed, locked }
        let id: Int
        let date: Date
        let day: Int
        let state: State
        /// For `.partial`: fraction of the prescribed workout completed (0…1).
        var progress: Double = 0
    }

    var body: some View {
        let nodes = buildNodes()
        let count = nodes.count
        let cur = currentIndex(nodes)
        GeometryReader { geo in
            let amp = min(70, geo.size.width * 0.18)
            let pos: (Int) -> CGPoint = { i in
                CGPoint(x: geo.size.width / 2 + CGFloat(sin(Double(i) * 2 * .pi / 5)) * amp,
                        y: CGFloat(i) * spacing + spacing / 2)
            }
            let pts = nodes.indices.map { pos($0) }
            ZStack(alignment: .topLeading) {
                // full road (upcoming = muted)
                Self.smoothPath(pts)
                    .stroke(Color.witsLine, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                // travelled road up to where you are now (accent)
                if cur >= 1 {
                    Self.smoothPath(Array(pts[0...cur]))
                        .stroke(Color.witsAccent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                }
                ForEach(Array(nodes.enumerated()), id: \.element.id) { i, node in
                    node_view(node)
                        .position(pos(i))
                        // Live node carries a "start"/"resume" pill below it that
                        // reaches into the next node's space — keep it on top so a
                        // later-drawn neighbour can never occlude it.
                        .zIndex(node.state == .today || node.state == .inProgress ? 1 : 0)
                }
                // Scroll anchor for the live node. We can't reuse `.position`
                // here: that modifier expands its view to fill the whole ZStack,
                // so `scrollTo(anchor: .center)` would center the road's midpoint
                // instead of today. A top-stacked spacer gives the 1×1 marker a
                // real layout frame at the node's y, so centering lands on today
                // — and clamps to no-scroll when today sits above screen-center.
                VStack(spacing: 0) {
                    Color.clear.frame(width: 1, height: pos(cur).y)
                    Color.clear.frame(width: 1, height: 1).id(Self.liveScrollID)
                    Spacer(minLength: 0)
                }
                .frame(height: CGFloat(count) * spacing, alignment: .top)
                .allowsHitTesting(false)
            }
            .frame(width: geo.size.width, height: CGFloat(count) * spacing)
        }
        .frame(height: CGFloat(count) * spacing)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
        .sheet(item: $selected) { node in
            DayDetailSheet(node: node, start: {
                selected = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onStart() }
            })
        }
    }

    /// Index of the live (today) node — the accent road runs up to here.
    private func currentIndex(_ nodes: [DayNode]) -> Int {
        nodes.firstIndex { $0.state == .today || $0.state == .inProgress || $0.state == .doneToday }
            ?? max(0, (nodes.firstIndex { $0.state == .locked } ?? nodes.count) - 1)
    }

    /// Smooth Catmull-Rom curve through the node centers for a flowing path.
    private static func smoothPath(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        guard pts.count > 1 else { return path }
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(0, i - 1)]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = pts[min(pts.count - 1, i + 2)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }

    // MARK: Node

    private func node_view(_ node: DayNode) -> some View {
        Button { selected = node } label: { nodeBody(node) }
            .buttonStyle(.plain)
    }

    @ViewBuilder
    private func nodeBody(_ node: DayNode) -> some View {
        if node.state == .today || node.state == .inProgress { liveNode(node) }
        else { staticNode(node) }
    }

    private func liveNode(_ node: DayNode) -> some View {
        // Circle only is centered at the node point; the caption floats below as an
        // overlay so it doesn't shift the circle up into the previous node.
        ZStack {
            Circle().fill(Color.witsAccent.opacity(0.25))
                .frame(width: 90, height: 90)
                .scaleEffect(pulse ? 1.12 : 0.92)
                .opacity(pulse ? 0.0 : 0.7)
            Circle().fill(Color.witsCard)
                .frame(width: 74, height: 74)
                .overlay(Circle().strokeBorder(Color.witsAccent, lineWidth: 4))
                .shadow(color: .witsAccent.opacity(0.4), radius: 12, y: 4)
            dayLabel(node.day, number: 24, fg: .witsAccent)
        }
        .frame(width: 90, height: 90)
        .overlay(alignment: .bottom) {
            Text(node.state == .inProgress ? "resume · \(app.today.results.count)/\(app.today.games.count)" : "start")
                .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsAccent)
                .padding(.horizontal, 12).padding(.vertical, 5)
                // Solid backing first, accent tint over it: the pill stays legible
                // even where it floats over the path or a neighbouring node.
                .background(Color.witsAccent.opacity(0.18), in: Capsule())
                .background(Color.witsBg, in: Capsule())
                .fixedSize()
                .offset(y: 28)
        }
    }

    private func staticNode(_ node: DayNode) -> some View {
        let st = nodeStyle(node.state)
        return ZStack {
            Circle().fill(Color.witsBg)
                .frame(width: st.size + 10, height: st.size + 10)
            Circle().fill(st.fill)
                .frame(width: st.size, height: st.size)
                .overlay(Circle().strokeBorder(node.state == .locked ? Color.witsLine : .clear, lineWidth: 2))
                .shadow(color: st.glow ? .witsAccent.opacity(0.45) : .witsShadow, radius: st.glow ? 10 : 5, y: 3)
            // Partial days: an accent arc showing how much of the workout was done.
            if node.state == .partial {
                Circle()
                    .trim(from: 0, to: max(0.04, min(1, node.progress)))
                    .stroke(Color.witsAccent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: st.size, height: st.size)
            }
            dayLabel(node.day, number: 19, fg: st.fg)
        }
    }

    private func dayLabel(_ n: Int, number: CGFloat, fg: Color) -> some View {
        VStack(spacing: -2) {
            Text("day")
                .font(.system(size: number * 0.5, weight: .bold, design: .rounded))
                .foregroundStyle(fg.opacity(0.8))
            Text("\(n)")
                .font(.system(size: number, weight: .heavy, design: .rounded))
                .foregroundStyle(fg)
        }
    }

    private func nodeStyle(_ s: DayNode.State) -> (fill: Color, fg: Color, size: CGFloat, glow: Bool) {
        switch s {
        case .done, .doneToday: (Color.witsAccent, .white, 66, true)   // completed = highlighted
        case .partial: (Color.witsCard, Color.witsMuted, 62, false)    // started, not finished
        case .missed: (Color.witsLine, Color.witsMuted, 58, false)
        case .locked: (Color.witsCard, Color.witsFaint, 62, false)
        default: (Color.witsCard, Color.witsFaint, 62, false)
        }
    }

    // MARK: Data

    private func buildNodes() -> [DayNode] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Anchor the journey at the user's earliest recorded active day.
        let activeDates = app.progressDays
            .compactMap { $0.dayDate.map { cal.startOfDay(for: $0) } }
        let start = min(activeDates.min() ?? today, today)

        var out: [DayNode] = []
        var d = start
        var n = 1
        while d <= today, n <= 400 {
            let isToday = cal.isDate(d, inSameDayAs: today)
            var node: DayNode
            if isToday {
                let state: DayNode.State = app.isWorkoutDoneToday ? .doneToday
                    : (app.today.results.isEmpty ? .today : .inProgress)
                node = DayNode(id: n, date: d, day: n, state: state)
            } else {
                // Completion is measured from games actually played vs. the
                // prescribed lineup — a partly-done workout is never "completed".
                switch app.workoutStatus(on: d) {
                case .completed: node = DayNode(id: n, date: d, day: n, state: .done)
                case .partial:
                    let total = max(1, app.progressDays.first { $0.day == SupabaseManager.dayString(d) }?.workout_games?.count ?? WorkoutBuilder.size)
                    let frac = Double(app.playedGames(on: d).count) / Double(total)
                    node = DayNode(id: n, date: d, day: n, state: .partial, progress: frac)
                case .none: node = DayNode(id: n, date: d, day: n, state: .missed)
                }
            }
            out.append(node)
            d = cal.date(byAdding: .day, value: 1, to: d) ?? today.addingTimeInterval(90_000)
            n += 1
        }
        for f in 1...futurePreview {
            if let fd = cal.date(byAdding: .day, value: f, to: today) {
                out.append(DayNode(id: n, date: fd, day: n, state: .locked)); n += 1
            }
        }
        return out
    }
}

// MARK: - Day detail modal

/// Tapping a node opens this: the day's workout — results if completed, the games
/// to play (with a start/resume button) if it's today, or a locked preview.
struct DayDetailSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let node: WorkoutPathView.DayNode
    var start: () -> Void

    /// One game in the day's lineup, plus the level it ran at (for completed
    /// runs) so the recap shows progression.
    private struct LineupRow: Identifiable {
        let id = UUID()
        let game: GameID
        let level: Double?
        let done: Bool
    }

    private var rows: [LineupRow] {
        switch node.state {
        case .today, .inProgress, .doneToday:
            // Today's weakness-tuned lineup lives on the model; mark the games
            // already played and tag each with the level it ran at.
            let results = app.today.results
            return app.today.games.map { g in
                let r = results.first { $0.game == g }
                return LineupRow(game: g, level: r?.newDifficulty?.level, done: r != nil)
            }
        case .done, .partial, .missed:
            // Past day → show the full prescribed lineup, marking which games were
            // actually played (with the level) and leaving the rest unchecked.
            let played = app.playedGames(on: node.date)
            let byGame = Dictionary(played.map { ($0.game, $0) }, uniquingKeysWith: { a, _ in a })
            let prescribed = dayProgress?.workout_games?.compactMap { GameID(rawValue: $0) } ?? []
            if !prescribed.isEmpty {
                return prescribed.map { g in
                    let p = byGame[g]
                    return LineupRow(game: g, level: p?.level, done: p != nil)
                }
            }
            // Legacy days with no persisted lineup: show what we have (the games
            // played), else a best-effort preview.
            if !played.isEmpty {
                return played.map { LineupRow(game: $0.game, level: $0.level, done: true) }
            }
            return WorkoutBuilder.build(for: node.date).games.map {
                LineupRow(game: $0, level: nil, done: false)
            }
        case .locked:
            // Future day — a preview of what's coming up (weak spots unknown yet).
            return WorkoutBuilder.build(for: node.date).games.map {
                LineupRow(game: $0, level: nil, done: false)
            }
        }
    }
    private var dayProgress: DailyProgressRow? {
        app.progressDays.first { $0.day == SupabaseManager.dayString(node.date) }
    }
    private var statusText: String {
        switch node.state {
        case .done: "completed"
        case .doneToday: "completed today"
        case .today: "ready to train"
        case .inProgress: "in progress"
        case .partial: "incomplete · \(app.playedGames(on: node.date).count)/\(dayProgress?.workout_games?.count ?? WorkoutBuilder.size) done"
        case .locked: "locked"
        case .missed: "missed"
        }
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"; return f
    }()

    /// Exact content height so the sheet fits everything with no scroll / no gap.
    private var sheetHeight: CGFloat {
        var h: CGFloat = 22 + 62          // top pad + title block (title + status)
        h += 16 + 20                      // "the workout" label
        h += 16 + CGFloat(rows.count) * 64 + CGFloat(max(0, rows.count - 1)) * 10
        switch node.state {
        case .today, .inProgress: h += 16 + 52   // action button
        case .locked: h += 16 + 20               // unlock note
        default: break
        }
        return h + 24 + 28                // bottom pad + drag indicator/inset
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("day \(node.day)")
                        .font(.witsDisplay(28))
                        .foregroundStyle(Color.witsInk)
                    HStack(spacing: 8) {
                        Text(statusText)
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(node.state == .locked || node.state == .missed ? Color.witsMuted : Color.witsAccent)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background((node.state == .locked || node.state == .missed ? Color.witsMuted : Color.witsAccent).opacity(0.14), in: Capsule())
                        Text(Self.dateFmt.string(from: node.date))
                            .font(.witsBody(13))
                            .foregroundStyle(Color.witsFaint)
                    }
                }
                .padding(.top, 22)

                Text(node.state == .locked ? "what's coming up" : "the workout")
                    .font(.witsBody(14, weight: .bold))
                    .foregroundStyle(Color.witsMuted)
                    .padding(.top, 2)

                VStack(spacing: 10) {
                    ForEach(rows) { row in
                        gameRow(row.game, level: row.level, done: row.done, locked: node.state == .locked)
                    }
                }

                actionView
                    .padding(.top, 4)
            }
            .padding(.horizontal, WitsMetrics.screenPadding)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.witsBg.ignoresSafeArea())
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var actionView: some View {
        switch node.state {
        case .today:
            Cta(title: "start workout", action: start)
        case .inProgress:
            Cta(title: "resume workout", action: start)
        case .locked:
            Text("unlocks on \(Self.dateFmt.string(from: node.date))")
                .font(.witsBody(13))
                .foregroundStyle(Color.witsFaint)
                .frame(maxWidth: .infinity)
        default:
            EmptyView()
        }
    }

    private func gameRow(_ g: GameID, level: Double?, done: Bool, locked: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: g.symbol)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(locked ? Color.witsFaint : Color.witsAccent)
                .frame(width: 40, height: 40)
                .background((locked ? Color.witsFaint : Color.witsAccent).opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(g.displayName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.witsInk)
                Text(g.domain.label)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.witsMuted)
            }
            Spacer(minLength: 0)
            if let level {
                Text(String(format: "lvl %.1f", level))
                    .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsAccent)
                    .monospacedDigit()
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.witsAccent.opacity(0.14), in: Capsule())
            }
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(Color.witsAccent)
            } else if locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color.witsFaint)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .opacity(locked ? 0.7 : 1)
    }
}
