import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import Photos
import UIKit

struct ExportService {
    func export(
        _ request: ExportRequest,
        progressHandler: @escaping @MainActor (ExportProgress) -> Void
    ) async throws -> ExportResult {
        do {
            switch request.options.format {
            case .image:
                return try await exportImage(request, progressHandler: progressHandler)
            case .video:
                return try await exportVideo(request, progressHandler: progressHandler)
            }
        } catch is CancellationError {
            throw AppError.exportCancelled
        } catch let error as AppError {
            throw error
        } catch {
            switch request.options.format {
            case .image:
                throw AppError.imageGenerationFailed
            case .video:
                throw AppError.videoExportFailed
            }
        }
    }

    func saveToPhotoLibrary(_ result: ExportResult) async throws {
        let authorizationStatus = await photoAddAuthorizationStatus()
        guard canSaveToPhotoLibrary(with: authorizationStatus) else {
            throw AppError.photoPermissionDenied
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let resourceType: PHAssetResourceType = result.format == .image ? .photo : .video
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = result.fileName
                request.addResource(with: resourceType, fileURL: result.url, options: options)
            }
        } catch {
            throw AppError.photoSaveFailed
        }
    }
}

private func photoAddAuthorizationStatus() async -> PHAuthorizationStatus {
    let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    guard currentStatus == .notDetermined else {
        return currentStatus
    }

    return await withCheckedContinuation { continuation in
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            continuation.resume(returning: status)
        }
    }
}

private func canSaveToPhotoLibrary(with status: PHAuthorizationStatus) -> Bool {
    switch status {
    case .authorized, .limited:
        return true
    case .notDetermined, .restricted, .denied:
        return false
    @unknown default:
        return false
    }
}

private let exportFrameRate: Int32 = 30

private enum ExportContentMode {
    case fit
    case fill
}

private enum ExportDrawAlignment {
    case center
    case leading
    case trailing
    case top
    case bottom
}

private func exportImage(
    _ request: ExportRequest,
    progressHandler: @escaping @MainActor (ExportProgress) -> Void
) async throws -> ExportResult {
    await progressHandler(ExportProgress(fraction: 0.05, message: String(localized: "Creating image…")))

    let image = try await Task.detached(priority: .userInitiated) {
        try Task.checkCancellation()
        let leftAsset = AVURLAsset(url: request.leftURL)
        let rightAsset = AVURLAsset(url: request.rightURL)
        let leftDuration = try await leftAsset.load(.duration).seconds
        let rightDuration = try await rightAsset.load(.duration).seconds
        let leftTime = clampedTime(
            request.timelineSeconds - request.syncSettings.leftOffsetSeconds,
            durationSeconds: leftDuration
        )
        let rightTime = clampedTime(
            request.timelineSeconds - request.syncSettings.rightOffsetSeconds,
            durationSeconds: rightDuration
        )
        let maximumFrameSize = sourceFrameMaximumSize(for: request)
        let leftFrame = try frameImage(from: leftAsset, at: leftTime, exact: true, maximumSize: maximumFrameSize)
        let rightFrame = try frameImage(from: rightAsset, at: rightTime, exact: true, maximumSize: maximumFrameSize)

        return compositeImage(
            leftFrame: leftFrame,
            rightFrame: rightFrame,
            layout: request.layout,
            overlaySettings: request.overlaySettings,
            outputSize: request.outputSize,
            includesWatermark: request.options.includesWatermark
        )
    }.value

    try Task.checkCancellation()
    guard let data = image.pngData() else {
        throw AppError.imageGenerationFailed
    }

    let url = temporaryExportURL(prefix: "KinePair", extension: "png")
    try? FileManager.default.removeItem(at: url)
    try data.write(to: url, options: [.atomic])
    await progressHandler(ExportProgress(fraction: 1, message: String(localized: "Image created.")))
    return ExportResult(url: url, format: .image, fileName: url.lastPathComponent)
}

