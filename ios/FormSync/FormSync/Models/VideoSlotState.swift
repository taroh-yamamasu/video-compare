import Foundation

struct VideoSlotState: Identifiable, Equatable {
    let side: VideoSide
    var video: VideoItem
    var currentTimeSeconds: Double = 0
    var syncPointSeconds: Double = 0
    var hasSyncPoint = false
    var viewScale: Double = 1
    var viewOffsetX: Double = 0
    var viewOffsetY: Double = 0
    var isPlaying = false

    var id: VideoSide { side }

    var label: String {
        "\(String(localized: "Video")) \(side.setupLabel)"
    }
}

struct OverlayTransform: Equatable, Hashable, Codable {
    var opacity: Double = 0.5
    var translateX: Double = 0
    var translateY: Double = 0
    var scale: Double = 1
    var rotationDegrees: Double = 0

    init(
        opacity: Double = 0.5,
        translateX: Double = 0,
        translateY: Double = 0,
        scale: Double = 1,
        rotationDegrees: Double = 0
    ) {
        self.opacity = opacity
        self.translateX = translateX
        self.translateY = translateY
        self.scale = scale
        self.rotationDegrees = rotationDegrees
    }

    private enum CodingKeys: String, CodingKey {
        case opacity
        case translateX
        case translateY
        case scale
        case rotationDegrees
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.5
        translateX = try container.decodeIfPresent(Double.self, forKey: .translateX) ?? 0
        translateY = try container.decodeIfPresent(Double.self, forKey: .translateY) ?? 0
        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1
        rotationDegrees = try container.decodeIfPresent(Double.self, forKey: .rotationDegrees) ?? 0
    }
}

struct OverlaySettings: Equatable, Hashable, Codable {
    var editingSide: VideoSide = .right
    var leftTransform = OverlayTransform(opacity: 1)
    var rightTransform = OverlayTransform()

    func transform(for side: VideoSide) -> OverlayTransform {
        side == .left ? leftTransform : rightTransform
    }

    mutating func setTransform(_ transform: OverlayTransform, for side: VideoSide) {
        switch side {
        case .left:
            leftTransform = transform
        case .right:
            rightTransform = transform
        }
    }
}

enum CompareMode: String, Equatable, Hashable, Codable {
    case setup
    case synced
}
