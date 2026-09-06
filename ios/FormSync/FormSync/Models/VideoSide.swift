import Foundation

enum VideoSide: String, CaseIterable, Identifiable, Hashable, Codable {
    case left
    case right

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .left:
            return String(localized: "Left")
        case .right:
            return String(localized: "Right")
        }
    }
}