private func exportVideo(
    _ request: ExportRequest,
    progressHandler: @escaping @MainActor (ExportProgress) -> Void
) async throws -> ExportResult {
    await progressHandler(ExportProgress(fraction: 0.02, message: String(localized: "Exporting video…")))

    let silentVideoURL = try await renderSilentVideo(request, progressHandler: progressHandler)
    try Task.checkCancellation()

    let finalURL: URL
    if request.options.audioSource == .none {
        finalURL = silentVideoURL
    } else {
        await progressHandler(ExportProgress(fraction: 0.92, message: String(localized: "Adding audio…")))
        do {
            finalURL = try await mergeAudio(videoURL: silentVideoURL, request: request)
            try? FileManager.default.removeItem(at: silentVideoURL)
        } catch {
            try? FileManager.default.removeItem(at: silentVideoURL)
            throw error
        }
    }

    await progressHandler(ExportProgress(fraction: 1, message: String(localized: "Video exported.")))
    return ExportResult(url: finalURL, format: .video, fileName: finalURL.lastPathComponent)
}

private func renderSilentVideo(
    _ request: ExportRequest,
    progressHandler: @escaping @MainActor (ExportProgress) -> Void
) async throws -> URL {
    let range = try timelineRange(for: request)
    let durationSeconds = range.upperBound - range.lowerBound
    guard durationSeconds > 0 else {
        throw AppError.exportRangeUnavailable
    }
    try ensureAvailableTemporaryStorage(
        durationSeconds: durationSeconds,
        outputSize: request.outputSize,
        includesAudio: request.options.audioSource != .none
    )

    let outputURL = temporaryExportURL(prefix: "KinePair-video", extension: "mp4")
    try? FileManager.default.removeItem(at: outputURL)

    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
    let width = Int(request.outputSize.width)
    let height = Int(request.outputSize.height)
    let outputSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: bitrate(for: request.outputSize),
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
        ]
    ]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
    input.expectsMediaDataInRealTime = false
    let sourceAttributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height
    ]
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: sourceAttributes
    )

    guard writer.canAdd(input) else {
        throw AppError.videoExportFailed
    }
    writer.add(input)

    let leftAsset = AVURLAsset(url: request.leftURL)
    let rightAsset = AVURLAsset(url: request.rightURL)
    let leftDuration = try await leftAsset.load(.duration).seconds
    let rightDuration = try await rightAsset.load(.duration).seconds
    let maximumFrameSize = sourceFrameMaximumSize(for: request)
    let leftGenerator = imageGenerator(for: leftAsset, exact: false, maximumSize: maximumFrameSize)
    let rightGenerator = imageGenerator(for: rightAsset, exact: false, maximumSize: maximumFrameSize)
    defer {
        leftGenerator.cancelAllCGImageGeneration()
        rightGenerator.cancelAllCGImageGeneration()
    }

    guard writer.startWriting() else {
        throw AppError.videoExportFailed
    }
    writer.startSession(atSourceTime: .zero)

    let frameCount = max(1, Int(ceil(durationSeconds * Double(exportFrameRate))))

    do {
        for frameIndex in 0..<frameCount {
            try Task.checkCancellation()

            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 5_000_000)
            }

            let frameTime = min(durationSeconds, Double(frameIndex) / Double(exportFrameRate))
            let timelineSeconds = range.lowerBound + frameTime
            let leftTime = clampedTime(
                timelineSeconds - request.syncSettings.leftOffsetSeconds,
                durationSeconds: leftDuration
            )
            let rightTime = clampedTime(
                timelineSeconds - request.syncSettings.rightOffsetSeconds,
                durationSeconds: rightDuration
            )
            let pixelBuffer = try autoreleasepool {
                let leftFrame = try frameImage(from: leftGenerator, at: leftTime)
                let rightFrame = try frameImage(from: rightGenerator, at: rightTime)
                let image = compositeImage(
                    leftFrame: leftFrame,
                    rightFrame: rightFrame,
                    layout: request.layout,
                    overlaySettings: request.overlaySettings,
                    outputSize: request.outputSize
                )
                guard let cgImage = image.cgImage else {
                    throw AppError.imageGenerationFailed
                }
                return try makePixelBuffer(from: cgImage, size: request.outputSize, adaptor: adaptor)
            }

            let presentationTime = CMTime(
                value: CMTimeValue(frameIndex),
                timescale: exportFrameRate
            )
            guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                throw AppError.videoExportFailed
            }

            if frameIndex % 10 == 0 || frameIndex == frameCount - 1 {
                let fraction = 0.05 + (Double(frameIndex + 1) / Double(frameCount)) * 0.85
                await progressHandler(ExportProgress(fraction: fraction, message: String(localized: "Exporting video…")))
            }
        }
    } catch {
        input.markAsFinished()
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: outputURL)
        throw error
    }

    input.markAsFinished()
    await finishWriting(writer)

    guard writer.status == .completed else {
        try? FileManager.default.removeItem(at: outputURL)
        throw AppError.videoExportFailed
    }

    return outputURL
}

