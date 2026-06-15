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
