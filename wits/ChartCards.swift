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
    var tint: Color = .witsAccent

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
                    LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.01)],
                                   startPoint: .top, endPoint: .bottom)
                )
            LineMark(x: .value("day", p.day), y: .value("score", p.value))
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 3))
                .foregroundStyle(tint)
            PointMark(x: .value("day", p.day), y: .value("score", p.value))
                .foregroundStyle(tint)
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

extension StatNorm {
    /// "top 38%" only means what it sounds like above the median — below it,
    /// "top 90%" reads as praise it isn't, so fall back to the plain percentile.
    var headlineLabel: String {
        pct >= 50 ? "top \(100 - pct)%" : "\(Self.ordinal(pct)) percentile"
    }
    /// Compact framing for the score-bar chip: unambiguous at any percentile.
    var chipLabel: String { "beats \(pct)%" }

    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 100, n % 10) {
        case (11...13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }
}

/// A horizontal score bar that opens a full trend page when tapped.
struct MetricBar: View {
    let label: String
    let value: Double            // 0...5000 current WPI
    let series: [SeriesPoint]
    var emphasized = false       // the overall WPI bar
    var tint: Color = .witsAccent
    var norm: StatNorm? = nil    // population comparison, when the server has it

    var body: some View {
        NavigationLink {
            MetricDetailView(title: label, value: value, series: series, tint: tint, norm: norm)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    if !emphasized {
                        Circle()
                            .fill(tint)
                            .frame(width: 8, height: 8)
                    }
                    Text(label)
                        .font(.system(size: emphasized ? 15.5 : 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.witsInk)
                    if let norm {
                        Text(norm.chipLabel)
                            .font(.witsLabel(11))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(tint.opacity(0.12), in: Capsule())
                    }
                    Spacer()
                    Text("\(Int(value))")
                        .font(.witsValue(emphasized ? 17 : 15))
                        .foregroundStyle(tint)
                        .monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Color.witsFaint)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.witsLine)
                        Capsule()
                            .fill(
                                LinearGradient(colors: [tint.opacity(0.75), tint],
                                               startPoint: .leading, endPoint: .trailing)
                            )
                            .frame(width: max(6, geo.size.width * max(0, min(1, value / ProgressMath.maxScore))))
                    }
                }
                .frame(height: emphasized ? 12 : 8)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous)
                    .strokeBorder(emphasized ? tint.opacity(0.5) : .clear, lineWidth: 1.5)
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
    var tint: Color = .witsAccent
    var norm: StatNorm? = nil

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
                        .foregroundStyle(tint)
                        .monospacedDigit()
                    Text("/ 5000")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.witsMuted)
                }

                if let norm {
                    Text("vs other users")
                        .font(.witsBody(15, weight: .bold))
                        .foregroundStyle(Color.witsMuted)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(norm.headlineLabel)
                                .font(.system(size: 22, weight: .heavy, design: .rounded))
                                .foregroundStyle(tint)
                            Text("higher than \(norm.pct)% of all users")
                                .font(.witsBody(13.5))
                                .foregroundStyle(Color.witsMuted)
                        }
                        if let mean = norm.mean, let sd = norm.sd, sd > 0 {
                            BellCurveChart(value: value, mean: mean, sd: sd, tint: tint)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface()
                }

                Text("over time")
                    .font(.witsBody(15, weight: .bold))
                    .foregroundStyle(Color.witsMuted)
                if series.count >= 2 {
                    TrendLine(points: series, tint: tint)
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
                .font(.witsValue(22))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(.witsLabel(12))
                .foregroundStyle(Color.witsMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .cardSurface()
    }
}

/// Population distribution for one skill score: a normal curve from the server
/// norms (mean/sd across all users) with the user's own score marked on it.
/// The area left of the marker — the share of users they beat — is shaded.
/// Drawn with Canvas (like the radar chart) so the fill hugs the curve exactly.
struct BellCurveChart: View {
    let value: Double            // the user's score, 0...5000
    let mean: Double             // population mean
    let sd: Double               // population standard deviation
    var tint: Color = .witsAccent

