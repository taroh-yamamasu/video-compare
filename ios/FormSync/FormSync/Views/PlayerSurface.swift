import AVFoundation
import SwiftUI
import UIKit

struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    let videoGravity: AVLayerVideoGravity

    init(player: AVPlayer, videoGravity: AVLayerVideoGravity = .resizeAspect) {
        self.player = player
        self.videoGravity = videoGravity
    }

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = videoGravity
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        if uiView.playerLayer.videoGravity != videoGravity {
            uiView.playerLayer.videoGravity = videoGravity
        }
    }

    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: ()) {
        uiView.playerLayer.player = nil
    }
}

struct ZoomablePlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    let videoGravity: AVLayerVideoGravity
    let maximumZoomScale: CGFloat
    let viewScale: Double
    let viewOffset: CGSize
    let resetTrigger: Int
    let onSingleTap: () -> Void
    let onTransformChanged: (Double, CGSize) -> Void

    init(
        player: AVPlayer,
        videoGravity: AVLayerVideoGravity = .resizeAspect,
        maximumZoomScale: CGFloat = 4,
        viewScale: Double = 1,
        viewOffset: CGSize = .zero,
        resetTrigger: Int = 0,
        onSingleTap: @escaping () -> Void = {},
        onTransformChanged: @escaping (Double, CGSize) -> Void = { _, _ in }
    ) {
        self.player = player
        self.videoGravity = videoGravity
        self.maximumZoomScale = maximumZoomScale
        self.viewScale = viewScale
        self.viewOffset = viewOffset
        self.resetTrigger = resetTrigger
        self.onSingleTap = onSingleTap
        self.onTransformChanged = onTransformChanged
    }

    func makeUIView(context: Context) -> ZoomablePlayerScrollView {
        let view = ZoomablePlayerScrollView()
        view.configure(
            player: player,
            videoGravity: videoGravity,
            maximumZoomScale: maximumZoomScale,
            viewScale: viewScale,
            viewOffset: viewOffset,
            resetTrigger: resetTrigger,
            onSingleTap: onSingleTap,
            onTransformChanged: onTransformChanged
        )
        return view
    }

    func updateUIView(_ uiView: ZoomablePlayerScrollView, context: Context) {
        uiView.configure(
            player: player,
            videoGravity: videoGravity,
            maximumZoomScale: maximumZoomScale,
            viewScale: viewScale,
            viewOffset: viewOffset,
            resetTrigger: resetTrigger,
            onSingleTap: onSingleTap,
            onTransformChanged: onTransformChanged
        )
    }

    static func dismantleUIView(_ uiView: ZoomablePlayerScrollView, coordinator: ()) {
        uiView.clearPlayer()
    }
}

final class ZoomablePlayerScrollView: UIScrollView, UIScrollViewDelegate {
    private let playerView = PlayerContainerView()
    private var laidOutSize: CGSize = .zero
    private var resetTrigger = 0
    private var requestedScale: CGFloat = 1
    private var requestedOffset: CGPoint = .zero
    private var onSingleTap: () -> Void = {}
    private var onTransformChanged: (Double, CGSize) -> Void = { _, _ in }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureScrollView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureScrollView()
    }

    func configure(
        player: AVPlayer,
        videoGravity: AVLayerVideoGravity,
        maximumZoomScale: CGFloat,
        viewScale: Double,
        viewOffset: CGSize,
        resetTrigger: Int,
        onSingleTap: @escaping () -> Void,
        onTransformChanged: @escaping (Double, CGSize) -> Void
    ) {
        self.onSingleTap = onSingleTap
        self.onTransformChanged = onTransformChanged
        requestedScale = CGFloat(viewScale)
        requestedOffset = CGPoint(x: viewOffset.width, y: viewOffset.height)
        if self.maximumZoomScale != maximumZoomScale {
            self.maximumZoomScale = maximumZoomScale
        }
        if playerView.playerLayer.player !== player {
            playerView.playerLayer.player = player
        }
        if playerView.playerLayer.videoGravity != videoGravity {
            playerView.playerLayer.videoGravity = videoGravity
        }
        if self.resetTrigger != resetTrigger {
            self.resetTrigger = resetTrigger
            resetFraming(animated: true)
        }
        applyRequestedTransform()
    }

    func clearPlayer() {
        playerView.playerLayer.player = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let size = bounds.size
        guard size.width > 0, size.height > 0 else {
            return
        }

        if laidOutSize != size {
            laidOutSize = size
            setZoomScale(minimumZoomScale, animated: false)
            playerView.transform = .identity
            playerView.frame = CGRect(origin: .zero, size: size)
            contentSize = size
        }

        updateInsets()
        updatePanState()
        applyRequestedTransform()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        playerView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateInsets()
        updatePanState()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        updatePanState()
        reportTransform()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            reportTransform()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        reportTransform()
    }

    private func configureScrollView() {
        backgroundColor = .black
        clipsToBounds = true
        delegate = self
        minimumZoomScale = 1
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        delaysContentTouches = false
        canCancelContentTouches = true
        panGestureRecognizer.isEnabled = false

        addSubview(playerView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }

    private func updateInsets() {
        let horizontalInset = max((bounds.width - contentSize.width) / 2, 0)
        let verticalInset = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }

    private func updatePanState() {
        panGestureRecognizer.isEnabled = zoomScale > minimumZoomScale + 0.01
    }

    private func applyRequestedTransform() {
        guard laidOutSize != .zero, !isTracking, !isDragging, !isDecelerating, !isZooming else {
            return
        }

        let scale = min(max(requestedScale, minimumZoomScale), maximumZoomScale)
        if abs(zoomScale - scale) > 0.001 {
            setZoomScale(scale, animated: false)
        }
        if abs(contentOffset.x - requestedOffset.x) > 0.5 || abs(contentOffset.y - requestedOffset.y) > 0.5 {
            setContentOffset(requestedOffset, animated: false)
        }
    }

    private func reportTransform() {
        requestedScale = zoomScale
        requestedOffset = contentOffset
        onTransformChanged(
            Double(zoomScale),
            CGSize(width: contentOffset.x, height: contentOffset.y)
        )
    }

    @objc private func handleSingleTap() {
        onSingleTap()
    }

    @objc private func handleDoubleTap() {
        resetFraming(animated: true)
        requestedScale = minimumZoomScale
        requestedOffset = .zero
        onTransformChanged(Double(minimumZoomScale), .zero)
    }

    private func resetFraming(animated: Bool) {
        setZoomScale(minimumZoomScale, animated: animated)
        setContentOffset(.zero, animated: animated)
    }
}

final class PlayerContainerView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
    }
}
