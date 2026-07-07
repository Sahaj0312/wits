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

                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 12),
                ], spacing: 18) {
                    ForEach(SelfTestCatalog.all) { test in
                        Button {
                            activeTest = test
                        } label: {
                            testGridCard(test)
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

    private func estimatedMinutes(_ test: SelfTest) -> Int {
        max(1, Int(ceil(Double(test.questions.count) / 6.0)))
    }

    private func testGridCard(_ test: SelfTest) -> some View {
        let record = app.selfTests[test.id]

        return VStack(alignment: .leading, spacing: 9) {
            testIllustration(test, taken: record != nil)

            VStack(alignment: .leading, spacing: 3) {
                Text(test.name)
                    .font(.witsHeading(15.5))
                    .foregroundStyle(Color.witsInk)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(record?.label ?? "\(test.questions.count) questions · \(estimatedMinutes(test)) min")
                    .font(.witsLabel(11))
                    .foregroundStyle(record == nil ? Color.witsFaint : test.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .monospacedDigit()
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(record.map { "\(test.name), latest result \($0.label)" } ?? "\(test.name), not taken, \(test.questions.count) questions")
    }

    private func testIllustration(_ test: SelfTest, taken: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous)
        let assetName = "selftest-\(test.id)"

        return Color.clear
            .aspectRatio(1.12, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                if UIImage(named: assetName) != nil {
                    Image(assetName)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(colors: [test.tint.opacity(0.22), test.tint.opacity(0.07)],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing)
                        Image(systemName: test.icon)
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(test.tint)
                    }
                    .background(Color.witsCard)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.witsLine, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if taken {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(test.tint, in: Circle())
                        .padding(7)
                }
            }
    }
}
