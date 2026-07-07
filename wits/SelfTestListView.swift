//
//  SelfTestListView.swift
//  wits
//
//  Full self-report test catalog, pushed from the profile page.
//

import SwiftUI

struct SelfTestListView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var activeTest: SelfTest?

    private var completedSelfTestCount: Int {
        SelfTestCatalog.all.filter { app.selfTests[$0.id] != nil }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                pageHeader

                VStack(spacing: 10) {
                    ForEach(SelfTestCatalog.all) { test in
                        Button {
                            activeTest = test
                        } label: {
                            selfTestCard(test)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, WitsMetrics.screenPadding)

                Text("self-report tests are reflections, not diagnoses. retake them any time; your latest result is kept.")
                    .font(.witsBody(12.5))
                    .foregroundStyle(Color.witsFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, WitsMetrics.screenPadding + 4)
                    .padding(.top, 2)
                    .padding(.bottom, 40)
            }
        }
        .background(Color.witsBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $activeTest) { test in
            SelfTestFlowView(test: test, lastRecord: app.selfTests[test.id]) { outcome in
                app.recordSelfTest(test, outcome: outcome)
            }
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Button { dismiss() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .heavy))
                        Text("profile")
                            .font(.witsLabel(12.5))
                            .textCase(.uppercase)
                            .kerning(0.8)
                    }
                    .foregroundStyle(Color.witsFaint)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("back to profile")

                Text("self-report")
                    .font(.witsDisplay(30))
                    .foregroundStyle(Color.witsInk)
            }

            Spacer(minLength: 12)

            Text("\(completedSelfTestCount)/\(SelfTestCatalog.all.count)")
                .font(.witsLabel(12))
                .foregroundStyle(Color.witsAccent)
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.witsAccent.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func selfTestCard(_ test: SelfTest) -> some View {
        let record = app.selfTests[test.id]
        let shape = RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous)

        return HStack(alignment: .center, spacing: 13) {
            Image(systemName: test.icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(test.tint)
                .frame(width: 38, height: 38)
                .background(test.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(test.name)
                        .font(.witsHeading(16))
                        .foregroundStyle(Color.witsInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .layoutPriority(1)

                    if test.isScreener && !test.name.localizedCaseInsensitiveContains("screener") {
                        Text("screener")
                            .font(.witsLabel(10.5))
                            .foregroundStyle(Color.witsFaint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.witsTint, in: Capsule())
                            .lineLimit(1)
                    }
                }

                Text(record?.label ?? test.tagline)
                    .font(.witsBody(12.8))
                    .foregroundStyle(Color.witsMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 5) {
                testStatusChip(title: record == nil ? "take it" : "latest",
                               tint: test.tint,
                               filled: record != nil)

                Text(record.map { SelfTestFlowView.shortDate($0.takenAt) } ?? "\(test.questions.count) q")
                    .font(.witsLabel(11.5))
                    .foregroundStyle(Color.witsFaint)
                    .lineLimit(1)
                    .monospacedDigit()
            }
            .frame(width: 58, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.witsFaint)
        }
        .padding(14)
        .background(Color.witsCard, in: shape)
        .overlay(shape.strokeBorder(Color.witsLine, lineWidth: 1))
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(record.map { "\(test.name), latest result \($0.label)" } ?? "\(test.name), not taken")
    }

    private func testStatusChip(title: String, tint: Color, filled: Bool) -> some View {
        Text(title)
            .font(.witsLabel(11))
            .foregroundStyle(filled ? Color.white : tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(filled ? tint : tint.opacity(0.12), in: Capsule())
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}