private func mergeAudio(videoURL: URL, request: ExportRequest) async throws -> URL {
    let range = try timelineRange(for: request)
    let outputURL = temporaryExportURL(prefix: "KinePair-audio", extension: "mp4")
    try? FileManager.default.removeItem(at: outputURL)

    let composition = AVMutableComposition()
    let videoAsset = AVURLAsset(url: videoURL)
    let videoDuration = try await videoAsset.load(.duration)

    guard
        let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
        let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
    else {
        throw AppError.videoExportFailed
    }

    try compositionVideoTrack.insertTimeRange(
        CMTimeRange(start: .zero, duration: videoDuration),
        of: videoTrack,
        at: .zero
    )
    compositionVideoTrack.preferredTransform = try await videoTrack.load(.preferredTransform)

    let audioURL = request.options.audioSource == .left ? request.leftURL : request.rightURL
    let audioOffset = request.options.audioSource == .left
        ? request.syncSettings.leftOffsetSeconds
        : request.syncSettings.rightOffsetSeconds
    let audioAsset = AVURLAsset(url: audioURL)
    if
        let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
        let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
    {
        let sourceDuration = try await audioAsset.load(.duration).seconds
        let sourceStartSeconds = max(0, range.lowerBound - audioOffset)
        let availableSeconds = max(0, sourceDuration - sourceStartSeconds)
        let requestedSeconds = range.upperBound - range.lowerBound
        let audioDurationSeconds = min(availableSeconds, requestedSeconds)
        if audioDurationSeconds > 0 {
            try compositionAudioTrack.insertTimeRange(
                CMTimeRange(
                    start: CMTime(seconds: sourceStartSeconds, preferredTimescale: 600),
                    duration: CMTime(seconds: audioDurationSeconds, preferredTimescale: 600)
                ),
                of: audioTrack,
                at: .zero
            )
        }
    }

    guard let exportSession = AVAssetExportSession(
        asset: composition,
        presetName: AVAssetExportPresetHighestQuality
    ) else {
        throw AppError.videoExportFailed
    }
    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mp4
    exportSession.shouldOptimizeForNetworkUse = true

    let cancellationBox = ExportSessionCancellationBox(exportSession)
    do {
        try await withTaskCancellationHandler {
            await exportAsynchronously(exportSession)
            try Task.checkCancellation()
        } onCancel: {
            cancellationBox.session.cancelExport()
        }
    } catch {
        try? FileManager.default.removeItem(at: outputURL)
        throw error
    }

    guard exportSession.status == .completed else {
        try? FileManager.default.removeItem(at: outputURL)
        if exportSession.status == .cancelled {
            throw AppError.exportCancelled
        }
        throw AppError.videoExportFailed
    }

    return outputURL
}

private func timelineRange(for request: ExportRequest) throws -> ClosedRange<Double> {
    switch request.options.range {
    case .currentFrame:
        return request.timelineSeconds...request.timelineSeconds
    case .full:
        return request.timelineRange
    case .loop:
        guard
            request.loopRange.isEnabled,
            request.loopRange.isComplete,
            let start = request.loopRange.startSeconds,
            let end = request.loopRange.endSeconds
        else {
            throw AppError.exportRangeUnavailable
        }
        let lower = max(request.timelineRange.lowerBound, start)
        let upper = min(request.timelineRange.upperBound, end)
        guard upper > lower else {
            throw AppError.exportRangeUnavailable
        }
        return lower...upper
    }
}

private func imageGenerator(for asset: AVURLAsset, exact: Bool, maximumSize: CGSize? = nil) -> AVAssetImageGenerator {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    if let maximumSize, maximumSize.width > 0, maximumSize.height > 0 {
        generator.maximumSize = maximumSize
    }
    if exact {
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
    } else {
        let tolerance = CMTime(seconds: 1.0 / Double(exportFrameRate), preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
    }
    return generator
}

private func frameImage(
    from asset: AVURLAsset,
    at time: CMTime,
    exact: Bool,
    maximumSize: CGSize? = nil
) throws -> CGImage {
    try frameImage(from: imageGenerator(for: asset, exact: exact, maximumSize: maximumSize), at: time)
}

private func frameImage(from generator: AVAssetImageGenerator, at time: CMTime) throws -> CGImage {
    do {
        return try generator.copyCGImage(at: time, actualTime: nil)
    } catch {
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.12, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.12, preferredTimescale: 600)
        return try generator.copyCGImage(at: time, actualTime: nil)
    }
}

