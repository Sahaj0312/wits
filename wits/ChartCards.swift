//
//  ChartCards.swift
//  wits
//
//  Swift Charts views for the progress screen: the WPI hero line and the
//  per-domain breakdown bars.
//

import SwiftUI
import Charts

/// A bare score-over-time line (no card chrome) — shown when a metric bar expands.
struct TrendLine: View {
    let points: [SeriesPoint]

    private var yDomain: ClosedRange<Double> {
        let vs = points.map(\.value)
        let lo = max(0, (vs.min() ?? 0) - 400)
        let hi = min(ProgressMath.maxScore, (vs.max() ?? ProgressMath.maxScore) + 400)
        return lo...(max(hi, lo + 1))
    }

    var body: some View {
        Chart(points) { p in
            AreaMark(x: .value("day", p.day), y: .value("score", p.value))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(colors: [Color.witsAccent.opacity(0.22), Color.witsAccent.opacity(0.01)],
                                   startPoint: .top, endPoint: .bottom)
                )
            LineMark(x: .value("day", p.day), y: .value("score", p.value))
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 3))
                .foregroundStyle(Color.witsAccent)
            PointMark(x: .value("day", p.day), y: .value("score", p.value))
                .foregroundStyle(Color.witsAccent)
                .symbolSize(points.count <= 8 ? 36 : 0)
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
        .frame(height: 180)          // firm height so the plot can't grow to fill the page
    }
}

/// A horizontal score bar that opens a full trend page when tapped.
struct MetricBar: View {
    let label: String
    let value: Double            // 0...5000 current WPI
    let series: [SeriesPoint]
    var emphasized = false       // the overall WPI bar

    var body: some View {
        NavigationLink {
            MetricDetailView(title: label, value: value, series: series)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Text(label)
                        .font(.system(size: emphasized ? 15.5 : 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.witsInk)
                    Spacer()
                    Text("\(Int(value))")
                        .font(.system(size: emphasized ? 17 : 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsAccent)
                        .monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Color.witsFaint)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.witsLine)
                        Capsule().fill(Color.witsAccent)
                            .frame(width: max(6, geo.size.width * max(0, min(1, value / ProgressMath.maxScore))))
                    }
                }
                .frame(height: emphasized ? 12 : 8)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous)
                    .strokeBorder(emphasized ? Color.witsAccent.opacity(0.5) : .clear, lineWidth: 1.5)
            )
            .cardSurface()
        }
        .buttonStyle(.plain)
    }
}

/// Full-page trend for a single metric (overall WPI or one skill).
struct MetricDetailView: View {
    let title: String
    let value: Double
    let series: [SeriesPoint]

    private var best: Double? { series.map(\.value).max() }
    private var avg: Double? {
        series.isEmpty ? nil : series.map(\.value).reduce(0, +) / Double(series.count)
    }
    private var change: Double? {
        guard let f = series.first?.value, let l = series.last?.value, series.count >= 2 else { return nil }
        return l - f
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    WitsBrandMark()
                    Text(title)
                        .font(.witsDisplay(30))
                        .foregroundStyle(Color.witsInk)
                }
                .padding(.top, 8)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(value))")
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsAccent)
                        .monospacedDigit()
                    Text("/ 5000")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.witsMuted)
                }

                Text("over time")
                    .font(.witsBody(15, weight: .bold))
                    .foregroundStyle(Color.witsMuted)
                if series.count >= 2 {
                    TrendLine(points: series)
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(Color.witsCard, in: RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous))
                        .shadow(color: .witsShadow, radius: 10, y: 6)
                } else {
                    Text("your trend will appear here as you train across more days.")
                        .font(.witsBody(15))
                        .foregroundStyle(Color.witsMuted)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSurface()
                }

                if !series.isEmpty {
                    HStack(spacing: 12) {
                        stat("\(Int(best ?? value))", "best")
                        stat("\(Int(avg ?? value))", "average")
                        stat(change.map { "\($0 >= 0 ? "+" : "")\(Int($0))" } ?? "—", "change")
                    }
                }
            }
            .padding(.horizontal, WitsMetrics.screenPadding)
            .padding(.bottom, 24)
        }
        .background(Color.witsBg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsAccent)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.witsMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .cardSurface()
    }
}

/// Per-domain scores as a radar/spider chart — a richer read than flat bars.
struct DomainRadarChart: View {
    let scores: [CognitiveDomain: Double]
    private let domains = CognitiveDomain.allCases

    var body: some View {
        let vals = domains.map { max(0, min(1, (scores[$0] ?? 0) / ProgressMath.maxScore)) }
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
