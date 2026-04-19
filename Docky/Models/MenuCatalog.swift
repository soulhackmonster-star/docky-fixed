//
//  MenuCatalog.swift
//  Docky
//

import AppKit
import Foundation

enum MenuTileType: String, Codable, CaseIterable {
    case app
    case folder
    case trash
}

enum CatalogActionKind: String, Codable {
    case builtin
    case applescript
    case menuClick
}

enum CatalogPermissionRequirement: String, Codable, CaseIterable {
    case finderAutomation
    case accessibility

    var permission: Permission {
        switch self {
        case .finderAutomation: return .finderAutomation
        case .accessibility: return .accessibility
        }
    }
}

enum CatalogContextFlag: String, Codable {
    case isRunning
    case isPinned
    case canTogglePin
    case isFinder
    case optionKey
}

enum CatalogInputKey: String, Codable, CaseIterable {
    case bundleIdentifier
    case displayName
    case appBundlePath
    case folderPath
    case filePath
}

struct CatalogCondition: Codable {
    indirect enum Kind {
        case flag(CatalogContextFlag)
        case bundleIdentifierEquals(String)
        case all([CatalogCondition])
        case any([CatalogCondition])
        case not(CatalogCondition)
    }

    let kind: Kind

    private enum CodingKeys: String, CodingKey {
        case flag
        case bundleIdentifierEquals
        case all
        case any
        case not
    }

    init(kind: Kind) {
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let flag = try container.decodeIfPresent(CatalogContextFlag.self, forKey: .flag) {
            kind = .flag(flag)
            return
        }

        if let bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifierEquals) {
            kind = .bundleIdentifierEquals(bundleIdentifier)
            return
        }

        if let conditions = try container.decodeIfPresent([CatalogCondition].self, forKey: .all) {
            kind = .all(conditions)
            return
        }

        if let conditions = try container.decodeIfPresent([CatalogCondition].self, forKey: .any) {
            kind = .any(conditions)
            return
        }

        if let condition = try container.decodeIfPresent(CatalogCondition.self, forKey: .not) {
            kind = .not(condition)
            return
        }

        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath,
            debugDescription: "Catalog condition must define exactly one condition key."
        ))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch kind {
        case .flag(let flag):
            try container.encode(flag, forKey: .flag)
        case .bundleIdentifierEquals(let bundleIdentifier):
            try container.encode(bundleIdentifier, forKey: .bundleIdentifierEquals)
        case .all(let conditions):
            try container.encode(conditions, forKey: .all)
        case .any(let conditions):
            try container.encode(conditions, forKey: .any)
        case .not(let condition):
            try container.encode(condition, forKey: .not)
        }
    }

    func evaluate(in context: CatalogActionContext) -> Bool {
        switch kind {
        case .flag(let flag):
            return context.value(for: flag)
        case .bundleIdentifierEquals(let bundleIdentifier):
            return context.bundleIdentifier == bundleIdentifier
        case .all(let conditions):
            return conditions.allSatisfy { $0.evaluate(in: context) }
        case .any(let conditions):
            return conditions.contains { $0.evaluate(in: context) }
        case .not(let condition):
            return !condition.evaluate(in: context)
        }
    }
}

struct CatalogPackageManifest: Codable, Identifiable {
    let id: String
    let title: String
    let author: String
    let version: String
    let reviewStatus: String
    let description: String?
}

struct CatalogActionPackage: Codable, Identifiable {
    let id: String
    let title: String
    let author: String
    let version: String
    let reviewStatus: String
    let description: String?
    let actions: [CatalogActionDefinition]

    var manifest: CatalogPackageManifest {
        CatalogPackageManifest(
            id: id,
            title: title,
            author: author,
            version: version,
            reviewStatus: reviewStatus,
            description: description
        )
    }
}

struct CatalogActionsDocument: Codable {
    let version: Int
    let packages: [CatalogActionPackage]
}

struct CatalogMenusDocument: Codable {
    let version: Int
    let menus: [CatalogMenuDefinition]
}

struct CatalogActionDefinition: Codable, Identifiable {
    let id: String
    let title: String
    let alternateTitle: String?
    let alternateTitleWhen: CatalogCondition?
    let kind: CatalogActionKind
    let tileTypes: [MenuTileType]
    let destructive: Bool
    let destructiveWhen: CatalogCondition?
    let toggleFlag: CatalogContextFlag?
    let when: CatalogCondition?
    let permissions: [CatalogPermissionRequirement]
    let builtinIdentifier: String?
    let targetApp: String?
    let inputs: [CatalogInputKey]
    let script: String?
    let path: [String]?
    let requiresFrontmost: Bool
    let holdOption: Bool
}

enum CatalogMenuItemType: String, Codable {
    case action
    case submenu
    case divider
}

struct CatalogMenuDefinition: Codable {
    let tileType: MenuTileType
    let items: [CatalogMenuItemDefinition]
}

struct CatalogMenuItemDefinition: Codable {
    let type: CatalogMenuItemType
    let title: String?
    let action: String?
    let alternateAction: String?
    let alternateActionWhen: CatalogCondition?
    let when: CatalogCondition?
    let children: [CatalogMenuItemDefinition]?
}

struct CatalogPackageSummary: Identifiable {
    let id: String
    let title: String
    let author: String
    let version: String
    let reviewStatus: String
    let description: String?
    let actionCount: Int
}

struct CatalogActionContext {
    let tile: Tile
    let modifierFlags: NSEvent.ModifierFlags
    let bundleIdentifier: String?
    let displayName: String
    let appBundlePath: String?
    let folderPath: String?
    let filePath: String?
    let isRunning: Bool
    let isPinned: Bool
    let canTogglePin: Bool
    let isFinder: Bool

    func value(for flag: CatalogContextFlag) -> Bool {
        switch flag {
        case .isRunning: return isRunning
        case .isPinned: return isPinned
        case .canTogglePin: return canTogglePin
        case .isFinder: return isFinder
        case .optionKey: return modifierFlags.contains(.option)
        }
    }

    func stringValue(for input: CatalogInputKey) -> String? {
        switch input {
        case .bundleIdentifier: return bundleIdentifier
        case .displayName: return displayName
        case .appBundlePath: return appBundlePath
        case .folderPath: return folderPath
        case .filePath: return filePath
        }
    }
}
