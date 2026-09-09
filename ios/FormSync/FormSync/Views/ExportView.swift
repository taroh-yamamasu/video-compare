import SwiftUI
import UIKit

struct ExportView: View {
    @ObservedObject var viewModel: CompareViewModel
    let hasTrialAccess: Bool
    private let startsWithQuickExport: Bool
    private let settingsStore: SettingsStore
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var options: ExportOptions
    @State private var hasStartedQuickExport = false
    @State private var exportTask: Task<Void, Never>?
    @State private var shareResult: ExportResult?
    @State private var pendingSharedExportURL: URL?
    @State private var proPaywallFeature: ProFeature?
    @State private var backgroundTask = ExportBackgroundTask()

    init(
        viewModel: CompareViewModel,
        hasTrialAccess: Bool,
        startsWithQuickExport: Bool = false,
        settingsStore: SettingsStore = SettingsStore()
    ) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        self.hasTrialAccess = hasTrialAccess
        self.startsWithQuickExport = startsWithQuickExport
        self.settingsStore = settingsStore
        _options = State(initialValue: settingsStore.quickExportPreset?.options ?? ExportOptions())
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    exportContent(size: proxy.size)
                        .padding(.horizontal, AppTheme.pageHorizontalPadding(for: proxy.size))
                        .padding(.vertical, AppTheme.pageVerticalPadding(for: proxy.size))
                        .frame(maxWidth: exportContentWidthLimit(for: proxy.size), alignment: .topLeading)
                        .frame(maxWidth: .infinity)
                }
                .background(AppTheme.background.ignoresSafeArea())
            }
            .navigationTitle("Export")
            .accessibilityIdentifier("export.screen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        exportTask?.cancel()
                        dismiss()
                    }
                    .disabled(viewModel.isExporting)
                }
            }
            .sheet(item: $shareResult, onDismiss: cleanupSharedExport) { result in
                ShareSheet(activityItems: [result.url]) {
                    cleanupSharedExport()
                }
            }
            .sheet(item: $proPaywallFeature) { feature in
                ProPaywallView(feature: feature)
                    .presentationDetents([.medium, .large])
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    backgroundTask.end()
                } else if phase == .background, viewModel.isExporting, !backgroundTask.isActive {
                    startBackgroundTask()
                }
            }
            .onDisappear {
                cancelExport()
            }
            .onAppear {
                startQuickExportIfPossible()
            }
        }
    }

    @ViewBuilder
    private func exportContent(size: CGSize) -> some View {
        if AppTheme.isRegularWidth(size) {
            let leadingColumnWidth = AppTheme.splitLeadingColumnWidth(for: size, preferred: 300)

            HStack(alignment: .top, spacing: AppTheme.spacingL) {
                VStack(alignment: .leading, spacing: AppTheme.spacingL) {
                    exportHeader
                    actionButtons

                    if viewModel.isExporting {
                        progressView
                    }
                }
                .frame(width: leadingColumnWidth, alignment: .topLeading)

                VStack(alignment: .leading, spacing: AppTheme.spacingL) {
                    exportSettings
                    messageView
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: AppTheme.spacingL) {
                exportHeader
                exportSettings
                messageView

                if viewModel.isExporting {
                    progressView
                }

                actionButtons
            }
        }
    }

    private func exportContentWidthLimit(for size: CGSize) -> CGFloat {
        AppTheme.isRegularWidth(size) ? min(size.width, 920) : AppTheme.contentMaxWidth
    }

    private var exportHeader: some View {
        HStack(alignment: .center, spacing: AppTheme.spacingM) {
            VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                Text("Export")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.accentText)

                Text(exportHeaderDetail)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.accentText.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: AppTheme.spacingS)

            Image(systemName: options.format == .image ? "photo.fill" : "video.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.accentText)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.10), in: RoundedRectangle(cornerRadius: AppTheme.radiusS, style: .continuous))
        }
        .padding(AppTheme.spacingL)
        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous)
                .stroke(Color.black.opacity(0.12))
        )
    }

    private var exportSettings: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingM) {
            AdaptiveSegmentGroup(items: Array(ExportFormat.allCases)) { format in
                exportSegmentButton(
                    title: format.label,
                    isSelected: options.format == format,
                    showsBadge: format == .video && !canUse(.videoExport)
                ) {
                    if format == .video, !canUse(.videoExport) {
                        proPaywallFeature = .videoExport
                        options.format = .image
                        options.range = .currentFrame
                        options.resolution = .p720
                        options.audioSource = .none
                    } else {
                        options.format = format
                        if format == .image {
                            options.range = .currentFrame
                            options.audioSource = .none
                        } else if options.range == .currentFrame {
                            options.range = .full
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: AppTheme.spacingS) {
                Text("Range")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)

                if options.format == .image {
                    Text(ExportRange.currentFrame.label)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppTheme.spacingM)
                        .background(AppTheme.subtleSurface, in: RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous))
                } else {
                    Picker("Range", selection: videoRangeBinding) {
                        Text(ExportRange.full.label).tag(ExportRange.full)
                        Text(ExportRange.loop.label).tag(ExportRange.loop)
                    }
                    .pickerStyle(.segmented)

                    if !viewModel.canExportLoopRange {
                        Text("Turn on a loop before exporting the loop range.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.tertiaryText)
                    }
                }
            }

            AdaptiveSegmentGroup(items: Array(ExportResolution.allCases)) { resolution in
                exportSegmentButton(
                    title: resolution.label,
                    isSelected: options.resolution == resolution,
                    showsBadge: resolution.requiresPro && !canUse(.highResolutionExport)
                ) {
                    if resolution.requiresPro, !canUse(.highResolutionExport) {
                        proPaywallFeature = .highResolutionExport
                        options.resolution = .p720
                    } else {
                        options.resolution = resolution
                    }
                }
            }

            if !canUse(.watermarkFreeImageExport) {
                Button {
                    proPaywallFeature = .watermarkFreeImageExport
                } label: {
                    HStack(spacing: AppTheme.spacingS) {
                        VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                            Text("Free exports include a KinePair watermark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.primaryText)
                            Text("PRO unlocks watermark-free export.")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer(minLength: AppTheme.spacingS)
                    }
                }
                .buttonStyle(.plain)
                .proBadgeOverlay(true)
                .padding(AppTheme.spacingS)
                .background(AppTheme.subtleSurface, in: RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous))
            }

            if options.format == .video {
                VStack(alignment: .leading, spacing: AppTheme.spacingS) {
                    Text("Audio")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)

                    Picker("Audio", selection: $options.audioSource) {
                        ForEach(ExportAudioSource.allCases) { audioSource in
                            Text(audioSource.label).tag(audioSource)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .appCard(padding: AppTheme.spacingL)
        .disabled(viewModel.isExporting)
    }

    @ViewBuilder
    private var messageView: some View {
        if let errorMessage = viewModel.errorMessage {
            VStack(alignment: .leading, spacing: AppTheme.spacingS) {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(AppTheme.error)
                    .fixedSize(horizontal: false, vertical: true)

                if let recoverySuggestion {
                    Text(recoverySuggestion)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if canOpenPhotoSettings {
                    Button {
                        openSettings()
                    } label: {
                        Label("Open Settings", systemImage: "gear")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
                }
            }
            .appCard()
        } else if let toastMessage = viewModel.toastMessage {
            Label(toastMessage, systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard()
        }
    }

    private var exportHeaderDetail: String {
        let range = effectiveOptions.range.label
        return "\(viewModel.settings.displayMode.label) / \(range) / \(options.resolution.label)"
    }

    private var progressView: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingM) {
            Text(viewModel.exportProgress.message)
                .font(.callout.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)

            ProgressView(value: viewModel.exportProgress.fraction)
                .progressViewStyle(.linear)

            Button(role: .cancel) {
                cancelExport()
            } label: {
                Label("Cancel", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
        }
        .appCard()
    }

    private var actionButtons: some View {
        VStack(spacing: AppTheme.spacingS) {
            Button {
                startPhotoSave()
            } label: {
                Label("Save to Photos", systemImage: "photo.badge.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(AppTheme.accentText)
            .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
            .controlSize(.large)
            .disabled(viewModel.isExporting || !canStartExport)

            Button {
                startShare()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
            .controlSize(.large)
            .disabled(viewModel.isExporting || !canStartExport)
        }
    }

    private var canStartExport: Bool {
        options.format == .image || options.range != .loop || viewModel.canExportLoopRange
    }

    private var recoverySuggestion: String? {
        if viewModel.errorMessage == AppError.photoPermissionDenied.errorDescription {
            return AppError.photoPermissionDenied.recoverySuggestion
        }

        if viewModel.errorMessage == AppError.insufficientStorage.errorDescription {
            return AppError.insufficientStorage.recoverySuggestion
        }

        if viewModel.errorMessage == AppError.exportRangeUnavailable.errorDescription {
            return AppError.exportRangeUnavailable.recoverySuggestion
        }

        if viewModel.errorMessage == AppError.videoExportFailed.errorDescription {
            return AppError.videoExportFailed.recoverySuggestion
        }

        if viewModel.errorMessage == AppError.imageGenerationFailed.errorDescription {
            return AppError.imageGenerationFailed.recoverySuggestion
        }

        return nil
    }

    private var canOpenPhotoSettings: Bool {
        viewModel.errorMessage == AppError.photoPermissionDenied.errorDescription
    }

    private var hasFullAccess: Bool {
        purchaseManager.isProUnlocked || hasTrialAccess
    }

    private func canUse(_ feature: ProFeature) -> Bool {
        purchaseManager.canUse(feature, hasTrialAccess: hasTrialAccess)
    }

    private var formatBinding: Binding<ExportFormat> {
        Binding(
            get: { options.format },
            set: { format in
                if format == .video, !canUse(.videoExport) {
                    proPaywallFeature = .videoExport
                    options.format = .image
                    options.range = .currentFrame
                    options.resolution = .p720
                    options.audioSource = .none
                    return
                }

                options.format = format
                if format == .image {
                    options.range = .currentFrame
                    options.audioSource = .none
                } else if options.range == .currentFrame {
                    options.range = .full
                }
            }
        )
    }

    private func exportSegmentButton(
        title: String,
        isSelected: Bool,
        showsBadge: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .foregroundStyle(isSelected ? AppTheme.selectedText : AppTheme.unselectedText)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(
                    isSelected ? AppTheme.selectedSegment : Color.clear,
                    in: RoundedRectangle(cornerRadius: AppTheme.radiusS, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .proBadgeOverlay(showsBadge)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var resolutionBinding: Binding<ExportResolution> {
        Binding(
            get: { options.resolution },
            set: { resolution in
                if resolution.requiresPro, !canUse(.highResolutionExport) {
                    proPaywallFeature = .highResolutionExport
                    options.resolution = .p720
                    return
                }

                options.resolution = resolution
            }
        )
    }

    private var videoRangeBinding: Binding<ExportRange> {
        Binding(
            get: {
                options.range == .currentFrame ? .full : options.range
            },
            set: { range in
                if range == .loop, !viewModel.canExportLoopRange {
                    options.range = .full
                } else {
                    options.range = range
                }
            }
        )
    }

    private var effectiveOptions: ExportOptions {
        var next = options
        if !hasFullAccess {
            next.format = .image
            next.range = .currentFrame
            next.resolution = .p720
            next.audioSource = .none
            next.includesWatermark = true
            return next
        }

        next.includesWatermark = false
        if next.format == .image {
            next.range = .currentFrame
            next.audioSource = .none
        } else if next.range == .currentFrame {
            next.range = .full
        }
        return next
    }

    private func startPhotoSave() {
        guard exportTask == nil, canStartExport else {
            return
        }

        saveQuickExportPreset(destination: .photoLibrary)
        startBackgroundTask()
        exportTask = Task { @MainActor in
            defer {
                backgroundTask.end()
                exportTask = nil
            }
            await viewModel.exportToPhotoLibrary(options: effectiveOptions)
        }
    }

    private func startShare() {
        guard exportTask == nil, canStartExport else {
            return
        }

        saveQuickExportPreset(destination: .share)
        startBackgroundTask()
        exportTask = Task { @MainActor in
            defer {
                backgroundTask.end()
                exportTask = nil
            }
            let result = await viewModel.exportForSharing(options: effectiveOptions)
            if let result {
                pendingSharedExportURL = result.url
                shareResult = result
            }
        }
    }

    private func startQuickExportIfPossible() {
        guard startsWithQuickExport, !hasStartedQuickExport else {
            return
        }
        hasStartedQuickExport = true

        guard let preset = settingsStore.quickExportPreset?.validated(
            hasFullAccess: hasFullAccess,
            canExportLoopRange: viewModel.canExportLoopRange
        ) else {
            options = ExportOptions()
            return
        }

        options = preset.options
        switch preset.destination {
        case .photoLibrary:
            startPhotoSave()
        case .share:
            startShare()
        }
    }

    private func saveQuickExportPreset(destination: ExportDestination) {
        let current = effectiveOptions
        settingsStore.saveQuickExportPreset(
            QuickExportPreset(
                format: current.format,
                range: current.range,
                resolution: current.resolution,
                audioSource: current.audioSource,
                destination: destination
            )
        )
    }

    private func startBackgroundTask() {
        backgroundTask.begin {
            exportTask?.cancel()
        }
    }

    private func cancelExport() {
        exportTask?.cancel()
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        openURL(url)
    }

    private func cleanupSharedExport() {
        if let pendingSharedExportURL {
            try? FileManager.default.removeItem(at: pendingSharedExportURL)
        }
        pendingSharedExportURL = nil
        shareResult = nil
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var onComplete: () -> Void = {}

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            DispatchQueue.main.async {
                onComplete()
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

@MainActor
private final class ExportBackgroundTask {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private var expirationHandler: (() -> Void)?

    var isActive: Bool {
        identifier != .invalid
    }

    func begin(expirationHandler: @escaping () -> Void) {
        end()
        self.expirationHandler = expirationHandler
        identifier = UIApplication.shared.beginBackgroundTask(withName: "FormSyncExport") { [weak self] in
            Task { @MainActor in
                self?.expirationHandler?()
                self?.end()
            }
        }
    }

    func end() {
        guard identifier != .invalid else {
            expirationHandler = nil
            return
        }

        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
        expirationHandler = nil
    }

    deinit {
        let taskIdentifier = identifier
        if taskIdentifier != .invalid {
            Task { @MainActor in
                UIApplication.shared.endBackgroundTask(taskIdentifier)
            }
        }
    }
}

#if DEBUG
#Preview {
    ExportView(
        viewModel: CompareViewModel(
            leftVideo: VideoItem(url: URL(fileURLWithPath: "/tmp/left.mov"), fileName: "left.mov", durationSeconds: 8),
            rightVideo: VideoItem(url: URL(fileURLWithPath: "/tmp/right.mov"), fileName: "right.mov", durationSeconds: 9)
        ),
        hasTrialAccess: false
    )
}
#endif
