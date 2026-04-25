//
//  BehaviorSettingsView.swift
//  Docky
//

import SwiftUI

struct BehaviorSettingsView: View {
    @ObservedObject private var preferences = DockyPreferences.shared

    var body: some View {
        Form {
            Section("Placement") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Window Position")
                        .font(.headline)

                    Picker("Window Position", selection: $preferences.windowPosition) {
                        ForEach(DockWindowPosition.allCases) { position in
                            Text(position.title).tag(position)
                        }
                    }
                    .pickerStyle(.menu)

                    Text("Choose where Docky sits on screen, or mirror the macOS Dock position.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("Visibility") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Autohide Window", isOn: $preferences.autohidesWindow)
                        .font(.headline)

                    Text("Slides Docky's window off-screen until the pointer reaches its edge. Reveal and hide timing still follows the system Dock settings.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Overflow Behavior")
                        .font(.headline)

                    Picker("Overflow Behavior", selection: $preferences.overflowBehavior) {
                        ForEach(DockOverflowBehavior.allCases) { behavior in
                            Text(behavior.title).tag(behavior)
                        }
                    }
                    .pickerStyle(.menu)

                    Text("Choose whether Docky shrinks to fit the screen or keeps its size and scrolls when it runs out of room on the current dock axis.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Show Active/Pinned Separator", isOn: $preferences.showsActivePinnedSeparator)
                        .font(.headline)

                    Text("When turned off, unpinned running apps are merged into the pinned section so the dock behaves like a single app strip.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("App Folders") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Shows Grouped Opened Apps In Dock", isOn: $preferences.showsGroupedOpenedAppsInDock)
                        .font(.headline)

                    Text("Shows running apps from an app folder immediately to the right of that folder, and lets the folder reflect how many grouped apps are open.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section {
                Button("Reset to Defaults") {
                    preferences.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
    }
}
