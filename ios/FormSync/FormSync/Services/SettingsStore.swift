import Foundation

struct SettingsStore {
    private enum Key {
        static let lastPlaybackRate = "lastPlaybackRate"
        static let lastDisplayMode = "lastDisplayMode"
        static let hasSeenOnboarding = "hasSeenOnboarding"
        static let hasRequestedReview = "hasRequestedReview"
        static let pendingReviewRequest = "pendingReviewRequest"
        static let completedComparisonCount = "completedComparisonCount"
        static let hasSeenV13UpdateNotice = "hasSeenV13UpdateNotice"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastPlaybackRate: PlaybackRate {
        get {
            let rawValue = defaults.float(forKey: Key.lastPlaybackRate)
            return PlaybackRate(rawValue: rawValue) ?? .normal
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.lastPlaybackRate)
        }
    }

    var lastDisplayMode: DisplayMode {
        get {
            guard let rawValue = defaults.string(forKey: Key.lastDisplayMode) else {
                return .sideBySide
            }

            return DisplayMode(rawValue: rawValue) ?? .sideBySide
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.lastDisplayMode)
        }
    }

    var hasSeenOnboarding: Bool {
        get {
            defaults.bool(forKey: Key.hasSeenOnboarding)
        }
        set {
            defaults.set(newValue, forKey: Key.hasSeenOnboarding)
        }
    }

    var shouldShowV13UpdateNotice: Bool {
        hasSeenOnboarding && !defaults.bool(forKey: Key.hasSeenV13UpdateNotice)
    }

    func markV13UpdateNoticeSeen() {
        defaults.set(true, forKey: Key.hasSeenV13UpdateNotice)
    }

    func resetComparisonDefaults() {
        defaults.removeObject(forKey: Key.lastPlaybackRate)
        defaults.removeObject(forKey: Key.lastDisplayMode)
    }

    func markOnboardingSeen() {
        defaults.set(true, forKey: Key.hasSeenOnboarding)
    }

    func markComparisonCompletedForReview() {
        guard !defaults.bool(forKey: Key.hasRequestedReview) else {
            return
        }

        let completedCount = defaults.integer(forKey: Key.completedComparisonCount) + 1
        defaults.set(completedCount, forKey: Key.completedComparisonCount)

        if completedCount >= 3 {
            defaults.set(true, forKey: Key.pendingReviewRequest)
        }
    }

    func consumePendingReviewRequest() -> Bool {
        guard defaults.bool(forKey: Key.pendingReviewRequest),
              defaults.integer(forKey: Key.completedComparisonCount) >= 3,
              !defaults.bool(forKey: Key.hasRequestedReview) else {
            return false
        }

        defaults.set(false, forKey: Key.pendingReviewRequest)
        defaults.set(true, forKey: Key.hasRequestedReview)
        return true
    }
}

struct CompareSessionStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private let metadataFileName = "session.json"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func listSessions() throws -> [CompareSession] {
        try ensureSessionsDirectory()

        let urls = try fileManager.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let sessions = urls.compactMap { directoryURL -> CompareSession? in
            let metadataURL = directoryURL.appendingPathComponent(metadataFileName)
            guard fileManager.fileExists(atPath: metadataURL.path) else {
                return nil
            }

            do {
                let data = try Data(contentsOf: metadataURL)
                return try decoder.decode(CompareSession.self, from: data)
            } catch {
                return nil
            }
        }

