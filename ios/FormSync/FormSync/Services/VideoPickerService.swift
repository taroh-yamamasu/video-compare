import AVFoundation
import CoreTransferable
import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct VideoPickerService {
    func loadVideo(from item: PhotosPickerItem) async throws -> VideoItem {
        guard let file = try await item.loadTransferable(type: PickedVideoFile.self) else {
            throw AppError.videoLoadFailed
        }

        return try await loadVideo(
            at: file.url,
            fileName: file.url.lastPathComponent,
            removesTemporaryFileOnFailure: true
        )
    }

    private func loadVideo(
        at url: URL,
        fileName: String,
        removesTemporaryFileOnFailure: Bool
    ) async throws -> VideoItem {
        do {
            let asset = AVURLAsset(url: url)
            let isPlayable = try await asset.load(.isPlayable)
            guard isPlayable else {
                throw AppError.unsupportedVideo
            }

            let duration = try await asset.load(.duration)
            let seconds = duration.seconds
            guard seconds.isFinite, seconds > 0 else {
                throw AppError.videoLoadFailed
            }

            return VideoItem(
                url: url,
                fileName: fileName,
                durationSeconds: seconds,
                isReady: true
            )
        } catch {
            if removesTemporaryFileOnFailure {
                TemporaryFileCleanup.removeIfTemporary(url)
            }

            throw error
        }
    }
}

enum TemporaryFileCleanup {
    static func removeIfTemporary(_ url: URL) {
        guard isManagedTemporaryFile(url) else {
            return
        }

        try? FileManager.default.removeItem(at: url)
    }

    static func removeTemporaryVideos(_ videos: [VideoItem]) {
        var removedURLs = Set<URL>()
        for video in videos where removedURLs.insert(video.url).inserted {
            removeIfTemporary(video.url)
        }
    }

    static func isManagedTemporaryFile(_ url: URL) -> Bool {
        guard url.isFileURL else {
            return false
        }

        let standardizedURL = url.standardizedFileURL
        let temporaryDirectory = FileManager.default.temporaryDirectory.standardizedFileURL
        guard standardizedURL.path.hasPrefix(temporaryDirectory.path) else {
            return false
        }

        return standardizedURL.lastPathComponent.hasPrefix("FormSync-")
    }
}

private struct PickedVideoFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { file in
            SentTransferredFile(file.url)
        } importing: { received in
            let copiedURL = try copyToTemporaryDirectory(received.file)
            return PickedVideoFile(url: copiedURL)
        }
    }

    private static func copyToTemporaryDirectory(_ sourceURL: URL) throws -> URL {
        let fileExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FormSync-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }
}
