//
//  PaywallView.swift
//  wits
//
//  A one-page, one-time-purchase paywall that continues the personal note
//  from onboarding instead of reading like a generic subscription screen.
//

import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var product: Product?
    @State private var loaded = false
    @State private var purchasing = false
    @State private var note: String?

    private let pageBackground = Color(hexAny: 0x09090B)
    private let controlFill = Color(hexAny: 0x232327)
    private let paper = Color(hexAny: 0xF2F0EA)
    private let hairline = Color.white.opacity(0.11)

    var body: some View {
        GeometryReader { geometry in
            let layout = PaywallLayout.forHeight(geometry.size.height)

            VStack(alignment: .leading, spacing: 0) {
                header(layout)

                letter(layout)
                    .padding(.top, layout.letterTopPadding)

                changes(layout)
                    .padding(.top, layout.changesTopPadding)

                purchaseRow(layout)
                    .padding(.top, layout.purchaseTopPadding)

                purchaseButton(layout)
                    .padding(.top, layout.buttonTopPadding)

                status(layout)
                    .padding(.top, layout.statusTopPadding)

                restoreButton(layout)
                    .padding(.top, layout.restoreTopPadding)

                legal(layout)
                    .padding(.top, layout.legalTopPadding)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.bottom, layout.bottomPadding)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(pageBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task { await loadProduct() }
    }

    private func header(_ layout: PaywallLayout) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ad-free")
                    .font(.system(size: layout.headerSize, weight: .black))
                    .foregroundStyle(.white)

                Rectangle()
                    .fill(Color.witsAccent)
                    .frame(width: 30, height: 4)
            }

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: layout.closeGlyphSize, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: layout.closeSize, height: layout.closeSize)
                    .background(controlFill, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(PressScale())
            .accessibilityLabel("Close paywall")
        }
        .padding(.top, layout.headerTopPadding)
    }

    private func letter(_ layout: PaywallLayout) -> some View {
        VStack(alignment: .leading, spacing: layout.paragraphSpacing) {
            Text("hey —")
                .font(.system(size: layout.letterTitleSize, weight: .semibold, design: .serif))
                .foregroundStyle(.white)

            Text("wits is free, and i want to keep it that way. the occasional ad keeps the lights on.")

            Text("if you’d rather skip the breaks, this one purchase removes automatic ads for good.")

            Text("— sahaj")
                .italic()
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: layout.letterBodySize, weight: .regular, design: .serif))
        .foregroundStyle(.white.opacity(0.86))
        .lineSpacing(layout.letterLineSpacing)
        .padding(.horizontal, 4)
    }

    private func changes(_ layout: PaywallLayout) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("what changes")
                .font(.system(size: layout.sectionLabelSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.42))
                .textCase(.uppercase)
                .kerning(0.8)
                .padding(.bottom, layout.sectionLabelBottomPadding)

            changeRow(title: "automatic ads", value: "removed", layout: layout)

            Rectangle()
                .fill(hairline)
                .frame(height: 1)

            changeRow(title: "rewarded continues", value: "still optional", layout: layout)
        }
    }

    private func changeRow(title: String,
                           value: String,
                           layout: PaywallLayout) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.white.opacity(0.88))

            Spacer(minLength: 12)

            Text(value)
                .foregroundStyle(Color.witsAccent)
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: layout.changeRowSize, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(height: layout.changeRowHeight)
    }

    private func purchaseRow(_ layout: PaywallLayout) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("ad-free forever")
                    .font(.system(size: layout.purchaseTitleSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("one purchase · no renewal")
                    .font(.system(size: layout.purchaseDetailSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.44))
            }

            Spacer(minLength: 8)

            price(layout)
        }
        .padding(.vertical, layout.purchaseVerticalPadding)
        .overlay(alignment: .top) {
            Rectangle().fill(hairline).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(hairline).frame(height: 1)
        }
    }

    @ViewBuilder
    private func price(_ layout: PaywallLayout) -> some View {
        if let product {
            Text(product.displayPrice)
                .font(.system(size: layout.priceSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        } else if loaded {
            Text("waiting for App Store")
                .font(.system(size: layout.unavailableSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.44))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        } else {
            ProgressView()
                .tint(.white.opacity(0.65))
        }
    }

    private func purchaseButton(_ layout: PaywallLayout) -> some View {
        Button { primaryAction() } label: {
            HStack(spacing: 9) {
                if purchasing || (!loaded && product == nil) {
                    ProgressView()
                        .tint(product == nil ? .white : pageBackground)
                }

                Text(primaryTitle)
                    .font(.system(size: layout.buttonTitleSize,
                                  weight: .semibold,
                                  design: .rounded))
            }
            .foregroundStyle(product == nil ? .white : pageBackground)
            .frame(maxWidth: .infinity)
            .frame(height: layout.buttonHeight)
            .background(product == nil ? controlFill : paper,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(product == nil ? 0.10 : 0), lineWidth: 1)
            )
        }
        .buttonStyle(PressScale())
        .disabled(purchasing || (!loaded && product == nil))
        .opacity((!loaded && product == nil) ? 0.62 : 1)
    }

    private func status(_ layout: PaywallLayout) -> some View {
        Group {
            if let note {
                Text(note)
                    .foregroundStyle(Color.witsWarm)
            } else if loaded, product == nil {
                Text("the App Store hasn’t returned this purchase yet.")
                    .foregroundStyle(.white.opacity(0.42))
            } else {
                Text("")
            }
        }
        .font(.system(size: layout.restoreSize - 0.5, weight: .medium, design: .rounded))
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .minimumScaleFactor(0.74)
        .frame(maxWidth: .infinity)
        .frame(height: layout.restoreSize + 4)
    }

    private func restoreButton(_ layout: PaywallLayout) -> some View {
        Button { restore() } label: {
            Text("restore purchase")
                .font(.system(size: layout.restoreSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
                .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .disabled(purchasing)
        .frame(maxWidth: .infinity)
    }

    private func legal(_ layout: PaywallLayout) -> some View {
        Text("one-time purchase charged to your Apple ID at confirmation. no subscription or recurring charge.")
            .font(.system(size: layout.legalSize, weight: .regular, design: .rounded))
            .foregroundStyle(.white.opacity(0.27))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.78)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
    }

    private var primaryTitle: String {
        if purchasing { return "one moment…" }
        if !loaded { return "asking the App Store…" }
        if product == nil { return "check the App Store again" }
        return "remove automatic ads"
    }

    private func primaryAction() {
        if product == nil {
            loaded = false
            note = nil
            Task { await loadProduct() }
        } else {
            buy()
        }
    }

    private func loadProduct() async {
        product = await PurchasesManager.shared.adFreeLifetimeProduct()
        loaded = true
    }

    private func buy() {
        guard let product, !purchasing else { return }
        purchasing = true
        note = nil

        Task {
            defer { purchasing = false }
            do {
                if try await PurchasesManager.shared.purchase(product) {
                    dismiss()
                }
            } catch {
                withAnimation {
                    note = "the purchase didn’t complete. you haven’t been charged."
                }
            }
        }
    }

    private func restore() {
        guard !purchasing else { return }
        purchasing = true
        note = nil

        Task {
            defer { purchasing = false }
            do {
                if try await PurchasesManager.shared.restore() {
                    dismiss()
                } else {
                    withAnimation { note = "no previous purchase was found." }
                }
            } catch {
                withAnimation { note = "restore failed. try again in a moment." }
            }
        }
    }
}

private struct PaywallLayout {
    let horizontalPadding: CGFloat
    let headerTopPadding: CGFloat
    let bottomPadding: CGFloat
    let letterTopPadding: CGFloat
    let changesTopPadding: CGFloat
    let purchaseTopPadding: CGFloat
    let buttonTopPadding: CGFloat
    let statusTopPadding: CGFloat
    let restoreTopPadding: CGFloat
    let legalTopPadding: CGFloat
    let headerSize: CGFloat
    let closeSize: CGFloat
    let closeGlyphSize: CGFloat
    let letterTitleSize: CGFloat
    let letterBodySize: CGFloat
    let letterLineSpacing: CGFloat
    let paragraphSpacing: CGFloat
    let sectionLabelSize: CGFloat
    let sectionLabelBottomPadding: CGFloat
    let changeRowSize: CGFloat
    let changeRowHeight: CGFloat
    let purchaseVerticalPadding: CGFloat
    let purchaseTitleSize: CGFloat
    let purchaseDetailSize: CGFloat
    let priceSize: CGFloat
    let unavailableSize: CGFloat
    let buttonHeight: CGFloat
    let buttonTitleSize: CGFloat
    let restoreSize: CGFloat
    let legalSize: CGFloat

    static func forHeight(_ height: CGFloat) -> Self {
        if height >= 820 { return .regular }
        if height >= 700 { return .compact }
        return .tight
    }

    private static let regular = Self(
        horizontalPadding: 24, headerTopPadding: 14, bottomPadding: 8,
        letterTopPadding: 48, changesTopPadding: 42, purchaseTopPadding: 32,
        buttonTopPadding: 20, statusTopPadding: 9, restoreTopPadding: 12,
        legalTopPadding: 4, headerSize: 29, closeSize: 44, closeGlyphSize: 16,
        letterTitleSize: 27, letterBodySize: 17, letterLineSpacing: 5,
        paragraphSpacing: 16, sectionLabelSize: 11.5, sectionLabelBottomPadding: 5,
        changeRowSize: 15, changeRowHeight: 51, purchaseVerticalPadding: 17,
        purchaseTitleSize: 17, purchaseDetailSize: 13, priceSize: 23,
        unavailableSize: 12, buttonHeight: 54, buttonTitleSize: 16,
        restoreSize: 12.5, legalSize: 10.5
    )

    private static let compact = Self(
        horizontalPadding: 21, headerTopPadding: 8, bottomPadding: 4,
        letterTopPadding: 29, changesTopPadding: 25, purchaseTopPadding: 20,
        buttonTopPadding: 14, statusTopPadding: 6, restoreTopPadding: 7,
        legalTopPadding: 2, headerSize: 26, closeSize: 40, closeGlyphSize: 15,
        letterTitleSize: 23, letterBodySize: 15, letterLineSpacing: 3,
        paragraphSpacing: 11, sectionLabelSize: 10.5, sectionLabelBottomPadding: 3,
        changeRowSize: 13.5, changeRowHeight: 43, purchaseVerticalPadding: 13,
        purchaseTitleSize: 15, purchaseDetailSize: 11.5, priceSize: 20,
        unavailableSize: 10.5, buttonHeight: 49, buttonTitleSize: 14.5,
        restoreSize: 11.5, legalSize: 9.5
    )

    private static let tight = Self(
        horizontalPadding: 18, headerTopPadding: 3, bottomPadding: 1,
        letterTopPadding: 16, changesTopPadding: 14, purchaseTopPadding: 12,
        buttonTopPadding: 9, statusTopPadding: 3, restoreTopPadding: 3,
        legalTopPadding: 1, headerSize: 23, closeSize: 38, closeGlyphSize: 14,
        letterTitleSize: 20, letterBodySize: 13.5, letterLineSpacing: 2,
        paragraphSpacing: 8, sectionLabelSize: 9.5, sectionLabelBottomPadding: 2,
        changeRowSize: 12.5, changeRowHeight: 37, purchaseVerticalPadding: 9,
        purchaseTitleSize: 14, purchaseDetailSize: 10.5, priceSize: 18,
        unavailableSize: 9.5, buttonHeight: 45, buttonTitleSize: 13.5,
        restoreSize: 10.5, legalSize: 8.5
    )
}
