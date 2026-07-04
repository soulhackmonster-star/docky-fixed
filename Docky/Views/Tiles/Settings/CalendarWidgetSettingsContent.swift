//
//  CalendarWidgetSettingsContent.swift
//  Docky
//

import AppKit
import SwiftUI

struct CalendarWidgetSettingsContent: View {
    let tileID: String

    @ObservedObject private var calendarService = CalendarService.shared

    @State private var choices: [CalendarChoice] = []
    @State private var included: Set<String> = []

    private let settingKey = "calendar.calendarIDs"

    var body: some View {
        Group {
            if calendarService.permissionStatus != .granted {
                noAccessView
            } else if choices.isEmpty {
                Text("No calendars available.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                calendarList
            }
        }
        .onAppear(perform: load)
    }

    private var calendarList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Show events from")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(choices) { choice in
                Toggle(isOn: binding(for: choice)) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(nsColor: choice.color))
                            .frame(width: 10, height: 10)
                        Text(choice.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .toggleStyle(.checkbox)
            }

            Text("All calendars are shown when none are selected.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
    }

    private var noAccessView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Calendar access is needed to choose which calendars to show.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Enable Calendar Access") {
                Task {
                    _ = await calendarService.requestAccess()
                    load()
                }
            }
        }
    }

    private func binding(for choice: CalendarChoice) -> Binding<Bool> {
        Binding(
            get: { included.contains(choice.identifier) },
            set: { isOn in
                if isOn {
                    included.insert(choice.identifier)
                } else {
                    included.remove(choice.identifier)
                }
                persist()
            }
        )
    }

    private func load() {
        choices = calendarService.availableCalendars()
        let availableIDs = Set(choices.map(\.identifier))

        let stored = TileStore.shared.widgetSettings(tileID: tileID)?.stringList(settingKey) ?? []
        if stored.isEmpty {
            // Absent / empty == show all.
            included = availableIDs
        } else {
            let selection = availableIDs.intersection(stored)
            // Stored calendars no longer present fall back to "all" so the widget keeps working.
            included = selection.isEmpty ? availableIDs : selection
        }
    }

    private func persist() {
        let availableIDs = Set(choices.map(\.identifier))

        // All-selected and none-selected both mean the default (show everything); clear the key rather than store a list.
        if included.isEmpty || included == availableIDs {
            TileStore.shared.setWidgetSetting(tileID: tileID, key: settingKey, value: nil)
        } else {
            TileStore.shared.setWidgetSetting(
                tileID: tileID,
                key: settingKey,
                value: .stringList(Array(included))
            )
        }
    }
}
