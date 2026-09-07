import AVFoundation
import Foundation
import PhotosUI
import SwiftUI

struct CompareView: View {
    @StateObject private var viewModel: CompareViewModel
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.dismiss) private var dismiss
    @State private var leftReplacement: PhotosPickerItem?
    @State private var rightReplacement: PhotosPickerItem?
    @State private var focusedSetupSide: VideoSide = .left
    @State private var showsSyncedDetails = false
    @State private var showsOverlayDetails = false
    @State private var showsExportSheet = false
    @State private var proPaywallFeature: ProFeature?
    @State private var hasTrialAccess = false
    @State private var trialVideoPairIdentity: String?
    @State private var overlayNudgeStep: Double = 1
    @State private var overlayScaleStep: Double = 0.01
    @State private var overlayRotationStep: Double = 1
    @State private var isScreenCaptured = UIScreen.main.isCaptured
    @GestureState private var overlayPinchMagnification = 1.0
    @GestureState private var overlayDragTranslation = CGSize.zero

    init(leftVideo: VideoItem, rightVideo: VideoItem) {
        _viewModel = StateObject(
            wrappedValue: CompareViewModel(leftVideo: leftVideo, rightVideo: rightVideo)
        )
    }

    init(pair: LoadedVideoPair) {
        _viewModel = StateObject(
            wrappedValue: CompareViewModel(
                leftVideo: pair.left,
                rightVideo: pair.right,
                session: pair.session,
                ownsTemporaryVideos: pair.ownsTemporaryVideos,
                isSample: pair.isSample
            )
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height
            let isPhoneLandscape = isLandscape && !AppTheme.isRegularWidth(proxy.size)
            let spacing: CGFloat = isPhoneLandscape ? AppTheme.spacingS : AppTheme.spacingM
            let horizontalPadding = isPhoneLandscape ? AppTheme.spacingS : AppTheme.pageHorizontalPadding(for: proxy.size)
            let usesSidebar = usesSidebarLayout(for: proxy.size)
            let wrapsDenseControls = usesSidebar || AppTheme.isCompactPhone(proxy.size)
            let topPadding = isPhoneLandscape || usesSidebar ? AppTheme.spacingS : AppTheme.pageVerticalPadding(for: proxy.size)
            let bottomPadding = isPhoneLandscape || usesSidebar ? AppTheme.spacingM : AppTheme.spacingL

            ScrollView(.vertical) {
                Group {
                    if usesSidebar {
                        HStack(alignment: .top, spacing: AppTheme.spacingM) {
                            stageSection(
                                size: proxy.size,
                                isLandscape: isLandscape
                            )
                            .frame(maxWidth: .infinity, alignment: .top)

                            sidebarControls
                                .frame(width: compareSidebarWidth(for: proxy.size), alignment: .top)
                        }
                    } else {
                        VStack(spacing: spacing) {
                            stageSection(
                                size: proxy.size,
                                isLandscape: isLandscape
                            )
                            controls(wrapsDenseControls: wrapsDenseControls)
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, topPadding)
                .padding(.bottom, bottomPadding)
                .frame(maxWidth: compareContentWidthLimit(for: proxy.size), alignment: .top)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(AppTheme.background.ignoresSafeArea())
        }
        .navigationTitle(viewModel.compareMode == .setup ? "Reference Points" : "Comparison")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showsExportSheet) {
            ExportView(viewModel: viewModel, hasTrialAccess: hasTrialAccess)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsSyncedDetails) {
            syncedDetailsSheet
        }
        .sheet(item: $proPaywallFeature) { feature in
            ProPaywallView(feature: feature)
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            isScreenCaptured = UIScreen.main.isCaptured
            if viewModel.compareMode == .synced {
                activateTrialForCurrentComparisonIfNeeded()
            }
            enforceEntitlements()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
            isScreenCaptured = UIScreen.main.isCaptured
        }
        .onChange(of: purchaseManager.isProUnlocked) { _, _ in
            enforceEntitlements()
        }
        .onChange(of: viewModel.videoPairIdentity) { _, newIdentity in
            guard hasTrialAccess, trialVideoPairIdentity != newIdentity else {
                return
            }

            hasTrialAccess = false
            trialVideoPairIdentity = nil
            enforceEntitlements()
        }
        .onDisappear {
            if viewModel.compareMode == .synced,
               !viewModel.isSample,
               viewModel.hasMeaningfulComparisonActivity,
               !viewModel.hasExportFailure,
               !purchaseManager.hasRecentPurchaseFailure,
               proPaywallFeature == nil {
                SettingsStore().markComparisonCompletedForReview()
            }
            viewModel.pause()
            viewModel.persistSession()
        }
    }

    @ViewBuilder
    private func stageSection(
        size: CGSize,
        isLandscape: Bool
    ) -> some View {
        if viewModel.compareMode == .setup {
            VStack(alignment: .leading, spacing: AppTheme.spacingM) {
                setupHeader
                setupStage(size: size, isLandscape: isLandscape)
            }
        } else if viewModel.settings.displayMode == .overlayPreview {
            overlayStage(height: overlayHeight(for: size, isLandscape: isLandscape))
        } else if viewModel.settings.displayMode == .sideBySide {
            HStack(spacing: AppTheme.spacingS) {
                syncedVideoPane(side: .left, height: syncedPaneHeight(for: size, isLandscape: isLandscape))
                syncedVideoPane(side: .right, height: syncedPaneHeight(for: size, isLandscape: isLandscape))
            }
        } else {
            VStack(spacing: AppTheme.spacingS) {
                syncedVideoPane(side: .left, height: syncedPaneHeight(for: size, isLandscape: false))
                syncedVideoPane(side: .right, height: syncedPaneHeight(for: size, isLandscape: false))
            }
        }
    }

    private var setupHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
            Text("Match the Same Moment")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.primaryText)

            Text("Set the moment used to align each video.")
                .font(.callout)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var sidebarControls: some View {
        VStack(spacing: AppTheme.spacingM) {
            if viewModel.compareMode != .setup, viewModel.settings.displayMode == .overlayPreview {
                overlayControls
            }

            controls(isCompact: true, wrapsDenseControls: true)
        }
    }

    @ViewBuilder
    private func setupStage(size: CGSize, isLandscape: Bool) -> some View {
        if usesTwoColumnSetup(for: size) {
            HStack(spacing: AppTheme.spacingS) {
                setupSlotEditor(side: .left, videoHeight: setupVideoHeight(for: size, isLandscape: isLandscape))
                setupSlotEditor(side: .right, videoHeight: setupVideoHeight(for: size, isLandscape: isLandscape))
            }
        } else {
            VStack(spacing: AppTheme.spacingS) {
                setupSlotEditor(side: focusedSetupSide, videoHeight: setupVideoHeight(for: size, isLandscape: false))
            }
        }
    }

    private func setupSlotEditor(side: VideoSide, videoHeight: CGFloat) -> some View {
        let slot = viewModel.slot(for: side)

        return VStack(alignment: .leading, spacing: AppTheme.spacingM) {
            playerFrame(side: side, height: videoHeight)

            HStack(spacing: AppTheme.spacingS) {
                Text(slot.label)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)

                Spacer(minLength: AppTheme.spacingS)

                syncBadge(slot: slot)
            }

            HStack(spacing: AppTheme.spacingS) {
                Text(TimeFormatter.short(slot.currentTimeSeconds))
                TappableSeekSlider(
                    value: Binding(
                        get: { viewModel.slot(for: side).currentTimeSeconds },
                        set: { value in
                            viewModel.scrubSlot(side, to: value)
                        }
                    ),
                    range: 0...max(slot.video.durationSeconds, 0.01),
                    onEditingChanged: { isEditing in
                        if isEditing {
                            viewModel.beginSlotScrubbing(side)
                        } else {
                            Task {
                                await viewModel.endSlotScrubbing(side)
                            }
                        }
                    }
                )
                Text(TimeFormatter.short(slot.video.durationSeconds))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(AppTheme.secondaryText)

            HStack(spacing: AppTheme.spacingS) {
                Button {
                    viewModel.toggleSlotPlayback(side)
                } label: {
                    Image(systemName: slot.isPlaying ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
                .accessibilityLabel(slot.isPlaying ? String(localized: "Pause") : String(localized: "Play"))

                Button {
                    Task {
                        await viewModel.stepSlot(side, direction: -1)
                    }
                } label: {
                    Label("Step Back", systemImage: "backward.frame.fill")
                        .labelStyle(.iconOnly)
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
                .accessibilityLabel("Step Back")

                Button {
                    Task {
                        await viewModel.stepSlot(side, direction: 1)
                    }
                } label: {
                    Label("Step Forward", systemImage: "forward.frame.fill")
                        .labelStyle(.iconOnly)
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
                .accessibilityLabel("Step Forward")
            }

            HStack(spacing: AppTheme.spacingS) {
                Button {
                    setSyncPointAndAdvance(side)
                } label: {
                    Label("Set This Reference Point", systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(AppTheme.accentText)
                .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
                .accessibilityIdentifier("compare.setReference.\(side.rawValue)")

                if slot.hasSyncPoint {
                    Button {
                        viewModel.clearSyncPoint(side)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
                    .accessibilityLabel("\(String(localized: "Clear")) \(slot.label)")
                }

                if !viewModel.isSample {
                    PhotosPicker(
                        selection: replacementSelection(for: side),
                        matching: .videos,
                        preferredItemEncoding: .current
                    ) {
                        Image(systemName: "photo.on.rectangle")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
                    .disabled(viewModel.isLoadingReplacement)
                    .accessibilityLabel(L10n.format("Replace %@", slot.label))
                }
            }
        }
        .appCard(padding: AppTheme.spacingL)
    }

    private func syncedVideoPane(side: VideoSide, height: CGFloat) -> some View {
        playerFrame(
            side: side,
            height: height,
            showsSideLabel: false,
            videoGravity: .resizeAspect
        )
    }

    @ViewBuilder
    private func playerFrame(
        side: VideoSide,
        height: CGFloat,
        showsSideLabel: Bool = true,
        videoGravity: AVLayerVideoGravity = .resizeAspect
    ) -> some View {
        ZStack(alignment: .topLeading) {
            ZoomablePlayerSurface(player: viewModel.player(for: side), videoGravity: videoGravity)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(Color.black)
                .clipped()

            if showsSideLabel {
                Text(side.displayName)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, AppTheme.spacingS)
                    .padding(.vertical, AppTheme.spacingXS)
                    .background(AppTheme.elevatedSurface.opacity(0.82), in: RoundedRectangle(cornerRadius: AppTheme.radiusS, style: .continuous))
                    .foregroundStyle(AppTheme.primaryText)
                    .padding(AppTheme.spacingS)
            }

            if !hasFullAccess {
                liveWatermark
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(AppTheme.spacingS)
            }

            if shouldProtectLiveContent {
                screenCaptureProtection
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusS, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusS, style: .continuous)
                .stroke(viewModel.slot(for: side).hasSyncPoint ? AppTheme.accentBorder : AppTheme.border)
        )
    }

    private func overlayStage(height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.black

            overlayPlayer(side: .left)
            overlayPlayer(side: .right)

            if !hasFullAccess {
                liveWatermark
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(AppTheme.spacingS)
            }

            if shouldProtectLiveContent {
                screenCaptureProtection
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous)
                .stroke(AppTheme.border)
        )
        .simultaneousGesture(overlayPinchGesture)
        .simultaneousGesture(overlayDragGesture)
    }

    private var liveWatermark: some View {
        Text("KinePair")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white.opacity(0.86))
            .padding(.horizontal, AppTheme.spacingS)
            .padding(.vertical, AppTheme.spacingXS)
            .background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: AppTheme.radiusS, style: .continuous))
            .accessibilityHidden(true)
    }

    private var shouldProtectLiveContent: Bool {
        !hasFullAccess && isScreenCaptured
    }

    private var screenCaptureProtection: some View {
        VStack(spacing: AppTheme.spacingS) {
            Image(systemName: "lock.shield.fill")
                .font(.title2.weight(.bold))

            Text("Screen Recording Active")
                .font(.headline.weight(.bold))

            Text("Video is hidden during screen recording in the free version.")
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(AppTheme.primaryText)
        .padding(AppTheme.spacingM)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.72))
        .accessibilityElement(children: .combine)
    }

    private func overlayPlayer(side: VideoSide) -> some View {
        let transform = viewModel.overlaySettings.transform(for: side)
        let isEditing = side == viewModel.overlaySettings.editingSide
        let scale = transform.scale * (isEditing ? overlayPinchMagnification : 1)
        let offsetX = transform.translateX + (isEditing ? overlayDragTranslation.width : 0)
        let offsetY = transform.translateY + (isEditing ? overlayDragTranslation.height : 0)

        return PlayerSurface(player: viewModel.player(for: side), videoGravity: .resizeAspect)
            .opacity(transform.opacity)
            .scaleEffect(scale)
            .rotationEffect(.degrees(transform.rotationDegrees))
            .offset(x: offsetX, y: offsetY)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func controls(isCompact: Bool = false, wrapsDenseControls: Bool = false) -> some View {
        VStack(spacing: isCompact ? AppTheme.spacingS : AppTheme.spacingM) {
            messageView

            if viewModel.compareMode == .setup {
                setupControls(isCompact: isCompact)
            } else {
                syncedControls(isCompact: isCompact, wrapsDenseControls: wrapsDenseControls)
            }

            if viewModel.isSample {
                Button {
                    dismiss()
                } label: {
                    Label("Try Your Own Videos", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
                .accessibilityIdentifier("compare.tryOwnVideos")
            }
        }
        .appCard(padding: isCompact ? AppTheme.spacingM : AppTheme.spacingL)
    }

    @ViewBuilder
    private var messageView: some View {
        if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .font(.callout)
                .foregroundStyle(AppTheme.error)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if viewModel.compareMode == .setup, let toastMessage = viewModel.toastMessage {
            Text(toastMessage)
                .font(.callout)
                .foregroundStyle(AppTheme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func setupControls(isCompact: Bool = false) -> some View {
        VStack(spacing: isCompact ? AppTheme.spacingS : AppTheme.spacingM) {
            syncStatusSummary(isCompact: isCompact)
            trialAccessStatus

            HStack(spacing: AppTheme.spacingS) {
                Button {
                    Task {
                        activateTrialForCurrentComparisonIfNeeded()
                        await viewModel.startSyncedCompare()
                    }
                } label: {
                    Label("Start Comparison", systemImage: "play.rectangle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(AppTheme.accentText)
                .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
                .controlSize(.large)
                .disabled(!viewModel.canStartSyncedCompare)
                .accessibilityIdentifier("compare.start")

                Button {
                    Task {
                        await viewModel.swapVideos()
                    }
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
                .controlSize(.large)
                .accessibilityLabel("Swap Videos")
            }

        }
    }

    @ViewBuilder
    private var trialAccessStatus: some View {
        if viewModel.isSample {
            Label("Sample mode includes all PRO features.", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if !purchaseManager.isProUnlocked {
            let text = hasTrialAccess
                ? String(localized: "All PRO features are available in this comparison.")
                : purchaseManager.hasRemainingTrialUses
                    ? L10n.format(
                        "Starting comparison uses one full-feature trial. %d remaining.",
                        purchaseManager.remainingTrialUses
                    )
                    : String(localized: "This comparison uses the free feature set.")

            Label(text, systemImage: hasTrialAccess ? "sparkles" : "info.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(hasTrialAccess ? AppTheme.accent : AppTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func syncedControls(isCompact: Bool = false, wrapsDenseControls: Bool = false) -> some View {
        VStack(spacing: isCompact ? AppTheme.spacingS : AppTheme.spacingM) {
            displayModeSelector(wrapsDenseControls: wrapsDenseControls)

            HStack {
                Text("Sync \(signedTime(viewModel.playbackState.timelineSeconds))")
                Spacer()
                Text(TimeFormatter.short(viewModel.playbackState.comparableDurationSeconds))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(AppTheme.secondaryText)

            TappableSeekSlider(
                value: Binding(
                    get: { viewModel.playbackState.timelineSeconds },
                    set: { viewModel.scrub(to: $0) }
                ),
                range: viewModel.playbackState.timelineRange,
                isEnabled: viewModel.playbackState.hasValidTimelineRange,
                onEditingChanged: { isEditing in
                    if isEditing {
                        viewModel.beginScrubbing()
                    } else {
                        Task {
                            await viewModel.endScrubbing()
                        }
                    }
                }
            )

            HStack(spacing: AppTheme.spacingS) {
                Button {
                    Task {
                        await viewModel.stepTimeline(-1)
                    }
                } label: {
                    Image(systemName: "backward.frame.fill")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
                .accessibilityLabel("Step Back")

                Button {
                    Task {
                        await viewModel.togglePlayback()
                    }
                } label: {
                    Label(
                        viewModel.playbackState.isPlaying ? String(localized: "Pause") : String(localized: "Play"),
                        systemImage: viewModel.playbackState.isPlaying ? "pause.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(AppTheme.accentText)
                .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
                .controlSize(.large)
                .disabled(!viewModel.playbackState.hasValidTimelineRange)

                Button {
                    Task {
                        await viewModel.stepTimeline(1)
                    }
                } label: {
                    Image(systemName: "forward.frame.fill")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
                .accessibilityLabel("Step Forward")
            }

            HStack(spacing: AppTheme.spacingS) {
                Menu {
                    ForEach(PlaybackRate.allCases) { rate in
                        Button {
                            if rate.requiresPro, !canUse(.slowPlayback) {
                                proPaywallFeature = .slowPlayback
                            } else {
                                viewModel.setPlaybackRate(rate)
                            }
                        } label: {
                            if viewModel.settings.playbackRate == rate {
                                Label(rate.label, systemImage: "checkmark")
                            } else {
                                Text(rate.label)
                            }
                        }
                    }
                } label: {
                    Label(viewModel.settings.playbackRate.label, systemImage: "speedometer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
                .proBadgeOverlay(viewModel.settings.playbackRate.requiresPro && !canUse(.slowPlayback))

                Button {
                    showsSyncedDetails = true
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
                .accessibilityIdentifier("compare.details")
                .accessibilityLabel("Advanced Settings")

                Button {
                    showsExportSheet = true
                } label: {
                    if viewModel.isExporting {
                        ProgressView()
                            .frame(width: 34, height: 34)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                            .frame(width: 34, height: 34)
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
                .disabled(viewModel.isExporting)
                .proBadgeOverlay(!hasFullAccess)
                .accessibilityIdentifier("compare.export")
                .accessibilityLabel("Export")
            }
        }
    }

    private var syncedDetailsContent: some View {
        VStack(spacing: AppTheme.spacingM) {
            displayModeSelector(wrapsDenseControls: true)
            playbackRateSelector(wrapsDenseControls: true)
            stepSelector(wrapsDenseControls: true)
            loopControls(wrapsDenseControls: true)

            HStack(spacing: AppTheme.spacingS) {
                Button {
                    showsSyncedDetails = false
                    viewModel.exitSyncedCompare()
                } label: {
                    Label("Edit Reference Points", systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))

                Button {
                    Task {
                        await viewModel.swapVideos()
                    }
                } label: {
                    Label("Swap Videos", systemImage: "arrow.left.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
            }
        }
    }

    private var syncedDetailsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.spacingM) {
                    syncedDetailsContent

                    if viewModel.settings.displayMode == .overlayPreview {
                        overlayControls
                    }
                }
                .padding(AppTheme.spacingL)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Advanced Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        showsSyncedDetails = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func syncStatusSummary(isCompact: Bool = false) -> some View {
        if isCompact {
            VStack(spacing: AppTheme.spacingS) {
                syncStatusChip(slot: viewModel.leftSlot)
                syncStatusChip(slot: viewModel.rightSlot)
            }
        } else {
            HStack(spacing: AppTheme.spacingS) {
                syncStatusChip(slot: viewModel.leftSlot)
                syncStatusChip(slot: viewModel.rightSlot)
            }
        }
    }

    private func syncStatusChip(slot: VideoSlotState) -> some View {
        let isSelected = focusedSetupSide == slot.side

        return Button {
            focusedSetupSide = slot.side
        } label: {
            HStack(spacing: AppTheme.spacingXS) {
                Image(systemName: slot.hasSyncPoint ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(syncStatusIconColor(slot: slot, isSelected: isSelected))
                Text(slot.label)
                Spacer(minLength: 4)
                Text(slot.hasSyncPoint ? TimeFormatter.short(slot.syncPointSeconds) : String(localized: "Not Set"))
                    .monospacedDigit()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSelected ? AppTheme.selectedText : AppTheme.primaryText)
            .padding(.horizontal, AppTheme.spacingS)
            .padding(.vertical, AppTheme.spacingS)
            .frame(maxWidth: .infinity)
            .background(
                isSelected ? AppTheme.selectedSegment : AppTheme.subtleSurface,
                in: RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous)
                    .stroke(isSelected ? Color.clear : AppTheme.border)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(L10n.format("Show %@", slot.label))
        .accessibilityHint("Switch the video used for reference point setup")
    }

    private func syncStatusIconColor(slot: VideoSlotState, isSelected: Bool) -> Color {
        if isSelected {
            return AppTheme.selectedText.opacity(slot.hasSyncPoint ? 0.95 : 0.72)
        }

        return slot.hasSyncPoint ? AppTheme.accent : AppTheme.tertiaryText
    }

    private func displayModeSelector(wrapsDenseControls: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingS) {
            Text("Layout")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)

            AdaptiveSegmentGroup(
                items: Array(DisplayMode.allCases),
                gridColumns: wrapsDenseControls ? 3 : nil
            ) { mode in
                proSegmentButton(
                    title: mode.label,
                    isSelected: viewModel.settings.displayMode == mode,
                    showsBadge: mode.requiresPro && !canUse(.overlay),
                    accessibilityIdentifier: "compare.layout.\(mode.rawValue)"
                ) {
                    if mode.requiresPro, !canUse(.overlay) {
                        proPaywallFeature = .overlay
                    } else {
                        viewModel.setDisplayMode(mode)
                    }
                }
            }
        }
    }

    private func playbackRateSelector(wrapsDenseControls: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingS) {
            Text("Speed")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)

            AdaptiveSegmentGroup(
                items: Array(PlaybackRate.allCases),
                gridColumns: wrapsDenseControls ? 3 : nil
            ) { rate in
                proSegmentButton(
                    title: rate.label,
                    isSelected: viewModel.settings.playbackRate == rate,
                    showsBadge: rate.requiresPro && !canUse(.slowPlayback)
                ) {
                    if rate.requiresPro, !canUse(.slowPlayback) {
                        proPaywallFeature = .slowPlayback
                    } else {
                        viewModel.setPlaybackRate(rate)
                    }
                }
            }
        }
    }

    private func proSegmentButton(
        title: String,
        isSelected: Bool,
        showsBadge: Bool,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isSelected ? AppTheme.selectedText : AppTheme.unselectedText)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(
                    isSelected ? AppTheme.selectedSegment : Color.clear,
                    in: RoundedRectangle(cornerRadius: AppTheme.radiusS, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .proBadgeOverlay(showsBadge)
        .accessibilityIdentifier(accessibilityIdentifier ?? title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func stepSelector(wrapsDenseControls: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingS) {
            Text("Frame Step (Seconds)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)

            AdaptiveSegmentGroup(
                items: stepOptions,
                gridColumns: wrapsDenseControls ? 2 : nil
            ) { option in
                let requiresPro = stepRequiresPro(option.seconds)
                proSegmentButton(
                    title: option.label,
                    isSelected: isSelectedStep(option.seconds),
                    showsBadge: requiresPro && !canUse(.frameStep)
                ) {
                    if requiresPro, !canUse(.frameStep) {
                        proPaywallFeature = .frameStep
                    } else {
                        viewModel.setStepSeconds(option.seconds)
                    }
                }
            }
        }
    }

    private var stepOptions: [StepOption] {
        [
            StepOption(label: String(localized: "1/60 sec"), seconds: 1.0 / 60.0),
            StepOption(label: String(localized: "1/30 sec"), seconds: 1.0 / 30.0),
            StepOption(label: String(localized: "1/10 sec"), seconds: 0.1),
            StepOption(label: String(localized: "1/2 sec"), seconds: 0.5)
        ]
    }

    private func stepRequiresPro(_ seconds: Double) -> Bool {
        abs(seconds - 0.1) > 0.0001
    }

    private func isSelectedStep(_ seconds: Double) -> Bool {
        abs(viewModel.settings.stepSeconds - seconds) < 0.0001
    }

    private func loopControls(isCompact: Bool = false, wrapsDenseControls: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingS) {
            Text(loopStatusText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(AppTheme.secondaryText)

            if isCompact || wrapsDenseControls {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: AppTheme.spacingS),
                        GridItem(.flexible(), spacing: AppTheme.spacingS)
                    ],
                    spacing: AppTheme.spacingS
                ) {
                    loopStartButton
                    loopEndButton
                    loopToggleButton
                    loopClearButton
                }
            } else {
                HStack(spacing: AppTheme.spacingS) {
                    loopStartButton
                    loopEndButton
                    loopToggleButton
                    loopClearButton
                }
            }
        }
    }

    private var loopStartButton: some View {
        Button("Start") {
            performProFeature(.loop) {
                viewModel.markLoopStart()
            }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
        .frame(maxWidth: .infinity)
        .proBadgeOverlay(!canUse(.loop))
    }

    private var loopEndButton: some View {
        Button("End") {
            performProFeature(.loop) {
                viewModel.markLoopEnd()
            }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
        .frame(maxWidth: .infinity)
        .proBadgeOverlay(!canUse(.loop))
    }

    private var loopToggleButton: some View {
        Button(
            viewModel.settings.loopRange.isEnabled
                ? String(localized: "Loop OFF")
                : String(localized: "Loop ON")
        ) {
            performProFeature(.loop) {
                viewModel.toggleLoop()
            }
        }
        .buttonStyle(.borderedProminent)
        .foregroundStyle(AppTheme.accentText)
        .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
        .frame(maxWidth: .infinity)
        .proBadgeOverlay(!canUse(.loop))
    }

    private var loopClearButton: some View {
        Button("Clear") {
            viewModel.clearLoop()
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
        .frame(maxWidth: .infinity)
    }

    private var overlayControls: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingS) {
            HStack(spacing: AppTheme.spacingS) {
                Text("Overlay Alignment")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)

                Spacer(minLength: AppTheme.spacingS)

                Picker(
                    "Editing Video",
                    selection: Binding(
                        get: { viewModel.overlaySettings.editingSide },
                        set: { viewModel.updateOverlayEditingSide($0) }
                    )
                ) {
                    Text("Left").tag(VideoSide.left)
                    Text("Right").tag(VideoSide.right)
                }
                .pickerStyle(.segmented)
                .frame(minWidth: 108, maxWidth: 140)
            }

            overlayPrimaryControls

            DisclosureGroup(isExpanded: $showsOverlayDetails) {
                overlayDetailedControls
                    .padding(.top, AppTheme.spacingS)
            } label: {
                Text("Advanced Settings")
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier("compare.overlayDetails")
            }
            .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var overlayPrimaryControls: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingS) {
            HStack(spacing: AppTheme.spacingS) {
                Text("Position")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(minWidth: 38, alignment: .leading)

                overlayNudgeButton(systemImage: "arrow.left", x: -overlayNudgeStep, y: 0)
                overlayNudgeButton(systemImage: "arrow.up", x: 0, y: -overlayNudgeStep)
                overlayNudgeButton(systemImage: "arrow.down", x: 0, y: overlayNudgeStep)
                overlayNudgeButton(systemImage: "arrow.right", x: overlayNudgeStep, y: 0)
            }

            HStack(spacing: AppTheme.spacingS) {
                Text("Scale")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(minWidth: 38, alignment: .leading)

                overlayScaleButton(systemImage: "minus.magnifyingglass", delta: -overlayScaleStep)
                overlayScaleButton(systemImage: "plus.magnifyingglass", delta: overlayScaleStep)
            }

            HStack(spacing: AppTheme.spacingS) {
                Text("Rotation")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(minWidth: 38, alignment: .leading)

                overlayRotationButton(systemImage: "rotate.left", deltaDegrees: -overlayRotationStep)
                overlayRotationButton(systemImage: "rotate.right", deltaDegrees: overlayRotationStep)

                Button {
                    resetOverlayTransform()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.accent)
                .background(AppTheme.accent.opacity(0.20), in: RoundedRectangle(cornerRadius: AppTheme.radiusS, style: .continuous))
                .accessibilityLabel("Reset Overlay Alignment")
            }
        }
        .padding(AppTheme.spacingS)
        .background(AppTheme.subtleSurface, in: RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous))
    }

    private var overlayDetailedControls: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingS) {
            overlayStepRow(
                title: String(localized: "Move Step"),
                selection: $overlayNudgeStep,
                options: [
                    OverlayStepOption(label: "1px", value: 1),
                    OverlayStepOption(label: "5px", value: 5),
                    OverlayStepOption(label: "10px", value: 10)
                ]
            )

            overlayStepRow(
                title: String(localized: "Scale Step"),
                selection: $overlayScaleStep,
                options: [
                    OverlayStepOption(label: "0.01x", value: 0.01),
                    OverlayStepOption(label: "0.05x", value: 0.05)
                ]
            )

            overlayStepRow(
                title: String(localized: "Rotation Step"),
                selection: $overlayRotationStep,
                options: [
                    OverlayStepOption(label: "0.1°", value: 0.1),
                    OverlayStepOption(label: "1°", value: 1),
                    OverlayStepOption(label: "5°", value: 5)
                ]
            )

            overlaySlider(
                title: String(localized: "Opacity"),
                valueText: String(format: "%.0f%%", currentOverlayTransform.opacity * 100),
                range: 0...1,
                value: Binding(
                    get: { currentOverlayTransform.opacity },
                    set: { value in
                        viewModel.updateOverlayTransform { $0.opacity = value }
                    }
                )
            )

            overlaySlider(
                title: String(localized: "Scale"),
                valueText: String(format: "%.2fx", currentOverlayTransform.scale),
                range: 0.5...2,
                value: Binding(
                    get: { currentOverlayTransform.scale },
                    set: { value in
                        viewModel.updateOverlayTransform { $0.scale = value }
                    }
                )
            )

            overlaySlider(
                title: String(localized: "Rotation"),
                valueText: String(format: "%+.1f°", currentOverlayTransform.rotationDegrees),
                range: -180...180,
                value: Binding(
                    get: { currentOverlayTransform.rotationDegrees },
                    set: { value in
                        viewModel.updateOverlayTransform { $0.rotationDegrees = value }
                    }
                )
            )
        }
        .padding(AppTheme.spacingS)
        .background(AppTheme.subtleSurface, in: RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous))
    }

    private func overlayStepRow(
        title: String,
        selection: Binding<Double>,
        options: [OverlayStepOption]
    ) -> some View {
        HStack(spacing: AppTheme.spacingS) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .frame(minWidth: 62, alignment: .leading)

            Picker(title, selection: selection) {
                ForEach(options) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func resetOverlayTransform() {
        viewModel.updateOverlayTransform {
            $0.translateX = 0
            $0.translateY = 0
            $0.scale = 1
            $0.rotationDegrees = 0
        }
    }

    private func overlayNudgeButton(systemImage: String, x: Double, y: Double) -> some View {
        RepeatingIconButton(systemImage: systemImage) {
            viewModel.nudgeOverlayPosition(x: x, y: y)
        }
    }

    private func overlayScaleButton(systemImage: String, delta: Double) -> some View {
        RepeatingIconButton(systemImage: systemImage) {
            viewModel.nudgeOverlayScale(delta)
        }
    }

    private func overlayRotationButton(systemImage: String, deltaDegrees: Double) -> some View {
        RepeatingIconButton(systemImage: systemImage) {
            viewModel.nudgeOverlayRotation(deltaDegrees)
        }
    }

    private func overlaySlider(
        title: String,
        valueText: String,
        range: ClosedRange<Double>,
        value: Binding<Double>
    ) -> some View {
        HStack(spacing: AppTheme.spacingS) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .frame(minWidth: 62, alignment: .leading)

            Slider(value: value, in: range)

            Text(valueText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(AppTheme.secondaryText)
                .frame(minWidth: 50, alignment: .trailing)
        }
    }

    private var overlayPinchGesture: some Gesture {
        MagnificationGesture()
            .updating($overlayPinchMagnification) { value, state, _ in
                state = Double(value)
            }
            .onEnded { value in
                let baseScale = currentOverlayTransform.scale
                viewModel.updateOverlayTransform { $0.scale = baseScale * Double(value) }
            }
    }

    private var overlayDragGesture: some Gesture {
        DragGesture()
            .updating($overlayDragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                viewModel.updateOverlayTransform {
                    $0.translateX += value.translation.width
                    $0.translateY += value.translation.height
                }
            }
    }

    private func syncBadge(slot: VideoSlotState) -> some View {
        let text = slot.hasSyncPoint
            ? L10n.format("Reference %@", TimeFormatter.short(slot.syncPointSeconds))
            : String(localized: "Reference Not Set")

        return Text(text)
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(slot.hasSyncPoint ? AppTheme.accent : AppTheme.secondaryText)
            .padding(.horizontal, AppTheme.spacingS)
            .padding(.vertical, AppTheme.spacingXS)
            .background(AppTheme.subtleSurface, in: RoundedRectangle(cornerRadius: AppTheme.radiusS, style: .continuous))
    }

    private func replacementSelection(for side: VideoSide) -> Binding<PhotosPickerItem?> {
        Binding(
            get: {
                side == .left ? leftReplacement : rightReplacement
            },
            set: { newItem in
                if side == .left {
                    leftReplacement = newItem
                } else {
                    rightReplacement = newItem
                }

                guard let newItem else {
                    return
                }

                Task { @MainActor in
                    await viewModel.replaceVideo(on: side, with: newItem)
                    if side == .left {
                        leftReplacement = nil
                    } else {
                        rightReplacement = nil
                    }
                }
            }
        )
    }

    private func setSyncPointAndAdvance(_ side: VideoSide) {
        viewModel.setSyncPoint(side)

        if side == .left, !viewModel.rightSlot.hasSyncPoint {
            focusedSetupSide = .right
        } else if side == .right, !viewModel.leftSlot.hasSyncPoint {
            focusedSetupSide = .left
        }
    }

    private func setupVideoHeight(for size: CGSize, isLandscape: Bool) -> CGFloat {
        if usesTwoColumnSetup(for: size) {
            let candidate = size.height * (isLandscape ? 0.48 : 0.34)
            return min(max(candidate, 280), AppTheme.isRegularWidth(size) ? 520 : 340)
        }

        if isLandscape {
            return max(150, min(size.height - 210, 320))
        }

        let minimum: CGFloat = AppTheme.isCompactPhone(size) ? 220 : 250
        let maximum: CGFloat = AppTheme.isCompactPhone(size) ? 310 : 360
        return min(max(size.height * 0.36, minimum), maximum)
    }

    private func syncedPaneHeight(for size: CGSize, isLandscape: Bool) -> CGFloat {
        if usesSidebarLayout(for: size) {
            if viewModel.settings.displayMode == .stacked {
                let minimum: CGFloat = 220
                let maximum = max(minimum, (size.height - 170) / 2)
                return min(max(size.height * 0.38, minimum), maximum)
            }

            let minimum: CGFloat = 420
            let maximum = max(minimum, size.height - 120)
            return min(max(size.height * 0.78, minimum), maximum)
        }

        if AppTheme.isRegularWidth(size) {
            let candidate = size.height * (isLandscape ? 0.58 : 0.40)
            return min(max(candidate, 320), isLandscape ? 560 : 500)
        }

        if isLandscape {
            return max(150, min(size.height - 205, 320))
        }

        let minimum: CGFloat = AppTheme.isCompactPhone(size) ? 220 : 250
        let maximum: CGFloat = AppTheme.isCompactPhone(size) ? 310 : 360
        return min(max(size.height * 0.34, minimum), maximum)
    }

    private func overlayHeight(for size: CGSize, isLandscape: Bool) -> CGFloat {
        if usesSidebarLayout(for: size) {
            let maximum = max(420, size.height - 120)
            return min(max(size.height * 0.78, 420), maximum)
        }

        if AppTheme.isRegularWidth(size) {
            let candidate = size.height * (isLandscape ? 0.62 : 0.46)
            return min(max(candidate, 380), isLandscape ? 580 : 620)
        }

        if isLandscape {
            return max(170, min(size.height - 190, 320))
        }

        let minimum: CGFloat = AppTheme.isCompactPhone(size) ? 250 : 280
        let maximum: CGFloat = AppTheme.isCompactPhone(size) ? 330 : 380
        return min(max(size.height * 0.38, minimum), maximum)
    }

    private func usesTwoColumnSetup(for size: CGSize) -> Bool {
        size.width >= AppTheme.regularWidthBreakpoint
    }

    private func usesSidebarLayout(for size: CGSize) -> Bool {
        size.width >= AppTheme.wideLandscapeBreakpoint && size.width > size.height
    }

    private func compareSidebarWidth(for size: CGSize) -> CGFloat {
        let availableWidth = max(size.width - AppTheme.pageHorizontalPadding(for: size) * 2, 1)
        return AppTheme.clamped(availableWidth * 0.30, min: 340, max: 430)
    }

    private func compareContentWidthLimit(for size: CGSize) -> CGFloat {
        if size.width >= AppTheme.wideLandscapeBreakpoint {
            return usesSidebarLayout(for: size) ? min(size.width - AppTheme.spacingL * 2, 1600) : 1120
        }

        if AppTheme.isRegularWidth(size) {
            return min(size.width, 920)
        }

        return .infinity
    }

    private var currentOverlayTransform: OverlayTransform {
        viewModel.overlaySettings.transform(for: viewModel.overlaySettings.editingSide)
    }

    private var hasFullAccess: Bool {
        viewModel.isSample || purchaseManager.isProUnlocked || hasTrialAccess
    }

    private func canUse(_ feature: ProFeature) -> Bool {
        purchaseManager.canUse(
            feature,
            hasTrialAccess: viewModel.isSample || hasTrialAccess || canConfigureUpcomingTrial
        )
    }

    private var canConfigureUpcomingTrial: Bool {
        viewModel.compareMode == .setup && purchaseManager.hasRemainingTrialUses
    }

    private func performProFeature(_ feature: ProFeature, action: () -> Void) {
        guard canUse(feature) else {
            proPaywallFeature = feature
            return
        }

        action()
    }

    private func enforceEntitlements() {
        guard !hasFullAccess else {
            return
        }

        if viewModel.settings.displayMode.requiresPro {
            viewModel.setDisplayMode(.sideBySide)
        }

        if viewModel.settings.playbackRate.requiresPro {
            viewModel.setPlaybackRate(.normal)
        }

        if stepRequiresPro(viewModel.settings.stepSeconds) {
            viewModel.setStepSeconds(0.1)
        }

        if viewModel.settings.loopRange.isEnabled {
            viewModel.clearLoop()
        }
    }

    private func activateTrialForCurrentComparisonIfNeeded() {
        guard !purchaseManager.isProUnlocked else {
            return
        }

        let identity = viewModel.videoPairIdentity
        if hasTrialAccess, trialVideoPairIdentity == identity {
            return
        }

        hasTrialAccess = purchaseManager.beginFullFeatureComparison(isSample: viewModel.isSample)
        trialVideoPairIdentity = hasTrialAccess && !viewModel.isSample ? identity : nil

        if hasTrialAccess, !viewModel.isSample {
            viewModel.markTrialUseConsumed()
        } else if !hasTrialAccess {
            enforceEntitlements()
        }
    }

    private var loopStatusText: String {
        let loopRange = viewModel.settings.loopRange
        let state = loopRange.isEnabled ? "ON" : "OFF"

        guard loopRange.startSeconds != nil || loopRange.endSeconds != nil else {
            return L10n.format("Loop %@: Full Timeline", state)
        }

        let start = loopRange.startSeconds.map(signedTime) ?? String(localized: "Beginning")
        let end = loopRange.endSeconds.map(signedTime) ?? String(localized: "End")
        return L10n.format("Loop %@: %@ - %@", state, start, end)
    }

    private func signedTime(_ seconds: Double) -> String {
        let sign = seconds >= 0 ? "+" : "-"
        return "\(sign)\(TimeFormatter.short(abs(seconds)))"
    }
}

private struct OverlayStepOption: Identifiable {
    let label: String
    let value: Double

    var id: Double {
        value
    }
}

private struct StepOption: Identifiable {
    let label: String
    let seconds: Double

    var id: Double {
        seconds
    }
}

private struct TappableSeekSlider: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let isEnabled: Bool
    private let onEditingChanged: (Bool) -> Void
    @State private var isEditing = false

    init(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        isEnabled: Bool = true,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self._value = value
        self.range = range
        self.isEnabled = isEnabled
        self.onEditingChanged = onEditingChanged
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Slider(value: sliderValue, in: sliderRange)
                    .disabled(!isEnabled)
                    .allowsHitTesting(false)

                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(seekGesture(width: proxy.size.width))
            }
        }
        .frame(height: 34)
    }

    private var sliderValue: Binding<Double> {
        Binding(
            get: {
                Self.clamped(value, in: sliderRange)
            },
            set: { newValue in
                value = Self.clamped(newValue, in: sliderRange)
            }
        )
    }

    private var sliderRange: ClosedRange<Double> {
        let lower = range.lowerBound.isFinite ? range.lowerBound : 0
        let upperCandidate = range.upperBound.isFinite ? range.upperBound : lower
        let upper = max(upperCandidate, lower + 0.01)
        return lower...upper
    }

    private func seekGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isEnabled else {
                    return
                }

                if !isEditing {
                    isEditing = true
                    onEditingChanged(true)
                }

                updateValue(at: value.location.x, width: width)
            }
            .onEnded { value in
                guard isEnabled else {
                    return
                }

                if !isEditing {
                    onEditingChanged(true)
                }

                updateValue(at: value.location.x, width: width)
                isEditing = false
                onEditingChanged(false)
            }
    }

    private func updateValue(at locationX: CGFloat, width: CGFloat) {
        let safeWidth = max(width, 1)
        let ratio = min(max(Double(locationX / safeWidth), 0), 1)
        let range = sliderRange
        value = range.lowerBound + (range.upperBound - range.lowerBound) * ratio
    }

    private static func clamped(_ value: Double, in range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

private struct RepeatingIconButton: View {
    let systemImage: String
    let action: () -> Void
    @State private var isPressing = false
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        Image(systemName: systemImage)
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: 40)
            .foregroundStyle(AppTheme.accent)
            .background(AppTheme.accent.opacity(0.20), in: RoundedRectangle(cornerRadius: AppTheme.radiusS, style: .continuous))
            .contentShape(Rectangle())
            .opacity(isPressing ? 0.74 : 1)
            .accessibilityAddTraits(.isButton)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        startPressing()
                    }
                    .onEnded { _ in
                        stopRepeating()
                    }
            )
            .onDisappear {
                stopRepeating()
            }
    }

    private func startPressing() {
        guard !isPressing else {
            return
        }

        isPressing = true
        action()
        repeatTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)

            while !Task.isCancelled {
                action()
                try? await Task.sleep(nanoseconds: 70_000_000)
            }
        }
    }

    private func stopRepeating() {
        isPressing = false
        repeatTask?.cancel()
        repeatTask = nil
    }
}

#if DEBUG
#Preview {
    CompareView(
        leftVideo: VideoItem(
            url: URL(fileURLWithPath: "/tmp/left.mov"),
            fileName: "left.mov",
            durationSeconds: 10,
            isReady: true
        ),
        rightVideo: VideoItem(
            url: URL(fileURLWithPath: "/tmp/right.mov"),
            fileName: "right.mov",
            durationSeconds: 12,
            isReady: true
        )
    )
    .environmentObject(PurchaseManager())
}
#endif
