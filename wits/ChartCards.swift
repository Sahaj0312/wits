//
//  ChartCards.swift
//  wits
//
//  Swift Charts views for the progress screen: the "your brain is improving"
//  hero line and the per-domain breakdown bars.
//

import SwiftUI
import Charts

struct HeadlineChart: View {
    let points: [SeriesPoint]

    private var yDomain: ClosedRange<Double> {
        let vs = points.map(\.value)
        let lo = max(0, (vs.min() ?? 0) - 8)
        let hi = min(100, (vs.max() ?? 100) + 8)
        return lo...(max(hi, lo + 1))
    }

    var body: some View {
        Chart(points) { p in
            AreaMark(x: .value("day", p.day), y: .value("score", p.value))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(colors: [Color.witsAccent.opacity(0.28), Color.witsAccent.opacity(0.02)],
                                   startPoint: .top, endPoint: .bottom)
                )
            LineMark(x: .value("day", p.day), y: .value("score", p.value))
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 3))
                .foregroundStyle(Color.witsAccent)
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: max(1, points.count / 4))) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(Color.witsFaint)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Color.witsLine)
                AxisValueLabel().foregroundStyle(Color.witsFaint)
            }
        }
        .frame(height: 180)
        .padding(16)
        .cardSurface()
    }
}

/// Per-domain scores as a radar/spider chart — a richer read than flat bars.
struct DomainRadarChart: View {
    let scores: [CognitiveDomain: Double]
    private let domains = CognitiveDomain.allCases   // 6 axes

    var body: some View {
        let vals = domains.map { max(0, min(1, (scores[$0] ?? 0) / 100)) }
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2 - 34
            let n = domains.count
            func pt(_ i: Int, _ frac: Double) -> CGPoint {
                let a = -Double.pi / 2 + 2 * Double.pi * Double(i) / Double(n)
                return CGPoint(x: c.x + cos(a) * r * frac, y: c.y + sin(a) * r * frac)
            }
            func ring(_ frac: Double) -> Path {
                var p = Path()
                for i in 0..<n {
                    let q = pt(i, frac)
                    if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
                }
                p.closeSubpath(); return p
            }
            // grid rings + spokes
            for f in [0.25, 0.5, 0.75, 1.0] {
                ctx.stroke(ring(f), with: .color(.witsLine), lineWidth: 1)
            }
            for i in 0..<n {
                var s = Path(); s.move(to: c); s.addLine(to: pt(i, 1))
                ctx.stroke(s, with: .color(.witsLine.opacity(0.6)), lineWidth: 1)
            }
            // data polygon
            var dp = Path()
            for i in 0..<n {
                let q = pt(i, max(0.03, vals[i]))
                if i == 0 { dp.move(to: q) } else { dp.addLine(to: q) }
            }
            dp.closeSubpath()
            ctx.fill(dp, with: .color(.witsAccent.opacity(0.22)))
            ctx.stroke(dp, with: .color(.witsAccent), lineWidth: 2)
            for i in 0..<n {
                let q = pt(i, max(0.03, vals[i]))
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - 3, y: q.y - 3, width: 6, height: 6)),
                         with: .color(.witsAccent))
            }
            // axis labels
            for i in 0..<n {
                let q = pt(i, 1.16)
                ctx.draw(Text(domains[i].label)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.witsMuted), at: q, anchor: .center)
            }
        }
        .frame(height: 250)
        .padding(16)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }
}

/// Mood + sleep trend from recent daily check-ins.
struct LifestyleCard: View {
    let checkins: [DailyCheckIn]
    private var recent: [DailyCheckIn] { Array(checkins.suffix(7)) }

    private func moodLabel(_ a: Double) -> String {
        switch a {
        case ..<1.8: "low"
        case ..<2.6: "meh"
        case ..<3.4: "okay"
        case ..<4.3: "good"
        default: "great"
        }
    }
    private func moodEmoji(_ a: Double) -> String {
        ["😣", "🙁", "😐", "🙂", "😄"][min(4, max(0, Int(a.rounded()) - 1))]
    }

    var body: some View {
        let moods = recent.map { Double($0.mood) }
        let sleeps = recent.map { $0.sleepHours }
        let moodAvg = moods.isEmpty ? 0 : moods.reduce(0, +) / Double(moods.count)
        let sleepAvg = sleeps.isEmpty ? 0 : sleeps.reduce(0, +) / Double(sleeps.count)
        VStack(alignment: .leading, spacing: 16) {
            statRow(title: "mood",
                    value: "\(moodEmoji(moodAvg))  \(moodLabel(moodAvg))",
                    bars: recent.map { Double($0.mood) / 5.0 },
                    color: .witsAccent)
            Divider().overlay(Color.witsLine)
            statRow(title: "sleep",
                    value: String(format: "~%.0f hrs", sleepAvg),
                    bars: recent.map { min(1, $0.sleepHours / 9.0) },
                    color: .witsWarm)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }

    private func statRow(title: String, value: String, bars: [Double], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.witsMuted)
                Spacer()
                Text(value)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsInk)
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, v in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color)
                        .frame(height: max(5, 34 * v))
                        .frame(maxWidth: .infinity)
                }
                ForEach(bars.count..<max(bars.count, 7), id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.witsLine)
                        .frame(height: 5)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 34, alignment: .bottom)
        }
    }
}

struct DomainBars: View {
    let scores: [CognitiveDomain: Double]

    private var rows: [(domain: CognitiveDomain, value: Double)] {
        CognitiveDomain.allCases.compactMap { d in scores[d].map { (d, $0) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(rows, id: \.domain) { row in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(row.domain.label)
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.witsInk)
                        Spacer()
                        Text("\(Int(row.value))")
                            .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.witsAccent)
                            .monospacedDigit()
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.witsLine)
                            Capsule().fill(Color.witsAccent)
                                .frame(width: max(6, geo.size.width * row.value / 100))
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }
}
