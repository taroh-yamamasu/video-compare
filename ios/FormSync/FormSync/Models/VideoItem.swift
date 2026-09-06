import Foundation

struct VideoItem: Identifiable, Equatable, Hashable {
    let id: UUID
    let url: URL
    var fileName: String
    var durationSeconds: Double
    var isReady: Bool

    init(
        id: UUID = UUID(),
        url: URL,
        fileName: String,
        durationSeconds: Double = 0,
        isReady: Bool = false
    ) {
        self.id = id
        self.url = url
        self.fileName = fileName
        self.durationSeconds = durationSeconds
        self.isReady = isReady
    }
}

struct LoadedVideoPair: Identifiable, Hashable {
    let id = UUID()
    let left: VideoItem
    let right: VideoItem
    var session: CompareSession?
    var ownsTemporaryVideos = true
    var isSample = false
}

struct CompareSession: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var createdAt: Date
    var updatedAt: Date
    var title: String
    var leftSlot: CompareSessionSlot
    var rightSlot: CompareSessionSlot
    var settings: CompareSettings
    var overlaySettings: OverlaySettings
    var compareMode: CompareMode
    var timelineSeconds: Double
    var trialUseConsumed: Bool? = nil

    var hasSyncPoints: Bool {
        leftSlot.hasSyncPoint && rightSlot.hasSyncPoint
    }

    var isTrialHistory: Bool {
        trialUseConsumed == true
    }
}

struct CompareSessionSlot: Codable, Equatable, Hashable {
    var video: CompareSessionVideo
    var currentTimeSeconds: Double
    var syncPointSeconds: Double
    var hasSyncPoint: Bool
    var viewScale: Double
    var viewOffsetX: Double
    var viewOffsetY: Double

    init(
        video: CompareSessionVideo,
        currentTimeSeconds: Double = 0,
        syncPointSeconds: Double = 0,
        hasSyncPoint: Bool = false,
        viewScale: Double = 1,
        viewOffsetX: Double = 0,
        viewOffsetY: Double = 0
    ) {
        self.video = video
        self.currentTimeSeconds = currentTimeSeconds
        self.syncPointSeconds = syncPointSeconds
        self.hasSyncPoint = hasSyncPoint
        self.viewScale = viewScale
        self.viewOffsetX = viewOffsetX
        self.viewOffsetY = viewOffsetY
    }

    init(slot: VideoSlotState) {
        self.init(
            video: CompareSessionVideo(
                fileName: slot.video.url.lastPathComponent,
                originalFileName: slot.video.fileName,
                durationSeconds: slot.video.durationSeconds
            ),
            currentTimeSeconds: slot.currentTimeSeconds,
            syncPointSeconds: slot.syncPointSeconds,
            hasSyncPoint: slot.hasSyncPoint,
            viewScale: slot.viewScale,
            viewOffsetX: slot.viewOffsetX,
            viewOffsetY: slot.viewOffsetY
        )
    }
}

struct CompareSessionVideo: Codable, Equatable, Hashable {
    var fileName: String
    var originalFileName: String
    var durationSeconds: Double
}
