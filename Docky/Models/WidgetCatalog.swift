//
//  WidgetCatalog.swift
//  Docky
//

import Foundation

enum WidgetOwnerBundleIdentifiers {
    static let calendar = "com.apple.iCal"
    static let reminders = "com.apple.reminders"
    static let batteries = "gt.quintero.Docky.batteries"
    static let weather = "gt.quintero.Docky.weather"
    static let genericNowPlaying = "gt.quintero.Docky.now-playing"
}

struct WidgetRegistration: Equatable, Identifiable {
    let kind: WidgetKind
    let ownerBundleIdentifier: String
    let defaultSpan: TileSpan
    let includesInPalette: Bool
    let includesInSmartStack: Bool

    var id: String {
        "\(ownerBundleIdentifier):\(kind.rawValue)"
    }

    func makeTile(span: TileSpan? = nil) -> WidgetTile {
        WidgetTile(
            identifier: id,
            title: kind.title,
            kind: kind,
            ownerBundleIdentifier: ownerBundleIdentifier,
            span: span ?? defaultSpan
        )
    }
}

enum WidgetCatalog {
    static let calendar = WidgetRegistration(
        kind: .calendar,
        ownerBundleIdentifier: WidgetOwnerBundleIdentifiers.calendar,
        defaultSpan: .three,
        includesInPalette: true,
        includesInSmartStack: true
    )

    static let reminders = WidgetRegistration(
        kind: .reminders,
        ownerBundleIdentifier: WidgetOwnerBundleIdentifiers.reminders,
        defaultSpan: .three,
        includesInPalette: true,
        includesInSmartStack: true
    )

    static let batteries = WidgetRegistration(
        kind: .batteries,
        ownerBundleIdentifier: WidgetOwnerBundleIdentifiers.batteries,
        defaultSpan: .three,
        includesInPalette: true,
        includesInSmartStack: true
    )

    static let weather = WidgetRegistration(
        kind: .weather,
        ownerBundleIdentifier: WidgetOwnerBundleIdentifiers.weather,
        defaultSpan: .three,
        includesInPalette: true,
        includesInSmartStack: true
    )

    static let genericNowPlaying = WidgetRegistration(
        kind: .nowPlaying,
        ownerBundleIdentifier: WidgetOwnerBundleIdentifiers.genericNowPlaying,
        defaultSpan: .three,
        includesInPalette: true,
        includesInSmartStack: false
    )

    static let staticRegistrations: [WidgetRegistration] = [
        calendar,
        reminders,
        batteries,
        weather,
        genericNowPlaying,
    ]

    static let paletteRegistrations: [WidgetRegistration] = staticRegistrations.filter(\.includesInPalette)
    static let smartStackRegistrations: [WidgetRegistration] = staticRegistrations.filter(\.includesInSmartStack)
}
