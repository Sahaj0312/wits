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

    @State private var pulse = false

    private let spacing: CGFloat = 92
    private let futurePreview = 12   // a long road ahead, like the duolingo map

    struct DayNode: Identifiable {
        enum State { case done, doneToday, today, inProgress, missed, locked }
        let id: Int
        let date: Date
        let day: Int
        let state: State
    }

    var body: some View {
        let nodes = buildNodes()
        let count = nodes.count
        let cur = currentIndex(nodes)
        GeometryReader { geo in
            let amp = min(118, geo.size.width * 0.3)
            let pos: (Int) -> CGPoint = { i in
                CGPoint(x: geo.size.width / 2 + CGFloat(sin(Double(i) * .pi / 3.2)) * amp,
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
                    node_view(node).position(pos(i))
                }
            }
            .frame(width: geo.size.width, height: CGFloat(count) * spacing)
        }
        .frame(height: CGFloat(count) * spacing)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
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

    @ViewBuilder
    private func node_view(_ node: DayNode) -> some View {
        switch node.state {
        case .today, .inProgress:
            Button(action: onStart) { liveNode(node) }.buttonStyle(.plain)
        default:
            staticNode(node)
        }
    }

    private func liveNode(_ node: DayNode) -> some View {
        let resuming = node.state == .inProgress
        return VStack(spacing: 7) {
            ZStack {
                Circle().fill(Color.witsAccent.opacity(0.25))
                    .frame(width: 100, height: 100)
                    .scaleEffect(pulse ? 1.12 : 0.92)
                    .opacity(pulse ? 0.0 : 0.7)
                Circle().fill(Color.witsAccent)
                    .frame(width: 78, height: 78)
                    .shadow(color: .witsAccent.opacity(0.5), radius: 12, y: 4)
                VStack(spacing: -2) {
                    Text("day").font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                    Text("\(node.day)").font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            Text(resuming ? "resume · \(app.today.results.count)/\(app.today.games.count)" : "start")
                .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsAccent)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Color.witsAccent.opacity(0.14), in: Capsule())
        }
    }

    private func staticNode(_ node: DayNode) -> some View {
        let st = nodeStyle(node.state)
        return ZStack {
            Circle().fill(st.fill)
                .frame(width: st.size, height: st.size)
                .overlay(Circle().strokeBorder(node.state == .locked ? Color.witsLine : .clear, lineWidth: 2))
                .shadow(color: .witsShadow, radius: 5, y: 2)
            Text("\(node.day)")
                .font(.system(size: st.size * 0.36, weight: .heavy, design: .rounded))
                .foregroundStyle(st.fg)
        }
        .overlay(alignment: .bottomTrailing) {
            if node.state == .done || node.state == .doneToday {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(Color.witsAccent)
                    .background(Circle().fill(Color.witsBg).padding(2))
                    .offset(x: 3, y: 3)
            }
        }
    }

    private func nodeStyle(_ s: DayNode.State) -> (fill: Color, fg: Color, size: CGFloat) {
        switch s {
        case .done, .doneToday: (Color.witsAccent, .white, 66)
        case .missed: (Color.witsLine, Color.witsMuted, 58)
        case .locked: (Color.witsCard, Color.witsFaint, 62)
        default: (Color.witsCard, Color.witsFaint, 62)
        }
    }

    // MARK: Data

    private func buildNodes() -> [DayNode] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let doneDates = Set(app.progressDays
            .filter { $0.workout_done == true }
            .compactMap { $0.dayDate.map { cal.startOfDay(for: $0) } })
        let start = min(doneDates.min() ?? today, today)

        var out: [DayNode] = []
        var d = start
        var n = 1
        while d <= today, n <= 400 {
            let isToday = cal.isDate(d, inSameDayAs: today)
            let done = doneDates.contains(d) || (isToday && app.isWorkoutDoneToday)
            let state: DayNode.State = isToday
                ? (done ? .doneToday : (app.today.results.isEmpty ? .today : .inProgress))
                : (done ? .done : .missed)
            out.append(DayNode(id: n, date: d, day: n, state: state))
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
