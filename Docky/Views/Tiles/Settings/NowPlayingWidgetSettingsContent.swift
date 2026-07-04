//
//  NowPlayingWidgetSettingsContent.swift
//  Docky
//

import AppKit
import SwiftUI

enum NowPlayingWidgetSettings {
    /// `.string` bundle id of the tracked media app; absent = "Automatic" (resolve from the widget's owner bundle id).
    static let appBundleIdentifierKey = "nowPlaying.appBundleIdentifier"
}

struct NowPlayingWidgetSettingsContent: View {
    let tileID: String
    let ownerBundleIdentifier: String

    /// Sentinel tag for the "Automatic" row; safe because real bundle ids can't contain spaces.
    private static let automaticTag = "__automatic__"

    @ObservedObject private var mediaPlayback = MediaPlaybackService.shared
    @State private var selection: String

    init(tileID: String, ownerBundleIdentifier: String) {
        self.tileID = tileID
        self.ownerBundleIdentifier = ownerBundleIdentifier

        let stored = TileStore.shared
            .widgetSettings(tileID: tileID)?
            .string(NowPlayingWidgetSettings.appBundleIdentifierKey)
        _selection = State(initialValue: stored ?? Self.automaticTag)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Media App", selection: selectionBinding) {
                Text("Automatic").tag(Self.automaticTag)

                Divider()

                ForEach(mediaApps) { app in
                    Text(app.displayName).tag(app.bundleIdentifier)
                }
            }
            .labelsHidden()

            Text("Automatic follows whichever app is currently playing. Choose a specific app to always show its playback.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Ensures the currently-selected app stays in the list even when not playing, so the picker doesn't drop the stored selection.
    private var mediaApps: [MediaAppChoice] {
        var apps = mediaPlayback.availableMediaApps()

        if selection != Self.automaticTag,
           !apps.contains(where: { $0.bundleIdentifier == selection }) {
            apps.insert(
                MediaAppChoice(bundleIdentifier: selection, displayName: displayName(for: selection)),
                at: 0
            )
        }

        return apps
    }

    private var selectionBinding: Binding<String> {
        Binding(
            get: { selection },
            set: { newValue in
                selection = newValue
                apply(newValue)
            }
        )
    }

    private func apply(_ newValue: String) {
        if newValue == Self.automaticTag {
            TileStore.shared.setWidgetSetting(
                tileID: tileID,
                key: NowPlayingWidgetSettings.appBundleIdentifierKey,
                value: nil
            )
        } else {
            TileStore.shared.setWidgetSetting(
                tileID: tileID,
                key: NowPlayingWidgetSettings.appBundleIdentifierKey,
                value: .string(newValue)
            )
        }
    }

    private func displayName(for bundleIdentifier: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleIdentifier
    }
}