private func clampedTime(_ seconds: Double, durationSeconds: Double) -> CMTime {
    let upperBound = max(0, durationSeconds - 0.04)
    let clampedSeconds = min(max(0, seconds), upperBound)
    return CMTime(seconds: clampedSeconds, preferredTimescale: 600)
}

private func sourceFrameMaximumSize(for request: ExportRequest) -> CGSize {
    switch request.layout {
    case .sideBySide:
        return CGSize(width: request.outputSize.width / 2, height: request.outputSize.height)
    case .stacked:
        return CGSize(width: request.outputSize.width, height: request.outputSize.height / 2)
    case .overlayPreview:
        return request.outputSize
    }
}

private func ensureAvailableTemporaryStorage(
    durationSeconds: Double,
    outputSize: CGSize,
    includesAudio: Bool
) throws {
    let videoBytesPerSecond = Double(bitrate(for: outputSize)) / 8
    let audioBytesPerSecond = includesAudio ? 32_000.0 : 0
    let estimatedFinalBytes = Int64((videoBytesPerSecond + audioBytesPerSecond) * max(durationSeconds, 1))
    let temporaryMultiplier: Int64 = includesAudio ? 2 : 1
    let fixedHeadroom: Int64 = 96 * 1024 * 1024
    let requiredBytes = estimatedFinalBytes * temporaryMultiplier + fixedHeadroom

    let values = try FileManager.default.temporaryDirectory.resourceValues(
        forKeys: [.volumeAvailableCapacityForImportantUsageKey]
    )

    guard let availableBytes = values.volumeAvailableCapacityForImportantUsage else {
        return
    }

    if availableBytes < requiredBytes {
        throw AppError.insufficientStorage
    }
}

private func compositeImage(
    leftFrame: CGImage,
    rightFrame: CGImage,
    layout: DisplayMode,
    overlaySettings: OverlaySettings,
    outputSize: CGSize,
    includesWatermark: Bool = false
) -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: outputSize)
    return renderer.image { context in
        UIColor.black.setFill()
        context.fill(CGRect(origin: .zero, size: outputSize))

        switch layout {
        case .sideBySide:
            let halfWidth = outputSize.width / 2
            draw(
                leftFrame,
                in: CGRect(x: 0, y: 0, width: halfWidth, height: outputSize.height),
                context: context.cgContext,
                alignment: .trailing
            )
            draw(
                rightFrame,
                in: CGRect(x: halfWidth, y: 0, width: halfWidth, height: outputSize.height),
                context: context.cgContext,
                alignment: .leading
            )
        case .stacked:
            let halfHeight = outputSize.height / 2
            draw(
                leftFrame,
                in: CGRect(x: 0, y: 0, width: outputSize.width, height: halfHeight),
                context: context.cgContext,
                alignment: .bottom
            )
            draw(
                rightFrame,
                in: CGRect(x: 0, y: halfHeight, width: outputSize.width, height: halfHeight),
                context: context.cgContext,
                alignment: .top
            )
        case .overlayPreview:
            let rect = CGRect(origin: .zero, size: outputSize)
            drawOverlay(leftFrame, in: rect, transform: overlaySettings.leftTransform, context: context.cgContext)
            drawOverlay(rightFrame, in: rect, transform: overlaySettings.rightTransform, context: context.cgContext)
        }

        if includesWatermark {
            drawWatermark(in: CGRect(origin: .zero, size: outputSize))
        }
    }
}

private func drawWatermark(in rect: CGRect) {
    let text = "KinePair"
    let scale = min(rect.width, rect.height) / 720
    let horizontalPadding = max(16, 22 * scale)
    let verticalPadding = max(9, 12 * scale)
    let cornerRadius = max(9, 12 * scale)
    let font = UIFont.systemFont(ofSize: max(20, 26 * scale), weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: UIColor.white.withAlphaComponent(0.94)
    ]
    let textSize = text.size(withAttributes: attributes)
    let pillSize = CGSize(
        width: textSize.width + horizontalPadding * 2,
        height: textSize.height + verticalPadding * 2
    )
    let origin = CGPoint(
        x: rect.maxX - pillSize.width - max(20, 28 * scale),
        y: rect.maxY - pillSize.height - max(20, 28 * scale)
    )
    let pillRect = CGRect(origin: origin, size: pillSize)
    let path = UIBezierPath(roundedRect: pillRect, cornerRadius: cornerRadius)
    UIColor.black.withAlphaComponent(0.48).setFill()
    path.fill()

    text.draw(
        in: CGRect(
            x: pillRect.minX + horizontalPadding,
            y: pillRect.minY + verticalPadding,
            width: textSize.width,
            height: textSize.height
        ),
        withAttributes: attributes
    )
}

