import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

private let width = 1280
private let height = 720
private let framesPerSecond: Int32 = 30
private let durationSeconds = 6

private struct MotionStyle {
    let depth: CGFloat
    let lean: CGFloat
    let phaseOffset: Double
}

private enum SampleGenerationError: Error {
    case pixelBufferPoolUnavailable
    case pixelBufferCreationFailed
    case contextCreationFailed
    case writerFailed(Error?)
}

private func smoothCycle(_ progress: Double, offset: Double) -> CGFloat {
    let shifted = (progress + offset).truncatingRemainder(dividingBy: 1)
    return CGFloat(0.5 - 0.5 * cos(shifted * 2 * .pi))
}

private func drawLine(
    _ context: CGContext,
    from start: CGPoint,
    to end: CGPoint,
    width: CGFloat,
    color: CGColor
) {
    context.setStrokeColor(color)
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.move(to: start)
    context.addLine(to: end)
    context.strokePath()
}

private func drawFrame(in context: CGContext, progress: Double, style: MotionStyle) {
    let canvas = CGRect(x: 0, y: 0, width: width, height: height)
    context.setFillColor(CGColor(red: 0.035, green: 0.043, blue: 0.055, alpha: 1))
    context.fill(canvas)

    context.setStrokeColor(CGColor(red: 0.15, green: 0.18, blue: 0.20, alpha: 1))
    context.setLineWidth(2)
    for x in stride(from: 80, through: width - 80, by: 80) {
        context.move(to: CGPoint(x: x, y: 80))
        context.addLine(to: CGPoint(x: x, y: height - 80))
    }
    for y in stride(from: 80, through: height - 80, by: 80) {
        context.move(to: CGPoint(x: 80, y: y))
        context.addLine(to: CGPoint(x: width - 80, y: y))
    }
    context.strokePath()

    let phase = smoothCycle(progress, offset: style.phaseOffset)
    let centerX: CGFloat = 640
    let groundY: CGFloat = 620
    let hip = CGPoint(x: centerX - 12 + (style.lean * 54 * phase), y: 420 + style.depth * phase)
    let knee = CGPoint(x: centerX + 92 * phase, y: 520 + 42 * phase)
    let ankle = CGPoint(x: centerX + 18, y: groundY)
    let toe = CGPoint(x: centerX + 95, y: groundY)
    let shoulder = CGPoint(
        x: hip.x + style.lean * 150 * phase,
        y: hip.y - 162 + 26 * phase
    )
    let head = CGPoint(x: shoulder.x + 8, y: shoulder.y - 72)
    let elbow = CGPoint(x: shoulder.x + 82, y: shoulder.y + 34 + 18 * phase)
    let hand = CGPoint(x: shoulder.x + 155, y: shoulder.y + 38 + 20 * phase)

    let lime = CGColor(red: 0.72, green: 1.0, blue: 0.16, alpha: 1)
    let shadow = CGColor(red: 0.28, green: 0.38, blue: 0.12, alpha: 0.45)

    drawLine(context, from: CGPoint(x: 300, y: groundY + 24), to: CGPoint(x: 980, y: groundY + 24), width: 3, color: shadow)
    drawLine(context, from: hip, to: shoulder, width: 82, color: lime)
    drawLine(context, from: hip, to: knee, width: 48, color: lime)
    drawLine(context, from: knee, to: ankle, width: 44, color: lime)
    drawLine(context, from: ankle, to: toe, width: 34, color: lime)
    drawLine(context, from: shoulder, to: elbow, width: 34, color: lime)
    drawLine(context, from: elbow, to: hand, width: 30, color: lime)

    context.setFillColor(lime)
    context.fillEllipse(in: CGRect(x: head.x - 46, y: head.y - 46, width: 92, height: 92))

    context.setStrokeColor(CGColor(red: 0.72, green: 1.0, blue: 0.16, alpha: 0.46))
    context.setLineWidth(3)
    context.move(to: CGPoint(x: centerX, y: 94))
    context.addLine(to: CGPoint(x: centerX, y: CGFloat(height - 76)))
    context.strokePath()

    context.setFillColor(CGColor(red: 0.72, green: 1.0, blue: 0.16, alpha: 0.75))
    context.fillEllipse(in: CGRect(x: centerX - 7, y: groundY + 17, width: 14, height: 14))
}

private func generateVideo(at outputURL: URL, style: MotionStyle) throws {
    try? FileManager.default.removeItem(at: outputURL)

    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
    let input = AVAssetWriterInput(
        mediaType: .video,
        outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 1_100_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
    )
    input.expectsMediaDataInRealTime = false

    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
    )

    guard writer.canAdd(input) else {
        throw SampleGenerationError.writerFailed(writer.error)
    }

    writer.add(input)
    guard writer.startWriting() else {
        throw SampleGenerationError.writerFailed(writer.error)
    }
    writer.startSession(atSourceTime: .zero)

    guard let pool = adaptor.pixelBufferPool else {
        throw SampleGenerationError.pixelBufferPoolUnavailable
    }

    let totalFrames = Int(framesPerSecond) * durationSeconds
    for frameIndex in 0..<totalFrames {
        while !input.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.002)
        }

        var optionalBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer) == kCVReturnSuccess,
              let pixelBuffer = optionalBuffer else {
            throw SampleGenerationError.pixelBufferCreationFailed
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
              let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
              ) else {
            throw SampleGenerationError.contextCreationFailed
        }

        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        drawFrame(
            in: context,
            progress: Double(frameIndex) / Double(totalFrames),
            style: style
        )

        let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: framesPerSecond)
        guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
            throw SampleGenerationError.writerFailed(writer.error)
        }
    }

    input.markAsFinished()
    let semaphore = DispatchSemaphore(value: 0)
    writer.finishWriting {
        semaphore.signal()
    }
    semaphore.wait()

    guard writer.status == .completed else {
        throw SampleGenerationError.writerFailed(writer.error)
    }
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "FormSync/SampleVideos")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

try generateVideo(
    at: outputDirectory.appendingPathComponent("sample-a.mp4"),
    style: MotionStyle(depth: 105, lean: 0.16, phaseOffset: 0)
)
try generateVideo(
    at: outputDirectory.appendingPathComponent("sample-b.mp4"),
    style: MotionStyle(depth: 145, lean: 0.34, phaseOffset: -0.08)
)

print("Generated sample-a.mp4 and sample-b.mp4 in \(outputDirectory.path)")
