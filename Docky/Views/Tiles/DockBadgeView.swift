//
//  DockBadgeView.swift
//  Docky
//
//  The red notification badge drawn over a running app's tile, mirroring the
//  system Dock's badge. Sizes itself relative to the tile so it scales with
//  the dock.
//

import SwiftUI

struct DockBadgeView: View {
    let text: String

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            badge(forTileSide: side)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topTrailing)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func badge(forTileSide side: CGFloat) -> some View {
        let height = max(8, side * 0.285)
        let fontSize = height * 0.62
        let horizontalPadding = height * 0.28

        Text(displayText)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(.white)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, horizontalPadding)
            .frame(minWidth: height, minHeight: height)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.red)
                    .shadow(color: .black.opacity(0.3), radius: max(1, height * 0.08), y: max(0.5, height * 0.03))
            )
            // Sit just inside the icon's top-trailing corner: half a badge
            // height down, and a quarter height to the left of the corner.
            .offset(x: height * 0.05, y: height * 0.30)
    }

    /// Clamp absurdly long status strings so a badge can't blow out the
    /// tile. The Dock itself shows "99+" past two digits for most apps;
    /// non-numeric labels (rare) are passed through but capped.
    private var displayText: String {
        if text.count <= 4 { return text }
        if let value = Int(text), value > 999 { return "999+" }
        return String(text.prefix(4))
    }
}