private func drawOverlay(
    _ image: CGImage,
    in rect: CGRect,
    transform: OverlayTransform,
    context: CGContext
) {
    let exportScale = min(rect.width, rect.height) / 390
    let translation = CGSize(
        width: transform.translateX * exportScale,
        height: transform.translateY * exportScale
    )
    draw(
        image,
        in: rect,
        context: context,
        opacity: CGFloat(transform.opacity),
        scaleMultiplier: CGFloat(transform.scale),
        translation: translation,
        rotationDegrees: CGFloat(transform.rotationDegrees)
    )
}

private func draw(
    _ image: CGImage,
    in rect: CGRect,
    context: CGContext,
    opacity: CGFloat = 1,
    scaleMultiplier: CGFloat = 1,
    translation: CGSize = .zero,
    rotationDegrees: CGFloat = 0,
    contentMode: ExportContentMode = .fit,
    alignment: ExportDrawAlignment = .center
) {
    let imageSize = CGSize(width: image.width, height: image.height)
    let widthScale = rect.width / imageSize.width
    let heightScale = rect.height / imageSize.height
    let baseScale = contentMode == .fill ? max(widthScale, heightScale) : min(widthScale, heightScale)
    let scale = baseScale * scaleMultiplier
    let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    let origin = drawOrigin(
        for: drawSize,
        in: rect,
        alignment: alignment,
        translation: translation
    )
    let drawRect = CGRect(
        x: origin.x,
        y: origin.y,
        width: drawSize.width,
        height: drawSize.height
    )

    context.saveGState()
    context.clip(to: rect)
    context.setAlpha(opacity)
    if rotationDegrees != 0 {
        context.translateBy(x: drawRect.midX, y: drawRect.midY)
        context.rotate(by: rotationDegrees * .pi / 180)
        context.translateBy(x: -drawRect.midX, y: -drawRect.midY)
    }
    context.translateBy(x: 0, y: drawRect.maxY + drawRect.minY)
    context.scaleBy(x: 1, y: -1)
    context.draw(image, in: drawRect)
    context.restoreGState()
}

private func drawOrigin(
    for drawSize: CGSize,
    in rect: CGRect,
    alignment: ExportDrawAlignment,
    translation: CGSize
) -> CGPoint {
    var x = rect.midX - drawSize.width / 2
    var y = rect.midY - drawSize.height / 2

    switch alignment {
    case .center:
        break
    case .leading:
        x = rect.minX
    case .trailing:
        x = rect.maxX - drawSize.width
    case .top:
        y = rect.minY
    case .bottom:
        y = rect.maxY - drawSize.height
    }

    return CGPoint(x: x + translation.width, y: y + translation.height)
}

private func makePixelBuffer(
    from image: CGImage,
    size: CGSize,
    adaptor: AVAssetWriterInputPixelBufferAdaptor
) throws -> CVPixelBuffer {
    guard let pool = adaptor.pixelBufferPool else {
        throw AppError.videoExportFailed
    }

    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
    guard status == kCVReturnSuccess, let pixelBuffer else {
        throw AppError.videoExportFailed
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    }

    guard
        let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: baseAddress,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )
    else {
        throw AppError.videoExportFailed
    }

    context.interpolationQuality = .high
    context.draw(image, in: CGRect(origin: .zero, size: size))
    return pixelBuffer
}

private func temporaryExportURL(prefix: String, extension pathExtension: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        .appendingPathExtension(pathExtension)
}

private func bitrate(for size: CGSize) -> Int {
    if max(size.width, size.height) >= 1900 {
        return 10_000_000
    }
    return 5_000_000
}

private func finishWriting(_ writer: AVAssetWriter) async {
    await withCheckedContinuation { continuation in
        writer.finishWriting {
            continuation.resume()
        }
    }
}

private func exportAsynchronously(_ exportSession: AVAssetExportSession) async {
    await withCheckedContinuation { continuation in
        exportSession.exportAsynchronously {
            continuation.resume()
        }
    }
}

private final class ExportSessionCancellationBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}
