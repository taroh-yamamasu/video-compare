import Foundation

enum EntitlementState: Equatable {
    case free
    case pro
}

enum AccessLevel: Equatable {
    case limited
    case fullTrial
    case pro
}

struct TrialState: Equatable {
    static let totalUses = 3

    let usedUses: Int

    var remainingUses: Int {
        max(Self.totalUses - usedUses, 0)
    }

    var hasRemainingUses: Bool {
        remainingUses > 0
    }
}

enum ProFeature: String, Identifiable, Hashable {
    case overlay
    case slowPlayback
    case loop
    case frameStep
    case watermarkFreeImageExport
    case highResolutionExport
    case videoExport
    case multipleHistory

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .overlay:
            return String(localized: "Overlay Comparison")
        case .slowPlayback:
            return String(localized: "Slow Playback")
        case .loop:
            return String(localized: "Loop Playback")
        case .frameStep:
            return String(localized: "Frame Step")
        case .watermarkFreeImageExport:
            return String(localized: "Watermark-Free Export")
        case .highResolutionExport:
            return String(localized: "1080p Export")
        case .videoExport:
            return String(localized: "Video Export")
        case .multipleHistory:
            return String(localized: "Multiple Comparisons")
        }
    }

    var message: String {
        switch self {
        case .overlay:
            return String(localized: "Unlock overlay mode with position, scale, and rotation controls.")
        case .slowPlayback:
            return String(localized: "Use 0.25x, 0.5x, and 0.75x slow playback with PRO.")
        case .loop:
            return String(localized: "Repeat a selected section for detailed review with PRO.")
        case .frameStep:
            return String(localized: "Use precise frame steps such as 1/60, 1/30, and 1/2 second with PRO.")
        case .watermarkFreeImageExport:
            return String(localized: "Save and share images without the KinePair watermark with PRO.")
        case .highResolutionExport:
            return String(localized: "Unlock high-quality 1080p image and video export with PRO.")
        case .videoExport:
            return String(localized: "Save and share the current comparison as an MP4 video.")
        case .multipleHistory:
            return String(localized: "Keep multiple comparisons on your device and resume them later.")
        }
    }
}