        return sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    func createSession(left: VideoItem, right: VideoItem, title: String? = nil) throws -> CompareSession {
        let id = UUID()
        let now = Date()
        let directoryURL = sessionDirectory(for: id)

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let persistedLeft = try copyVideoToSession(left, sessionID: id, side: .left)
            let persistedRight = try copyVideoToSession(right, sessionID: id, side: .right)
            let session = CompareSession(
                id: id,
                createdAt: now,
                updatedAt: now,
                title: title ?? defaultTitle(left: left, right: right, createdAt: now),
                leftSlot: CompareSessionSlot(video: sessionVideo(from: persistedLeft)),
                rightSlot: CompareSessionSlot(video: sessionVideo(from: persistedRight)),
                settings: CompareSettings(),
                overlaySettings: OverlaySettings(),
                compareMode: .setup,
                timelineSeconds: 0
            )
            try save(session)
            return session
        } catch {
            try? fileManager.removeItem(at: directoryURL)
            throw AppError.sessionSaveFailed
        }
    }

    func loadedPair(for session: CompareSession) throws -> LoadedVideoPair {
        let leftVideo = try videoItem(from: session.leftSlot.video, sessionID: session.id)
        let rightVideo = try videoItem(from: session.rightSlot.video, sessionID: session.id)

        return LoadedVideoPair(
            left: leftVideo,
            right: rightVideo,
            session: session,
            ownsTemporaryVideos: false
        )
    }

    func copyVideoToSession(
        _ video: VideoItem,
        sessionID: UUID,
        side: VideoSide,
        replacing replacedFileName: String? = nil
    ) throws -> VideoItem {
        let directoryURL = sessionDirectory(for: sessionID)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let fileExtension = video.url.pathExtension.isEmpty ? "mov" : video.url.pathExtension
        let destinationURL = directoryURL
            .appendingPathComponent("\(side.rawValue)-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)

        if TemporaryFileCleanup.isManagedTemporaryFile(video.url) {
            do {
                try fileManager.moveItem(at: video.url, to: destinationURL)
            } catch {
                try fileManager.copyItem(at: video.url, to: destinationURL)
                try? fileManager.removeItem(at: video.url)
            }
        } else {
            try fileManager.copyItem(at: video.url, to: destinationURL)
        }

        if let replacedFileName, replacedFileName != destinationURL.lastPathComponent {
            let replacedURL = directoryURL.appendingPathComponent(replacedFileName)
            try? fileManager.removeItem(at: replacedURL)
        }

        return VideoItem(
            id: video.id,
            url: destinationURL,
            fileName: video.fileName,
            durationSeconds: video.durationSeconds,
            isReady: video.isReady
        )
    }

    func save(_ session: CompareSession) throws {
        let directoryURL = sessionDirectory(for: session.id)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode(session)
        try data.write(to: metadataURL(for: session.id), options: [.atomic])
    }

    func rename(_ session: CompareSession, to title: String) throws {
        var renamedSession = session
        renamedSession.title = title
        renamedSession.updatedAt = Date()
        try save(renamedSession)
    }

    func delete(_ session: CompareSession) throws {
        try fileManager.removeItem(at: sessionDirectory(for: session.id))
    }

    func enforceFreeHistoryLimit(keeping keptSessionID: UUID, limit: Int = 1) throws {
        let sessions = try listSessions()
            .filter { $0.id != keptSessionID }
            .filter { !$0.isTrialHistory }

        for session in sessions.dropFirst(max(limit - 1, 0)) {
            try? delete(session)
        }
    }

    private var sessionsDirectory: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FormSync", isDirectory: true)
            .appendingPathComponent("Sessions", isDirectory: true)
    }

    private func ensureSessionsDirectory() throws {
        try fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    }

    private func sessionDirectory(for id: UUID) -> URL {
        sessionsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func metadataURL(for id: UUID) -> URL {
        sessionDirectory(for: id).appendingPathComponent(metadataFileName)
    }

    private func videoItem(from video: CompareSessionVideo, sessionID: UUID) throws -> VideoItem {
        let url = sessionDirectory(for: sessionID).appendingPathComponent(video.fileName)
        guard fileManager.fileExists(atPath: url.path) else {
            throw AppError.sessionLoadFailed
        }

        return VideoItem(
            url: url,
            fileName: video.originalFileName,
            durationSeconds: video.durationSeconds,
            isReady: true
        )
    }

    private func sessionVideo(from video: VideoItem) -> CompareSessionVideo {
        CompareSessionVideo(
            fileName: video.url.lastPathComponent,
            originalFileName: video.fileName,
            durationSeconds: video.durationSeconds
        )
    }

    private func defaultTitle(left: VideoItem, right: VideoItem, createdAt: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return L10n.format("%@ Comparison", formatter.string(from: createdAt))
    }
}
