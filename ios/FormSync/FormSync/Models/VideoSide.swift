import Foundation

enum VideoSide: String, CaseIterable, Identifiable, Hashable, Codable {
    case left
    case right

    var id: String { rawValue }

    var setupLabel: String {
        self == .left ? "A" : "B"
    }

    var displayName: String {
        setupLabel
    }
}
