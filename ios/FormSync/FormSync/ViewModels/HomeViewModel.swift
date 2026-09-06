import Foundation
import PhotosUI
import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var selectedItems: [PhotosPickerItem] = []
    @Published var loadedPair: LoadedVideoPair?
    @Published var sessions: [CompareSession] = []
    @Published var isLoading = false
    @Published var loadingMessage: String?
    @Published var errorMessage: String?

    private let videoPickerService: VideoPickerService
    private let sessionStore: CompareSessionStore
    private var settingsStore: SettingsStore
    private var hasExpandedHistoryAccess = false

    init(
        videoPickerService: VideoPickerService = VideoPickerService(),
        sessionStore: CompareSessionStore = CompareSessionStore(),
        settingsStore: SettingsStore = SettingsStore()
    ) {
        self.videoPickerService = videoPickerService
        self.sessionStore = sessionStore
        self.settingsStore = settingsStore
        refreshSessions()
    }

    func loadSelectedVideos(isProUnlocked: Bool) async {
        guard !selectedItems.isEmpty else {
            errorMessage = nil
            return
        }

        guard selectedItems.count == 2 else {
            errorMessage = String(localized: "Choose one more video.")
            return
        }

        isLoading = true
        loadingMessage = String(localized: "Loading videos…")
        errorMessage = nil
        var loadedVideos: [VideoItem] = []

        do {
            async let firstResult = loadVideoResult(from: selectedItems[0])
            async let secondResult = loadVideoResult(from: selectedItems[1])
            let (firstLoaded, secondLoaded) = await (firstResult, secondResult)
            let results = [firstLoaded, secondLoaded]

            for result in results {
                if case .success(let video) = result {
                    loadedVideos.append(video)
                }
            }

            for result in results {
                if case .failure(let error) = result {
                    throw error
                }
            }

            let firstVideo = loadedVideos[0]
            let secondVideo = loadedVideos[1]
            loadingMessage = String(localized: "Saving comparison…")
            let session = try sessionStore.createSession(left: firstVideo, right: secondVideo)
            if !isProUnlocked {
                try sessionStore.enforceFreeHistoryLimit(keeping: session.id)
            }
            loadedPair = try sessionStore.loadedPair(for: session)
            TemporaryFileCleanup.removeTemporaryVideos(loadedVideos)
            selectedItems = []
            refreshSessions()
            markOnboardingSeen()
        } catch let error as AppError {
            TemporaryFileCleanup.removeTemporaryVideos(loadedVideos)
            errorMessage = error.errorDescription
        } catch {
            TemporaryFileCleanup.removeTemporaryVideos(loadedVideos)
            errorMessage = AppError.videoLoadFailed.errorDescription
        }

        loadingMessage = nil
        isLoading = false
    }

    func loadSampleVideos() {
        errorMessage = nil

        guard let leftURL = sampleVideoURL(named: "sample-a"),
              let rightURL = sampleVideoURL(named: "sample-b") else {
            errorMessage = AppError.sampleUnavailable.errorDescription
            return
        }

        loadedPair = LoadedVideoPair(
            left: VideoItem(
                url: leftURL,
                fileName: String(localized: "Sample A"),
                durationSeconds: 6,
                isReady: true
            ),
            right: VideoItem(
                url: rightURL,
                fileName: String(localized: "Sample B"),
                durationSeconds: 6,
                isReady: true
            ),
            ownsTemporaryVideos: false,
            isSample: true
        )

        markOnboardingSeen()
    }

    private func sampleVideoURL(named name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "mp4")
            ?? Bundle.main.url(forResource: name, withExtension: "mp4", subdirectory: "SampleVideos")
    }

    func openSession(_ session: CompareSession) async {
        isLoading = true
        loadingMessage = String(localized: "Opening comparison…")
        errorMessage = nil

        do {
            loadedPair = try sessionStore.loadedPair(for: session)
            markOnboardingSeen()
        } catch let error as AppError {
            errorMessage = error.errorDescription
            refreshSessions()
        } catch {
            errorMessage = AppError.sessionLoadFailed.errorDescription
            refreshSessions()
        }

        loadingMessage = nil
        isLoading = false
    }

    func deleteSession(_ session: CompareSession) {
        do {
            try sessionStore.delete(session)
            refreshSessions()
            errorMessage = nil
        } catch {
            errorMessage = AppError.sessionDeleteFailed.errorDescription
        }
    }

    func renameSession(_ session: CompareSession, title: String, hasExpandedHistoryAccess: Bool) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return
        }

        do {
            try sessionStore.rename(session, to: trimmedTitle)
            refreshSessions(hasExpandedHistoryAccess: hasExpandedHistoryAccess)
            errorMessage = nil
        } catch {
            errorMessage = AppError.sessionSaveFailed.errorDescription
        }
    }

    func refreshSessions(hasExpandedHistoryAccess: Bool? = nil) {
        if let hasExpandedHistoryAccess {
            self.hasExpandedHistoryAccess = hasExpandedHistoryAccess
        }

        do {
            let allSessions = try sessionStore.listSessions()
            sessions = self.hasExpandedHistoryAccess ? allSessions : Array(allSessions.prefix(1))
        } catch {
            sessions = []
        }
    }

    private func markOnboardingSeen() {
        settingsStore.hasSeenOnboarding = true
    }

    private func loadVideoResult(from item: PhotosPickerItem) async -> Result<VideoItem, Error> {
        do {
            return .success(try await videoPickerService.loadVideo(from: item))
        } catch {
            return .failure(error)
        }
    }
}
