//
//  SettingsAccessViews.swift
//  Docky
//

import SwiftUI

struct ProBadge: View {
    var body: some View {
        Text("Pro")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.20), in: Capsule())
    }
}

struct ProFeatureNotice: View {
    let feature: ProductFeature

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProBadge()
                Text(feature.title)
                    .font(.headline)
            }

            Text(feature.summary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}