    var body: some View {
        Canvas { ctx, size in
            let lo = max(0, mean - 3.2 * sd)
            let hi = min(ProgressMath.maxScore, mean + 3.2 * sd)
            guard hi > lo, sd > 0 else { return }
            let topPad: CGFloat = 34         // room for the "you" pill
            let bottomPad: CGFloat = 20      // room for the avg label
            let baseline = size.height - bottomPad
            let plotH = baseline - topPad

            func xPos(_ v: Double) -> CGFloat { CGFloat((v - lo) / (hi - lo)) * size.width }
            func pdf(_ v: Double) -> CGFloat {
                let z = (v - mean) / sd
                return CGFloat(exp(-0.5 * z * z))     // normalized: peak = 1
            }
            func point(_ v: Double) -> CGPoint { CGPoint(x: xPos(v), y: baseline - pdf(v) * plotH) }

            let steps = 96
            let xs = (0...steps).map { lo + (hi - lo) * Double($0) / Double(steps) }
            let marker = min(hi, max(lo, value))

            // area under the curve up to `limit` (nil = the whole population)
            func area(upTo limit: Double?) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: xPos(xs[0]), y: baseline))
                for v in xs where limit.map({ v <= $0 }) ?? true {
                    p.addLine(to: point(v))
                }
                if let limit { p.addLine(to: point(limit)) }
                p.addLine(to: CGPoint(x: xPos(limit ?? xs[xs.count - 1]), y: baseline))
                p.closeSubpath()
                return p
            }

            ctx.fill(area(upTo: nil), with: .color(tint.opacity(0.10)))
            ctx.fill(area(upTo: marker), with: .linearGradient(
                Gradient(colors: [tint.opacity(0.45), tint.opacity(0.10)]),
                startPoint: CGPoint(x: 0, y: topPad),
                endPoint: CGPoint(x: 0, y: baseline)
            ))

            var curve = Path()
            curve.move(to: point(xs[0]))
            for v in xs.dropFirst() { curve.addLine(to: point(v)) }
            ctx.stroke(curve, with: .color(tint.opacity(0.85)), lineWidth: 2.5)

            var base = Path()
            base.move(to: CGPoint(x: 0, y: baseline))
            base.addLine(to: CGPoint(x: size.width, y: baseline))
            ctx.stroke(base, with: .color(.witsLine), lineWidth: 1)

            // population average: faint drop line + label under the baseline
            var avgLine = Path()
            avgLine.move(to: point(mean))
            avgLine.addLine(to: CGPoint(x: xPos(mean), y: baseline))
            ctx.stroke(avgLine, with: .color(.witsLine), lineWidth: 1)
            ctx.draw(Text("avg \(Int(mean))")
                .font(.witsLabel(11))
                .foregroundStyle(Color.witsFaint),
                at: CGPoint(x: min(size.width - 30, max(30, xPos(mean))), y: baseline + 10),
                anchor: .center)

            // the user's marker: dashed rule + "you" pill above it
            let mx = xPos(marker)
            var rule = Path()
            rule.move(to: CGPoint(x: mx, y: topPad - 4))
            rule.addLine(to: CGPoint(x: mx, y: baseline))
            ctx.stroke(rule, with: .color(tint),
                       style: StrokeStyle(lineWidth: 2, dash: [4, 3]))

            let pill = ctx.resolve(Text("you").font(.witsLabel(11)).foregroundStyle(.white))
            let pillSize = pill.measure(in: CGSize(width: 100, height: 40))
            let pillW = pillSize.width + 16
            let pillH = pillSize.height + 6
            let pillX = min(size.width - pillW / 2, max(pillW / 2, mx))
            let pillRect = CGRect(x: pillX - pillW / 2, y: topPad - 4 - pillH,
                                  width: pillW, height: pillH)
            ctx.fill(Capsule().path(in: pillRect), with: .color(tint))
            ctx.draw(pill, at: CGPoint(x: pillRect.midX, y: pillRect.midY), anchor: .center)
        }
        .frame(height: 170)
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
            ctx.fill(dp, with: .color(.witsAccent.opacity(0.20)))
            ctx.stroke(dp, with: .color(.witsAccent), lineWidth: 2)
            // domain-colored vertices
            for i in 0..<n {
                let q = pt(i, max(0.03, vals[i]))
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - 4, y: q.y - 4, width: 8, height: 8)),
                         with: .color(domains[i].color))
                ctx.stroke(Path(ellipseIn: CGRect(x: q.x - 4, y: q.y - 4, width: 8, height: 8)),
                           with: .color(.witsCard), lineWidth: 1.5)
            }
            // axis labels in each domain's color
            for i in 0..<n {
                let q = pt(i, 1.16)
                ctx.draw(Text(domains[i].label)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(domains[i].color), at: q, anchor: .center)
            }
        }
        .frame(height: 250)
        .padding(16)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }
}
