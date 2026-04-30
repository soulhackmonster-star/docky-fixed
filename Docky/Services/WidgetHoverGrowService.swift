//
//  WidgetHoverGrowService.swift
//  Docky
//

import Combine
import Foundation

final class WidgetHoverGrowService: ObservableObject {
    static let shared = WidgetHoverGrowService()

    @Published private(set) var isActive = false

    private var hoveredIdentifiers: Set<String> = []

    private init() {}

    func setHovered(_ hovered: Bool, identifier: String) {
        if hovered {
            hoveredIdentifiers.insert(identifier)
        } else {
            hoveredIdentifiers.remove(identifier)
        }

        let nowActive = !hoveredIdentifiers.isEmpty
        if nowActive != isActive {
            isActive = nowActive
        }
    }
}
