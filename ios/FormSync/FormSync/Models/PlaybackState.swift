import Foundation

struct PlaybackState: Equatable {
    var isPlaying: Bool = false
    var timelineSeconds: Double = 0
    var timelineLowerBound: Double = 0
    var timelineUpperBound: Double = 1
    var rightOffsetSeconds: Double = 0
    var playbackRate: Float = 1.0

    var hasValidTimelineRange: Bool {
        timelineUpperBound > timelineLowerBound
    }

    var timelineRange: ClosedRange<Double> {
        timelineLowerBound...max(timelineLowerBound, timelineUpperBound)
    }

    var comparableDurationSeconds: Double {
        max(0, timelineUpperBound - timelineLowerBound)
    }
}
