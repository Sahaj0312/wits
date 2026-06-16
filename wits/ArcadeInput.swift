//
//  ArcadeInput.swift
//  wits
//
//  One transparent overlay gesture resolves all four input archetypes against
//  the scene in unit space (Canvas entities aren't individually tappable). The
//  game's inputMode picks which interpretation runs.
//

import SwiftUI

struct ArcadeInputLayer: View {
    let mode: ArcadeInputMode
    let scene: ArcadeScene
    let onAction: (ArcadeAction) -> Void

    @State private var startUnit: CGPoint?
    @State private var dragID: Int?
    @State private var traceIDs: [Int] = []

    private let tapSlop: CGFloat = 14          // pt — below this a drag counts as a tap
    private let swipeMin: CGFloat = 24         // pt — swipe magnitude threshold
    private let pickRadius: CGFloat = 0.11     // unit — grab/tap tolerance
    private let traceRadius: CGFloat = 0.10

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in changed(v, geo.size) }
                        .onEnded { v in ended(v, geo.size) }
                )
        }
    }

    private func unit(_ p: CGPoint, _ s: CGSize) -> CGPoint {
        CGPoint(x: p.x / max(1, s.width), y: p.y / max(1, s.height))
    }

    private func changed(_ v: DragGesture.Value, _ size: CGSize) {
        let u = unit(v.location, size)
        if startUnit == nil { startUnit = unit(v.startLocation, size) }

        switch mode {
        case .drag:
            if dragID == nil {
                if let e = scene.nearest(to: startUnit ?? u, maxDist: pickRadius) {
                    dragID = e.id
                    scene.setDragging(e.id, true)
                }
            }
            if let id = dragID { scene.setPos(id, u) }
        case .trace:
            if let e = scene.nearest(to: u, maxDist: traceRadius, where: { $0.kind == 1 }),
               !traceIDs.contains(e.id) {
                traceIDs.append(e.id)
            }
        case .tap, .swipe:
            break
        }
    }

    private func ended(_ v: DragGesture.Value, _ size: CGSize) {
        let u = unit(v.location, size)
        let moved = hypot(v.translation.width, v.translation.height)

        switch mode {
        case .tap:
            if moved <= tapSlop { onAction(.tap(u)) }

        case .swipe:
            if moved >= swipeMin {
                onAction(.swipe(direction(v.translation), at: startUnit ?? u))
            }

        case .drag:
            if let id = dragID {
                scene.setDragging(id, false)
                onAction(.drop(entityID: id, at: u))
            } else if moved <= tapSlop {
                // fall back to a tap-pick so a quick tap still works in drag games
                if let e = scene.nearest(to: u, maxDist: pickRadius) {
                    onAction(.drop(entityID: e.id, at: u))
                }
            }

        case .trace:
            if !traceIDs.isEmpty { onAction(.trace(traceIDs)) }
        }

        startUnit = nil
        dragID = nil
        traceIDs = []
    }

    private func direction(_ t: CGSize) -> SwipeDir {
        abs(t.width) > abs(t.height)
            ? (t.width > 0 ? .right : .left)
            : (t.height > 0 ? .down : .up)
    }
}
