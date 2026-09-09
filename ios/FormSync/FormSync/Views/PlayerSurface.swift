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
    let resetTrigger: Int
    let onSingleTap: () -> Void

    init(
        player: AVPlayer,
        videoGravity: AVLayerVideoGravity = .resizeAspect,
        maximumZoomScale: CGFloat = 4,
        resetTrigger: Int = 0,
        onSingleTap: @escaping () -> Void = {}
    ) {
        self.player = player
        self.videoGravity = videoGravity
        self.maximumZoomScale = maximumZoomScale
        self.resetTrigger = resetTrigger
        self.onSingleTap = onSingleTap
    }

    func makeUIView(context: Context) -> ZoomablePlayerScrollView {
        let view = ZoomablePlayerScrollView()
        view.configure(
            player: player,
            videoGravity: videoGravity,
            maximumZoomScale: maximumZoomScale,
            resetTrigger: resetTrigger,
            onSingleTap: onSingleTap
        )
        return view
    }

    func updateUIView(_ uiView: ZoomablePlayerScrollView, context: Context) {
        uiView.configure(
            player: player,
            videoGravity: videoGravity,
            maximumZoomScale: maximumZoomScale,
            resetTrigger: resetTrigger,
            onSingleTap: onSingleTap
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
    private var onSingleTap: () -> Void = {}

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
        resetTrigger: Int,
        onSingleTap: @escaping () -> Void
    ) {
        self.onSingleTap = onSingleTap
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

    @objc private func handleSingleTap() {
        onSingleTap()
    }

    @objc private func handleDoubleTap() {
        resetFraming(animated: true)
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
