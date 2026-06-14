//
//  PaywallView.swift
//  wits
//
//  The in-app paywall (after the trial). Plans load from StoreKit; purchase and
//  restore run through the Store. Cancellation is as easy as the App Store's own
//  flow — no roach motel. Claims stay honest: a daily habit + measured progress.
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    var dismissable = true

    @State private var selectedID = Store.yearlyID
    @State private var working = false

    private var products: [Product] { app.store.products }
    private func product(_ id: String) -> Product? { products.first { $0.id == id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Wordmark()
                Spacer()
                if dismissable {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(Color.witsFaint)
                    }
                }
            }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("keep your edge")
                        .font(.witsDisplay(32))
                        .foregroundStyle(Color.witsInk)
                        .padding(.top, 14)
                        .rise()
                    Text("your free trial's done. subscribe to keep your daily workout, streak, and progress going.")
                        .font(.witsBody(15.5))
                        .foregroundStyle(Color.witsMuted)
                        .rise(0.06)

                    VStack(spacing: 10) {
                        benefit("all 7 games + your daily workout")
                        benefit("your streak and improvement chart")
                        benefit("difficulty that adapts as you sharpen")
                    }
                    .padding(.top, 4)
                    .rise(0.12)

                    VStack(spacing: 10) {
                        planCard(id: Store.yearlyID, name: "yearly", fallback: "$39.99 / year", badge: "best value")
                        planCard(id: Store.weeklyID, name: "weekly", fallback: "$4.99 / week", badge: nil)
                    }
                    .padding(.top, 8)
                    .rise(0.18)
                }
            }
            Cta(title: working ? "…" : "subscribe") { buy() }
                .padding(.top, 12)
                .rise(0.26)
            HStack(spacing: 16) {
                QuietButton(title: "restore") { Task { await app.store.restore(); if !app.entitlement.isExpired { dismiss() } } }
                Spacer()
                Text("cancel anytime in the app store")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.witsFaint)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 14)
        .background(Color.witsBg.ignoresSafeArea())
        .interactiveDismissDisabled(!dismissable)
    }

    private func benefit(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Color.witsAccent)
            Text(text)
                .font(.witsBody(15))
                .foregroundStyle(Color.witsInk)
            Spacer(minLength: 0)
        }
    }

    private func planCard(id: String, name: String, fallback: String, badge: String?) -> some View {
        let p = product(id)
        let price = p?.displayPrice ?? fallback
        let selected = selectedID == id
        return Button { selectedID = id } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsInk)
                    Text(price)
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.witsMuted)
                }
                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.witsWarm, in: Capsule())
                }
                Spacer()
                ZStack {
                    Circle().strokeBorder(selected ? Color.witsAccent : Color.witsLine, lineWidth: 2).frame(width: 22, height: 22)
                    if selected { Circle().fill(Color.witsAccent).frame(width: 12, height: 12) }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous).fill(Color.witsCard))
            .overlay(RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous)
                .strokeBorder(selected ? Color.witsAccent : .clear, lineWidth: 1.5))
            .shadow(color: .witsShadow, radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func buy() {
        guard !working, let p = product(selectedID) else { return }
        working = true
        Task {
            let ok = await app.store.purchase(p)
            working = false
            if ok { dismiss() }
        }
    }
}
