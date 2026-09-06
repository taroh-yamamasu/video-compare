import Foundation

enum AppError: LocalizedError, Equatable {
    case videoSelectionCancelled
    case videoLoadFailed
    case unsupportedVideo
    case playerFailed
    case noComparableRange
    case loopMissingStart
    case loopMissingEnd
    case invalidLoopRange
    case loopRangeOutOfBounds
    case imageGenerationFailed
    case videoExportFailed
    case exportCancelled
    case exportRangeUnavailable
    case insufficientStorage
    case photoPermissionDenied
    case photoSaveFailed
    case playbackRateChangeFailed
    case sessionSaveFailed
    case sessionLoadFailed
    case sessionDeleteFailed
    case sampleUnavailable

    var errorDescription: String? {
        switch self {
        case .videoSelectionCancelled:
            return nil
        case .videoLoadFailed:
            return String(localized: "The video could not be loaded. Choose another video.")
        case .unsupportedVideo:
            return String(localized: "This video format is not supported.")
        case .playerFailed:
            return String(localized: "The video could not be played.")
        case .noComparableRange:
            return String(localized: "There is no comparable range with the current sync points.")
        case .loopMissingStart:
            return String(localized: "Set the loop start point.")
        case .loopMissingEnd:
            return String(localized: "Set the loop end point.")
        case .invalidLoopRange:
            return String(localized: "Set the loop end after the start.")
        case .loopRangeOutOfBounds:
            return String(localized: "Set the loop range again.")
        case .imageGenerationFailed:
            return String(localized: "The image could not be created. Try another position.")
        case .videoExportFailed:
            return String(localized: "The video could not be exported. Try another range.")
        case .exportCancelled:
            return String(localized: "Export was cancelled.")
        case .exportRangeUnavailable:
            return String(localized: "Choose the export range again.")
        case .insufficientStorage:
            return String(localized: "There is not enough storage to export. Free up space and try again.")
        case .photoPermissionDenied:
            return String(localized: "KinePair cannot save to Photos. Allow Photos access in Settings.")
        case .photoSaveFailed:
            return String(localized: "The export could not be saved to Photos. Check storage and your photo library.")
        case .playbackRateChangeFailed:
            return String(localized: "Playback speed could not be changed.")
        case .sessionSaveFailed:
            return String(localized: "The comparison could not be saved. Check available storage.")
        case .sessionLoadFailed:
            return String(localized: "The comparison could not be opened. A saved video may be missing.")
        case .sessionDeleteFailed:
            return String(localized: "The comparison could not be deleted.")
        case .sampleUnavailable:
            return String(localized: "The sample could not be opened. Restart KinePair and try again.")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .photoPermissionDenied:
            return String(localized: "Open Settings > KinePair > Photos and allow adding photos.")
        case .insufficientStorage:
            return String(localized: "For longer videos, try 720p or export a loop range.")
        case .exportRangeUnavailable:
            return String(localized: "To export a loop, set its start and end points first.")
        case .videoExportFailed:
            return String(localized: "Try a shorter range or 720p.")
        case .imageGenerationFailed:
            return String(localized: "Seek to another position and try again.")
        case .sessionSaveFailed:
            return String(localized: "Free up storage on this device and try again.")
        case .sessionLoadFailed:
            return String(localized: "Delete this history item and choose the videos again.")
        case .sampleUnavailable:
            return String(localized: "If the problem continues, update KinePair from the App Store.")
        default:
            return nil
        }
    }
}
