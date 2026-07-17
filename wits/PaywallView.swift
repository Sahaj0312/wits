//
//  PaywallView.swift
//  wits
//
//  One-page lifetime purchase screen: the structure of the original ad-free
//  offer, rebuilt with Wits typography, color, and controls.
//

import StoreKit
import SwiftUI
import UIKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var product: Product?
    @State private var loaded = false
    @State private var purchasing = false
    @State private var note: String?

    private let pageBackground = Color(hexAny: 0x09090B)
    private let cardFill = Color(hexAny: 0x1B1B20)

    var body: some View {
        GeometryReader { geometry in
            let layout = PaywallLayout.forHeight(geometry.size.height)

            VStack(spacing: 0) {
                closeButton(layout)

                appIcon(layout)
                    .padding(.top, layout.appIconTopPadding)

                headline(layout)
                    .padding(.top, layout.headlineTopPadding)

                features(layout)
                    .padding(.top, layout.featuresTopPadding)

                Spacer(minLength: layout.minimumFlexibleSpace)

                price(layout)
                    .padding(.top, layout.priceTopPadding)

                purchaseButton(layout)
                    .padding(.top, layout.buttonTopPadding)

                status(layout)
                    .padding(.top, layout.statusTopPadding)

                restoreButton(layout)
                    .padding(.top, layout.restoreTopPadding)

                legal(layout)
                    .padding(.top, layout.legalTopPadding)
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

    private func closeButton(_ layout: PaywallLayout) -> some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: layout.closeGlyphSize, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: layout.closeSize, height: layout.closeSize)
                    .background(cardFill, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(TactilePressScale())
            .accessibilityLabel("Close paywall")

            Spacer()
        }
        .padding(.top, layout.headerTopPadding)
    }

    @ViewBuilder
    private func appIcon(_ layout: PaywallLayout) -> some View {
        if let appIconImage {
            Image(uiImage: appIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: layout.appIconSize, height: layout.appIconSize)
                .clipShape(
                    RoundedRectangle(cornerRadius: layout.appIconSize * 0.225,
                                     style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: layout.appIconSize * 0.225,
                                     style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.38), radius: 12, y: 6)
                .accessibilityHidden(true)
        } else {
            Image("WitsMark")
                .resizable()
                .scaledToFit()
                .frame(width: layout.appIconSize, height: layout.appIconSize)
                .accessibilityHidden(true)
        }
    }

    private var appIconImage: UIImage? {
        guard
            let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let files = primary["CFBundleIconFiles"] as? [String],
            let iconName = files.last
        else {
            return nil
        }

        return UIImage(named: iconName)
    }

    private func headline(_ layout: PaywallLayout) -> some View {
        VStack(spacing: layout.headlineSpacing) {
            Text("PLAY WITHOUT")
                .foregroundStyle(.white)

            Text("INTERRUPTIONS")
                .foregroundStyle(Color.witsAccent)
        }
        .font(.system(size: layout.headlineSize, weight: .black, design: .rounded))
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func features(_ layout: PaywallLayout) -> some View {
        VStack(spacing: layout.featureSpacing) {
            featureCard(
                symbol: "xmark",
                tint: .witsWarm,
                title: Text("\(Text("REMOVE").foregroundColor(.witsWarm))\n\(Text("AUTOMATIC ADS").foregroundColor(.white))"),
                detail: "no forced break after a game.",
                height: layout.firstFeatureHeight,
                layout: layout
            )

            featureCard(
                symbol: "play.fill",
                tint: .witsAccent,
                title: Text("\(Text("KEEP").foregroundColor(.witsAccent)) \(Text("OPTIONAL ADS").foregroundColor(.white))\n\(Text("FOR REWARDS").foregroundColor(.white))"),
                detail: "extra life or continue — only when you choose.",
                height: layout.secondFeatureHeight,
                layout: layout
            )
        }
    }

    private func featureCard(symbol: String,
                             tint: Color,
                             title: Text,
                             detail: String,
                             height: CGFloat,
                             layout: PaywallLayout) -> some View {
        HStack(spacing: layout.featureInnerSpacing) {
            Image(systemName: symbol)
                .font(.system(size: layout.featureSymbolSize, weight: .black))
                .foregroundStyle(.white)
                .frame(width: layout.featureIconSize, height: layout.featureIconSize)
                .background(tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: layout.featureTextSpacing) {
                title
                    .font(.system(size: layout.featureTitleSize,
                                  weight: .black,
                                  design: .rounded))
                    .lineSpacing(-2)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                Text(detail)
                    .font(.system(size: layout.featureDetailSize,
                                  weight: .medium,
                                  design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, layout.featureHorizontalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(cardFill,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func price(_ layout: PaywallLayout) -> some View {
        if let product {
            Text(product.displayPrice)
                .font(.system(size: layout.priceSize, weight: .black, design: .rounded))
                .foregroundStyle(Color.witsGold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        } else if loaded {
            Text("NOT AVAILABLE")
                .font(.system(size: layout.unavailableSize, weight: .bold, design: .rounded))
                .foregroundStyle(Color.witsWarm)
                .lineLimit(1)
        } else {
            ProgressView()
                .tint(Color.witsAccent)
                .frame(height: layout.priceSize)
        }
    }

    private func purchaseButton(_ layout: PaywallLayout) -> some View {
        Button { primaryAction() } label: {
            HStack(spacing: 8) {
                if purchasing || (!loaded && product == nil) {
                    ProgressView()
                        .tint(pageBackground)
                }

                Text(primaryTitle)
                    .font(.system(size: layout.buttonTitleSize,
                                  weight: .black,
                                  design: .rounded))
            }
            .foregroundStyle(pageBackground)
            .frame(width: layout.buttonWidth, height: layout.buttonHeight)
            .background(Color.witsAccent,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.20), lineWidth: 1)
            )
        }
        .buttonStyle(TactilePressScale(feedback: .primary))
        .disabled(purchasing || (!loaded && product == nil))
        .opacity((!loaded && product == nil) ? 0.58 : 1)
    }

    private func status(_ layout: PaywallLayout) -> some View {
        Group {
            if let note {
                Text(note)
                    .foregroundStyle(Color.witsWarm)
            } else if loaded, product == nil {
                Text("the App Store hasn’t returned this purchase yet.")
                    .foregroundStyle(.white.opacity(0.40))
            } else {
                Text("")
            }
        }
        .font(.system(size: layout.statusSize, weight: .medium, design: .rounded))
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .frame(maxWidth: .infinity)
        .frame(height: layout.statusHeight)
    }

    private func restoreButton(_ layout: PaywallLayout) -> some View {
        Button {
            GameFeel.shared.uiTap()
            restore()
        } label: {
            Text("RESTORE PURCHASE")
                .font(.system(size: layout.restoreSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.44))
                .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .disabled(purchasing)
    }

    private func legal(_ layout: PaywallLayout) -> some View {
        Text("one-time purchase charged to your Apple ID at confirmation. no subscription or recurring charge.")
            .font(.system(size: layout.legalSize, weight: .regular, design: .rounded))
            .foregroundStyle(.white.opacity(0.27))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.76)
            .padding(.horizontal, 8)
    }

    private var primaryTitle: String {
        if purchasing { return "ONE MOMENT…" }
        if !loaded { return "LOADING…" }
        if product == nil { return "TRY AGAIN" }
        return "UNLOCK"
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
    let closeSize: CGFloat
    let closeGlyphSize: CGFloat
    let appIconSize: CGFloat
    let appIconTopPadding: CGFloat
    let headlineTopPadding: CGFloat
    let headlineSize: CGFloat
    let headlineSpacing: CGFloat
    let featuresTopPadding: CGFloat
    let featureSpacing: CGFloat
    let firstFeatureHeight: CGFloat
    let secondFeatureHeight: CGFloat
    let featureHorizontalPadding: CGFloat
    let featureInnerSpacing: CGFloat
    let featureIconSize: CGFloat
    let featureSymbolSize: CGFloat
    let featureTextSpacing: CGFloat
    let featureTitleSize: CGFloat
    let featureDetailSize: CGFloat
    let minimumFlexibleSpace: CGFloat
    let priceTopPadding: CGFloat
    let priceSize: CGFloat
    let unavailableSize: CGFloat
    let buttonTopPadding: CGFloat
    let buttonWidth: CGFloat
    let buttonHeight: CGFloat
    let buttonTitleSize: CGFloat
    let statusTopPadding: CGFloat
    let statusSize: CGFloat
    let statusHeight: CGFloat
    let restoreTopPadding: CGFloat
    let restoreSize: CGFloat
    let legalTopPadding: CGFloat
    let legalSize: CGFloat

    static func forHeight(_ height: CGFloat) -> Self {
        if height >= 820 { return .regular }
        if height >= 700 { return .compact }
        return .tight
    }

    private static let regular = Self(
        horizontalPadding: 22, headerTopPadding: 10, bottomPadding: 5,
        closeSize: 50, closeGlyphSize: 21, appIconSize: 100,
        appIconTopPadding: 15,
        headlineTopPadding: 27, headlineSize: 39, headlineSpacing: -4,
        featuresTopPadding: 29, featureSpacing: 16,
        firstFeatureHeight: 112, secondFeatureHeight: 140,
        featureHorizontalPadding: 19, featureInnerSpacing: 17,
        featureIconSize: 60, featureSymbolSize: 25, featureTextSpacing: 7,
        featureTitleSize: 23, featureDetailSize: 14,
        minimumFlexibleSpace: 7,
        priceTopPadding: 12, priceSize: 37, unavailableSize: 15,
        buttonTopPadding: 12, buttonWidth: 210, buttonHeight: 60,
        buttonTitleSize: 20, statusTopPadding: 4, statusSize: 12,
        statusHeight: 15, restoreTopPadding: 4, restoreSize: 12,
        legalTopPadding: 2, legalSize: 9.5
    )

    private static let compact = Self(
        horizontalPadding: 20, headerTopPadding: 7, bottomPadding: 3,
        closeSize: 46, closeGlyphSize: 19, appIconSize: 84,
        appIconTopPadding: 11,
        headlineTopPadding: 17, headlineSize: 34, headlineSpacing: -3,
        featuresTopPadding: 21, featureSpacing: 14,
        firstFeatureHeight: 100, secondFeatureHeight: 124,
        featureHorizontalPadding: 16, featureInnerSpacing: 14,
        featureIconSize: 52, featureSymbolSize: 21, featureTextSpacing: 5,
        featureTitleSize: 20, featureDetailSize: 12.5,
        minimumFlexibleSpace: 5,
        priceTopPadding: 10, priceSize: 32, unavailableSize: 13,
        buttonTopPadding: 9, buttonWidth: 194, buttonHeight: 54,
        buttonTitleSize: 18, statusTopPadding: 4, statusSize: 11,
        statusHeight: 13, restoreTopPadding: 4, restoreSize: 11,
        legalTopPadding: 2, legalSize: 8.7
    )

    private static let tight = Self(
        horizontalPadding: 17, headerTopPadding: 3, bottomPadding: 1,
        closeSize: 42, closeGlyphSize: 17, appIconSize: 66,
        appIconTopPadding: 7,
        headlineTopPadding: 9, headlineSize: 29, headlineSpacing: -2,
        featuresTopPadding: 12, featureSpacing: 10,
        firstFeatureHeight: 88, secondFeatureHeight: 104,
        featureHorizontalPadding: 14, featureInnerSpacing: 12,
        featureIconSize: 45, featureSymbolSize: 18, featureTextSpacing: 3,
        featureTitleSize: 17, featureDetailSize: 10.5,
        minimumFlexibleSpace: 2,
        priceTopPadding: 7, priceSize: 26, unavailableSize: 11,
        buttonTopPadding: 6, buttonWidth: 178, buttonHeight: 48,
        buttonTitleSize: 16, statusTopPadding: 2, statusSize: 9.5,
        statusHeight: 11, restoreTopPadding: 2, restoreSize: 9.5,
        legalTopPadding: 1, legalSize: 7.8
    )
}
