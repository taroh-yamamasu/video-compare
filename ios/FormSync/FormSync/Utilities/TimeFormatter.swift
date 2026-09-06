import Foundation

enum TimeFormatter {
    static func short(_ seconds: Double) -> String {
        guard seconds.isFinite else {
            return "0:00.0"
        }

        let safeSeconds = max(0, seconds)
        let minutes = Int(safeSeconds / 60)
        let remainingSeconds = safeSeconds - Double(minutes * 60)
        return String(format: "%d:%04.1f", minutes, remainingSeconds)
    }
}
