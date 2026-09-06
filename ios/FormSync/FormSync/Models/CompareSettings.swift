import CoreGraphics
import Foundation

enum PlaybackRate: Float, CaseIterable, Identifiable, Hashable, Codable {
    case quarter = 0.25
    case half = 0.5
    case threeQuarter = 0.75
    case normal = 1.0
    case oneAndQuarter = 1.25

    var id: Float { rawValue }

    var label: String {
        switch self {
        case .quarter:
            return "0.25x"
        case .half:
            return "0.5x"
        case .threeQuarter:
            return "0.75x"
        case .normal:
            return "1x"
        case .oneAndQuarter:
            return "1.25x"
        }
    }

    var requiresPro: Bool {
        rawValue < PlaybackRate.normal.rawValue
    }
}

struct LoopRange: Equatable, Hashable, Codable {
    var startSeconds: Double?
    var endSeconds: Double?
    var isEnabled: Bool = false

    var isComplete: Bool {
        guard let startSeconds, let endSeconds else {
            return false
        }

        return endSeconds > startSeconds
    }
}

struct SyncSettings: Equatable, Hashable, Codable {
    var leftOffsetSeconds: Double = 0
    var rightOffsetSeconds: Double = 0

    func offset(for side: VideoSide) -> Double {
        side == .left ? leftOffsetSeconds : rightOffsetSeconds
    }

    mutating func setOffset(_ seconds: Double, for side: VideoSide) {
        switch side {
        case .left:
            leftOffsetSeconds = seconds
        case .right:
            rightOffsetSeconds = seconds
        }
    }
}

enum DisplayMode: String, CaseIterable, Identifiable, Hashable, Codable {
    case sideBySide
    case stacked
    case overlayPreview

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sideBySide:
            return String(localized: "Side by Side")
        case .stacked:
            return String(localized: "Stacked")
        case .overlayPreview:
            return String(localized: "Overlay")
        }
    }

    var requiresPro: Bool {
        self == .overlayPreview
    }
}

struct CompareSettings: Codable, Equatable, Hashable {
    var playbackRate: PlaybackRate = .normal
    var displayMode: DisplayMode = .sideBySide
    var loopRange: LoopRange = LoopRange()
    var syncSettings: SyncSettings = SyncSettings()
    var stepSeconds: Double = 0.1
}

enum ExportFormat: String, CaseIterable, Identifiable, Hashable {
    case image
    case video

    var id: String { rawValue }

    var label: String {
        switch self {
        case .image:
            return String(localized: "Image")
        case .video:
            return String(localized: "Video")
        }
    }
}

enum ExportRange: String, CaseIterable, Identifiable, Hashable {
    case currentFrame
    case full
    case loop

    var id: String { rawValue }

    var label: String {
        switch self {
        case .currentFrame:
            return String(localized: "Current Frame")
        case .full:
            return String(localized: "Full Timeline")
        case .loop:
            return String(localized: "Loop Range")
        }
    }
}

enum ExportResolution: String, CaseIterable, Identifiable, Hashable {
    case p720
    case p1080

    var id: String { rawValue }

    var label: String {
        switch self {
        case .p720:
            return "720p"
        case .p1080:
            return "1080p"
        }
    }

    var requiresPro: Bool {
        self == .p1080
    }

    func outputSize(for layout: DisplayMode) -> CGSize {
        switch (self, layout) {
        case (.p720, .stacked):
            return CGSize(width: 720, height: 1280)
        case (.p1080, .stacked):
            return CGSize(width: 1080, height: 1920)
        case (.p720, _):
            return CGSize(width: 1280, height: 720)
        case (.p1080, _):
            return CGSize(width: 1920, height: 1080)
        }
    }
}

enum ExportAudioSource: String, CaseIterable, Identifiable, Hashable {
    case none
    case left
    case right

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:
            return String(localized: "None")
        case .left:
            return String(localized: "Left")
        case .right:
            return String(localized: "Right")
        }
    }
}

enum ExportDestination: String, CaseIterable, Identifiable, Hashable {
    case photoLibrary
    case share

    var id: String { rawValue }
}

struct ExportOptions: Equatable {
    var format: ExportFormat = .image
    var range: ExportRange = .currentFrame
    var resolution: ExportResolution = .p720
    var audioSource: ExportAudioSource = .none
    var includesWatermark: Bool = false
}

struct ExportRequest {
    let leftURL: URL
    let rightURL: URL
    let timelineSeconds: Double
    let timelineRange: ClosedRange<Double>
    let loopRange: LoopRange
    let syncSettings: SyncSettings
    let layout: DisplayMode
    let overlaySettings: OverlaySettings
    let options: ExportOptions
    let outputSize: CGSize
}

struct ExportResult: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let format: ExportFormat
    let fileName: String
}

struct ExportProgress: Equatable {
    var fraction: Double
    var message: String

    static let idle = ExportProgress(fraction: 0, message: "")
}
