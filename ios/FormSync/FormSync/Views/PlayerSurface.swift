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

    init(
        player: AVPlayer,
        videoGravity: AVLayerVideoGravity = .resizeAspect,
        maximumZoomScale: CGFloat = 4
    ) {
        self.player = player
        self.videoGravity = videoGravity
        self.maximumZoomScale = maximumZoomScale
    }

    func makeUIView(context: Context) -> ZoomablePlayerScrollView {
        let view = ZoomablePlayerScrollView()
        view.configure(player: player, videoGravity: videoGravity, maximumZoomScale: maximumZoomScale)
        return view
    }

    func updateUIView(_ uiView: ZoomablePlayerScrollView, context: Context) {
        uiView.configure(player: player, videoGravity: videoGravity, maximumZoomScale: maximumZoomScale)
    }

    static func dismantleUIView(_ uiView: ZoomablePlayerScrollView, coordinator: ()) {
        uiView.clearPlayer()
    }
}

final class ZoomablePlayerScrollView: UIScrollView, UIScrollViewDelegate {
    private let playerView = PlayerContainerView()
    private var laidOutSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureScrollView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureScrollView()
    }

    func configure(player: AVPlayer, videoGravity: AVLayerVideoGravity, maximumZoomScale: CGFloat) {
        if self.maximumZoomScale != maximumZoomScale {
            self.maximumZoomScale = maximumZoomScale
        }
        if playerView.playerLayer.player !== player {
            playerView.playerLayer.player = player
        }
        if playerView.playerLayer.videoGravity != videoGravity {
            playerView.playerLayer.videoGravity = videoGravity
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

        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        recognizer.numberOfTapsRequired = 2
        addGestureRecognizer(recognizer)
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

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale + 0.01 {
            setZoomScale(minimumZoomScale, animated: true)
            return
        }

        let targetZoomScale = min(maximumZoomScale, 2)
        let location = recognizer.location(in: playerView)
        let zoomSize = CGSize(
            width: bounds.width / targetZoomScale,
            height: bounds.height / targetZoomScale
        )
        let zoomRect = CGRect(
            x: location.x - zoomSize.width / 2,
            y: location.y - zoomSize.height / 2,
            width: zoomSize.width,
            height: zoomSize.height
        )
        zoom(to: zoomRect, animated: true)
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
