import PhotosUI
import SafariServices
import StoreKit
import SwiftUI
import UIKit

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @State private var showsSettings = false
    @State private var showsHistory = false
    @State private var showsTutorial = false
    @State private var showsUpdateNotice = false
    @Environment(\.requestReview) private var requestReview

    private let settingsStore = SettingsStore()

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let horizontalPadding = AppTheme.pageHorizontalPadding(for: proxy.size)
                let verticalPadding = AppTheme.pageVerticalPadding(for: proxy.size)

                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.spacingL) {
                        heroVideoPicker(size: proxy.size)
                        continueLastSessionButton
                        sampleComparisonButton
                        historyPanel

                        if viewModel.isLoading {
                            HStack(spacing: AppTheme.spacingM) {
                                ProgressView()
                                Text(viewModel.loadingMessage ?? String(localized: "Loading…"))
                                    .font(.callout)
                            }
                            .foregroundStyle(AppTheme.secondaryText)
                            .appCard()
                        }

                        if let errorMessage = viewModel.errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(AppTheme.error)
                                .fixedSize(horizontal: false, vertical: true)
                                .appCard()
                        }

                        Spacer(minLength: AppTheme.spacingS)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, verticalPadding)
                    .padding(.bottom, AppTheme.spacingL)
                    .frame(maxWidth: AppTheme.contentWidthLimit(for: proxy.size), alignment: .topLeading)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                }
                .background(AppTheme.background.ignoresSafeArea())
            }
            .navigationTitle("KinePair")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityIdentifier("home.settings")
                    .accessibilityLabel("Settings")
                }
            }
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showsSettings) {
                SettingsView()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showsHistory) {
                SessionHistoryView(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showsTutorial) {
                TutorialView {
                    settingsStore.markOnboardingSeen()
                    settingsStore.markV13UpdateNoticeSeen()
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showsUpdateNotice) {
                V13UpdateNoticeView {
                    settingsStore.markV13UpdateNoticeSeen()
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .navigationDestination(item: $viewModel.loadedPair) { pair in
                CompareView(pair: pair)
            }
            .onAppear {
                refreshSessionsForCurrentAccess()
                if !settingsStore.hasSeenOnboarding {
                    showsTutorial = true
                } else if settingsStore.shouldShowV13UpdateNotice {
                    showsUpdateNotice = true
                }
                scheduleReviewRequestIfNeeded()
            }
            .onChange(of: purchaseManager.isProUnlocked) { _, _ in
                refreshSessionsForCurrentAccess()
            }
            .onChange(of: purchaseManager.remainingTrialUses) { _, _ in
                refreshSessionsForCurrentAccess()
            }
        }
    }

    private func refreshSessionsForCurrentAccess() {
        viewModel.refreshSessions(
            hasExpandedHistoryAccess: purchaseManager.hasExpandedHistoryAccess
        )
    }

    private func scheduleReviewRequestIfNeeded() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))

            guard !showsSettings, !showsHistory, !showsTutorial,
                  settingsStore.consumePendingReviewRequest() else {
                return
            }

            requestReview()
        }
    }

    private func heroVideoPicker(size: CGSize) -> some View {
        PhotosPicker(
            selection: Binding(
                get: { viewModel.selectedItems },
                set: { newItems in
                    viewModel.selectedItems = newItems
                    Task {
                        await viewModel.loadSelectedVideos(
                            isProUnlocked: purchaseManager.isProUnlocked
                        )
                    }
                }
            ),
            maxSelectionCount: 2,
            matching: .videos,
            preferredItemEncoding: .current
        ) {
            heroPanel(size: size)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
        .accessibilityLabel("Choose Two Videos")
    }

    private func heroPanel(size: CGSize) -> some View {
        let isCompact = AppTheme.isCompactPhone(size)
        let isRegular = AppTheme.isRegularWidth(size)
        let usesWideHero = usesWideHeroLayout(for: size)
        let titleSize: CGFloat = isCompact ? 32 : 40
        let panelMinHeight: CGFloat = usesWideHero
            ? AppTheme.clamped(size.height * 0.36, min: 260, max: 340)
            : (isRegular ? AppTheme.clamped(size.height * 0.42, min: 340, max: 410) : (isCompact ? 286 : 320))
        let panelPadding: CGFloat = isCompact ? AppTheme.spacingM : AppTheme.spacingL

        return Group {
            if usesWideHero {
                HStack(alignment: .center, spacing: AppTheme.spacingXL) {
                    VStack(alignment: .leading, spacing: AppTheme.spacingXL) {
                        heroCopy(titleSize: titleSize)
                        heroActionBlock
                    }
                    .frame(width: wideHeroCopyWidth(for: size), alignment: .leading)

                    heroComparisonPreview(height: heroIllustrationHeight(for: size))
                        .frame(maxWidth: .infinity)
                        .padding(.trailing, AppTheme.spacingL)
                }
            } else {
                VStack(alignment: .leading, spacing: AppTheme.spacingM) {
                    heroCopy(titleSize: titleSize)

                    heroComparisonPreview(height: heroIllustrationHeight(for: size))
                        .padding(.top, AppTheme.spacingXS)
                        .padding(.bottom, AppTheme.spacingS)

                    heroActionBlock
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: panelMinHeight, alignment: usesWideHero ? .center : .topLeading)
        .padding(panelPadding)
        .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous)
                .stroke(AppTheme.divider)
        )
        .shadow(color: .black.opacity(0.28), radius: 22, x: 0, y: 14)
    }

    private func heroCopy(titleSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingM) {
            Text("KinePair")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, AppTheme.spacingS)
                .padding(.vertical, AppTheme.spacingXS)
                .background(AppTheme.accentSurface, in: RoundedRectangle(cornerRadius: AppTheme.radiusS, style: .continuous))

            Text("Compare two movements in seconds")
                .font(.system(size: titleSize, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(3)
                .minimumScaleFactor(0.76)
                .padding(.top, AppTheme.spacingS)
        }
    }

    private var heroActionBlock: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingS) {
            Text("New Comparison")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)

            Label("Choose Two Videos", systemImage: "plus")
                .font(.headline.weight(.black))
                .foregroundStyle(AppTheme.accentText)
                .frame(maxWidth: .infinity, minHeight: AppTheme.minimumTouchTarget)
                .padding(.horizontal, AppTheme.spacingM)
                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: AppTheme.radiusS, style: .continuous))

            if !purchaseManager.isProUnlocked {
                Label(trialStatusText, systemImage: purchaseManager.hasRemainingTrialUses ? "sparkles" : "lock")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var continueLastSessionButton: some View {
        if let session = viewModel.latestSession {
            Button {
                Task {
                    await viewModel.openSession(session)
                }
            } label: {
                HStack(spacing: AppTheme.spacingM) {
                    Image(systemName: "play.fill")
                        .font(.headline.weight(.black))
                        .foregroundStyle(AppTheme.accentText)
                        .frame(width: AppTheme.minimumTouchTarget, height: AppTheme.minimumTouchTarget)
                        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: AppTheme.radiusS, style: .continuous))

                    VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                        Text("Resume your latest comparison")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.accent)

                        Text(session.title)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)

                        HStack(spacing: AppTheme.spacingXS) {
                            Text(session.settings.displayMode.label)
                            Text("·")
                            Text(
                                session.hasSyncPoints
                                    ? String(localized: "Reference points set")
                                    : String(localized: "Reference points not set")
                            )
                            Text("·")
                            Text(session.updatedAt, style: .relative)
                        }
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                    }

                    Spacer(minLength: AppTheme.spacingS)

                    Image(systemName: "chevron.right")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(AppTheme.tertiaryText)
                }
                .padding(AppTheme.spacingM)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.backgroundSecondary, in: RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous)
                        .stroke(AppTheme.accentBorder)
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
            .accessibilityIdentifier("home.continueLastSession")
        }
    }

    private var trialStatusText: String {
        if purchaseManager.hasRemainingTrialUses {
            if purchaseManager.remainingTrialUses == 1 {
                return String(localized: "Full-feature trial: 1 remaining")
            }
            return L10n.format("Full-feature trial: %d remaining", purchaseManager.remainingTrialUses)
        }

        return String(localized: "Basic comparison is free")
    }

    private var sampleComparisonButton: some View {
        Button {
            viewModel.loadSampleVideos()
        } label: {
            HStack(spacing: AppTheme.spacingM) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.subtleSurface, in: RoundedRectangle(cornerRadius: AppTheme.radiusS, style: .continuous))

                VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                    Text("Try Sample")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)

                    Text("No Photos access required. PRO features included.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: AppTheme.spacingS)

                Image(systemName: "chevron.right")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .padding(AppTheme.spacingM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous)
                    .stroke(AppTheme.accentBorder)
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
        .accessibilityIdentifier("home.trySample")
        .accessibilityLabel("Try Sample Comparison")
    }

    private func heroComparisonPreview(height: CGFloat) -> some View {
        Image("HomePanelIllustration")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(AppTheme.accent)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .padding(.horizontal, AppTheme.spacingM)
            .background(AppTheme.backgroundPrimary, in: RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous))
            .accessibilityHidden(true)
    }

    private func heroIllustrationHeight(for size: CGSize) -> CGFloat {
        if usesWideHeroLayout(for: size) {
            return AppTheme.clamped(size.height * 0.28, min: 200, max: 260)
        }

        if AppTheme.isRegularWidth(size) {
            return AppTheme.clamped(size.height * 0.20, min: 170, max: 240)
        }

        return AppTheme.isCompactPhone(size) ? 126 : AppTheme.clamped(size.height * 0.18, min: 140, max: 170)
    }

    private func wideHeroCopyWidth(for size: CGSize) -> CGFloat {
        AppTheme.clamped(size.width * 0.22, min: 220, max: 300)
    }

    private func usesWideHeroLayout(for size: CGSize) -> Bool {
        size.width >= AppTheme.wideLandscapeBreakpoint && size.width > size.height
    }

    @ViewBuilder
    private var historyPanel: some View {
        if !viewModel.sessions.isEmpty {
            Button {
                showsHistory = true
            } label: {
                historyCard(isEnabled: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View Comparison History")
        }
    }

    private func historyCard(isEnabled: Bool) -> some View {
        HStack(spacing: AppTheme.spacingM) {
            VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                Text("History")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.primaryText)

                Text(historyDetailText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer(minLength: AppTheme.spacingM)

            Image(systemName: isEnabled ? "clock.arrow.circlepath" : "clock")
                .font(.title3.weight(.bold))
                .foregroundStyle(isEnabled ? AppTheme.accent : AppTheme.tertiaryText)
                .frame(width: 42, height: 42)
                .background(AppTheme.subtleSurface, in: RoundedRectangle(cornerRadius: AppTheme.radiusS, style: .continuous))
        }
        .padding(AppTheme.spacingL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous)
                .stroke(isEnabled ? AppTheme.accentBorder : AppTheme.border)
        )
        .opacity(isEnabled ? 1 : 0.72)
    }

    private var historyDetailText: String {
        guard !viewModel.sessions.isEmpty else {
            return String(localized: "No comparison history yet")
        }

        if !purchaseManager.hasExpandedHistoryAccess {
            return String(localized: "Resume your latest comparison")
        }

        if viewModel.sessions.count == 1 {
            return String(localized: "Resume 1 comparison")
        }

        return L10n.format("Resume %d comparisons", viewModel.sessions.count)
    }

}

#if DEBUG
#Preview {
    HomeView()
        .environmentObject(PurchaseManager())
}
#endif

private struct SessionHistoryView: View {
    @ObservedObject var viewModel: HomeViewModel
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @State private var proPaywallFeature: ProFeature?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    LazyVStack(spacing: AppTheme.spacingS) {
                        if !purchaseManager.hasExpandedHistoryAccess {
                            Button {
                                proPaywallFeature = .multipleHistory
                            } label: {
                                HStack(spacing: AppTheme.spacingS) {
                                    ProBadge()
                                    Text("The free version shows your latest comparison. Buy PRO to restore access to multiple saved comparisons.")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.primaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .appCard()
                        }

                        if viewModel.sessions.isEmpty {
                            Text("No comparison history yet.")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(AppTheme.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .appCard()
                        } else {
                            ForEach(viewModel.sessions) { session in
                                SessionHistoryRow(session: session) {
                                    Task {
                                        await viewModel.openSession(session)
                                        dismiss()
                                    }
                                } onDelete: {
                                    viewModel.deleteSession(session)
                                } onRename: { title in
                                    viewModel.renameSession(
                                        session,
                                        title: title,
                                        hasExpandedHistoryAccess: purchaseManager.hasExpandedHistoryAccess
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.pageHorizontalPadding(for: proxy.size))
                    .padding(.vertical, AppTheme.pageVerticalPadding(for: proxy.size))
                    .frame(maxWidth: AppTheme.formWidthLimit(for: proxy.size), alignment: .topLeading)
                    .frame(maxWidth: .infinity)
                }
                .background(AppTheme.background.ignoresSafeArea())
            }
            .navigationTitle("Comparison History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(item: $proPaywallFeature) { feature in
                ProPaywallView(feature: feature)
                    .presentationDetents([.medium, .large])
            }
        }
    }
}

private struct SessionHistoryRow: View {
    let session: CompareSession
    let onOpen: () -> Void
    let onDelete: () -> Void
    let onRename: (String) -> Void
    @State private var isRenaming = false
    @State private var draftTitle = ""
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        HStack(spacing: AppTheme.spacingS) {
            VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                HStack(spacing: AppTheme.spacingS) {
                    if isRenaming {
                        TextField("Comparison Name", text: $draftTitle)
                            .font(.callout.weight(.bold))
                            .foregroundStyle(AppTheme.primaryText)
                            .textInputAutocapitalization(.never)
                            .submitLabel(.done)
                            .focused($isTitleFocused)
                            .onSubmit(commitRename)
                    } else {
                        Text(session.title)
                            .font(.callout.weight(.bold))
                            .foregroundStyle(AppTheme.primaryText)
                            .lineLimit(1)
                            .onTapGesture(count: 2, perform: beginRename)

                        if session.hasSyncPoints {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                }

                Text(sessionSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)

                Text(isRenaming ? String(localized: "Press Return to save the name") : updatedText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                if !isRenaming {
                    onOpen()
                }
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
            .accessibilityLabel(L10n.format("Delete %@", session.title))
        }
        .padding(AppTheme.spacingM)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous)
                .stroke(AppTheme.border)
        )
        .onAppear {
            draftTitle = session.title
        }
        .onChange(of: session.title) { _, title in
            if !isRenaming {
                draftTitle = title
            }
        }
    }

    private func beginRename() {
        draftTitle = session.title
        isRenaming = true
        isTitleFocused = true
    }

    private func commitRename() {
        let trimmedTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty, trimmedTitle != session.title {
            onRename(trimmedTitle)
        }

        isRenaming = false
        isTitleFocused = false
    }

    private var sessionSummary: String {
        "\(session.settings.displayMode.label) / \(syncStatusText)"
    }

    private var syncStatusText: String {
        session.hasSyncPoints
            ? String(localized: "Reference points set")
            : String(localized: "Reference points not set")
    }

    private var updatedText: String {
        Self.dateFormatter.string(from: session.updatedAt)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss
    let onFinish: () -> Void
    @State private var didFinish = false
    @State private var page = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: AppTheme.spacingM) {
                TabView(selection: $page) {
                    tutorialPage(
                        systemImage: "rectangle.split.2x1",
                        title: "Compare Two Videos",
                        detail: "Choose two videos and review them side by side or stacked.",
                        page: 0
                    )

                    tutorialPage(
                        systemImage: "scope",
                        title: "Sync the Key Moment",
                        detail: "Set a reference point in each video, then use synchronized playback, slow motion, frame stepping, and loops.",
                        page: 1
                    )

                    tutorialPage(
                        systemImage: "lock.shield.fill",
                        title: "Private by Design",
                        detail: "Videos stay on your device. No account is required, and your first three comparisons include all KinePair PRO features.",
                        page: 2
                    )
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Button {
                    if page < 2 {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            page += 1
                        }
                    } else {
                        finish()
                    }
                } label: {
                    Text(page < 2 ? String(localized: "Next") : String(localized: "Start Comparing"))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.accentText)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
                .controlSize(.large)
                .padding(.horizontal, AppTheme.spacingL)
                .padding(.bottom, AppTheme.spacingL)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("How It Works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        finish()
                    }
                }
            }
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onDisappear {
                finishIfNeeded()
            }
        }
    }

    private func tutorialPage(systemImage: String, title: LocalizedStringKey, detail: LocalizedStringKey, page: Int) -> some View {
        VStack(spacing: AppTheme.spacingL) {
            Spacer(minLength: AppTheme.spacingM)

            Image(systemName: systemImage)
                .font(.system(size: 54, weight: .bold))
                .foregroundStyle(AppTheme.accentText)
                .frame(width: 112, height: 112)
                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous))

            Text(title)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
                .multilineTextAlignment(.center)

            Text(detail)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 480)

            Spacer(minLength: AppTheme.spacingXL)
        }
        .padding(.horizontal, AppTheme.spacingXL)
        .tag(page)
    }

    private func finish() {
        finishIfNeeded()
        dismiss()
    }

    private func finishIfNeeded() {
        guard !didFinish else {
            return
        }

        didFinish = true
        onFinish()
    }
}

private struct V13UpdateNoticeView: View {
    @Environment(\.dismiss) private var dismiss
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spacingL) {
                    Text("What’s New in KinePair")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    TutorialStepRow(
                        systemImage: "character.bubble",
                        title: String(localized: "Language Support"),
                        detail: String(localized: "KinePair follows your device or app language in English, Japanese, and Korean.")
                    )

                    TutorialStepRow(
                        systemImage: "figure.strengthtraining.traditional",
                        title: String(localized: "Try Sample"),
                        detail: String(localized: "Explore every PRO comparison tool without choosing a video or using a trial session.")
                    )

                    TutorialStepRow(
                        systemImage: "sparkles",
                        title: String(localized: "KinePair Branding"),
                        detail: String(localized: "The iOS app is now named KinePair. Your history, trial state, and purchases are unchanged.")
                    )
                }
                .padding(.horizontal, AppTheme.spacingL)
                .padding(.top, AppTheme.spacingM)
                .padding(.bottom, AppTheme.spacingL)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Button {
                    close()
                } label: {
                    Text("Close")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(AppTheme.accentText)
                .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
                .controlSize(.large)
                .padding(.horizontal, AppTheme.spacingL)
                .padding(.vertical, AppTheme.spacingS)
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        close()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
            .onDisappear(perform: onClose)
        }
    }

    private func close() {
        onClose()
        dismiss()
    }
}

private struct TutorialStepRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.spacingM) {
            Image(systemName: systemImage)
                .font(.body.weight(.bold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                Text(LocalizedStringKey(title))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.primaryText)

                Text(LocalizedStringKey(detail))
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .appCard()
    }
}

private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @State private var resetMessage: String?
    @State private var showsAdvancedSettings = false
    @State private var showsTutorial = false
    @State private var showsPrivacyPolicy = false
    @State private var comparisonDefaults = SettingsStore().comparisonDefaults
    @State private var quickExportPreset = SettingsStore().quickExportPreset
    @State private var proPaywallFeature: ProFeature?

    private let settingsStore = SettingsStore()
    private let privacyPolicyURL = URL(
        string: "https://numerous-ninja-643.notion.site/FormSync-3993ecb271ce80d3813fdb937dfcae5f?pvs=73"
    )!

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    settingsContent(size: proxy.size)
                        .padding(.horizontal, AppTheme.pageHorizontalPadding(for: proxy.size))
                        .padding(.vertical, AppTheme.pageVerticalPadding(for: proxy.size))
                        .frame(maxWidth: AppTheme.contentWidthLimit(for: proxy.size), alignment: .topLeading)
                        .frame(maxWidth: .infinity)
                }
                .background(AppTheme.background.ignoresSafeArea())
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showsTutorial) {
                TutorialView {
                    settingsStore.markOnboardingSeen()
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showsPrivacyPolicy) {
                SafariView(url: privacyPolicyURL)
                    .ignoresSafeArea()
            }
            .sheet(item: $proPaywallFeature) { feature in
                ProPaywallView(feature: feature)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    @ViewBuilder
    private func settingsContent(size: CGSize) -> some View {
        if AppTheme.isRegularWidth(size) {
            VStack(alignment: .leading, spacing: AppTheme.spacingL) {
                proSettingsSection

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: AppTheme.spacingL),
                        GridItem(.flexible(), spacing: AppTheme.spacingL)
                    ],
                    alignment: .leading,
                    spacing: AppTheme.spacingL
                ) {
                    comparisonSettingsSection
                    exportSettingsSection
                }

                advancedSettingsSection
                privacySettingsSection
            }
        } else {
            VStack(alignment: .leading, spacing: AppTheme.spacingL) {
                proSettingsSection
                comparisonSettingsSection
                exportSettingsSection
                advancedSettingsSection
                privacySettingsSection
            }
        }
    }

    private var comparisonSettingsSection: some View {
        settingsSection(title: "Comparison") {
            Picker("Playback Speed", selection: playbackRateBinding) {
                ForEach(PlaybackRate.allCases) { rate in
                    Text(rate.label).tag(rate)
                }
            }
            .pickerStyle(.menu)
            SettingsDivider()
            Picker("Default Layout", selection: displayModeBinding) {
                ForEach(DisplayMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.menu)
            SettingsDivider()
            Picker("Frame Step (Seconds)", selection: stepSecondsBinding) {
                Text("1/60 sec").tag(1.0 / 60.0)
                Text("1/30 sec").tag(1.0 / 30.0)
                Text("1/10 sec").tag(0.1)
                Text("1/2 sec").tag(0.5)
            }
            .pickerStyle(.menu)
            SettingsDivider()
            Button {
                showsTutorial = true
            } label: {
                Label("View Tutorial", systemImage: "questionmark.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
        }
    }

    private var exportSettingsSection: some View {
        settingsSection(title: "Export and Share") {
            if let quickExportPreset {
                SettingsInfoRow(
                    systemImage: "bolt.fill",
                    title: "Quick Export Preset",
                    detail: quickExportDescription(quickExportPreset)
                )
                SettingsDivider()
                Button(role: .destructive) {
                    settingsStore.resetQuickExportPreset()
                    self.quickExportPreset = nil
                    resetMessage = String(localized: "Quick Export preset was reset.")
                } label: {
                    Label("Reset Quick Export Preset", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
            } else {
                SettingsInfoRow(
                    systemImage: "bolt",
                    title: "Quick Export Preset",
                    detail: "Your latest export choices will appear here."
                )
            }
        }
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    private var advancedSettingsSection: some View {
        DisclosureGroup(isExpanded: $showsAdvancedSettings) {
            VStack(alignment: .leading, spacing: AppTheme.spacingM) {
                SettingsInfoRow(
                    systemImage: "lock.shield",
                    title: "On-Device Processing",
                    detail: "Selected videos are processed on this device and are never uploaded."
                )

                SettingsDivider()

                Button {
                    openAppSettings()
                } label: {
                    Label("Review Photos Access", systemImage: "photo")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))

                SettingsDivider()

                Button(role: .destructive) {
                    settingsStore.resetComparisonDefaults()
                    comparisonDefaults = ComparisonDefaults()
                    resetMessage = String(localized: "Comparison settings were reset.")
                } label: {
                    Label("Reset Comparison Settings", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))

                #if DEBUG
                SettingsDivider()

                Button {
                    purchaseManager.resetTrialForTesting()
                    resetMessage = String(localized: "The three full-feature trial uses were restored.")
                } label: {
                    Label("Reset Trial Uses", systemImage: "sparkles")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
                #endif

                if let resetMessage {
                    Text(resetMessage)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                SettingsDivider()

                SettingsInfoRow(
                    systemImage: "info.circle",
                    title: "Version",
                    detail: appVersionText
                )
            }
            .padding(.top, AppTheme.spacingS)
        } label: {
            Text("Advanced Settings")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
        }
        .appCard()
    }

    private var playbackRateBinding: Binding<PlaybackRate> {
        Binding(
            get: { comparisonDefaults.playbackRate },
            set: { rate in
                guard purchaseManager.isProUnlocked || !rate.requiresPro else {
                    proPaywallFeature = .slowPlayback
                    return
                }
                comparisonDefaults.playbackRate = rate
                settingsStore.saveComparisonDefaults(comparisonDefaults)
            }
        )
    }

    private var displayModeBinding: Binding<DisplayMode> {
        Binding(
            get: { comparisonDefaults.displayMode },
            set: { mode in
                guard purchaseManager.isProUnlocked || !mode.requiresPro else {
                    proPaywallFeature = .overlay
                    return
                }
                comparisonDefaults.displayMode = mode
                settingsStore.saveComparisonDefaults(comparisonDefaults)
            }
        )
    }

    private var stepSecondsBinding: Binding<Double> {
        Binding(
            get: { comparisonDefaults.stepSeconds },
            set: { seconds in
                guard purchaseManager.isProUnlocked || abs(seconds - 0.1) < 0.0001 else {
                    proPaywallFeature = .frameStep
                    return
                }
                comparisonDefaults.stepSeconds = seconds
                settingsStore.saveComparisonDefaults(comparisonDefaults)
            }
        )
    }

    private func quickExportDescription(_ preset: QuickExportPreset) -> String {
        let destination = preset.destination == .photoLibrary
            ? String(localized: "Save to Photos")
            : String(localized: "Share")
        return "\(preset.format.label) / \(preset.range.label) / \(preset.resolution.label) / \(destination)"
    }

    private var privacySettingsSection: some View {
        settingsSection(title: "Privacy") {
            Button {
                showsPrivacyPolicy = true
            } label: {
                Label("Privacy Policy", systemImage: "hand.raised")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
            .accessibilityHint("Opens in an in-app browser")
        }
    }

    private var proSettingsSection: some View {
        settingsSection(title: "PRO") {
            SettingsInfoRow(
                systemImage: purchaseManager.isProUnlocked
                    ? "checkmark.seal.fill"
                    : purchaseManager.hasRemainingTrialUses ? "sparkles" : "star.fill",
                title: proStatusTitle,
                detail: proStatusDetail
            )

            if !purchaseManager.isProUnlocked {
                SettingsDivider()

                Button {
                    Task {
                        await purchaseManager.purchasePro()
                    }
                } label: {
                    if purchaseManager.isPurchasing {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Buy PRO \(purchaseManager.displayPrice)", systemImage: "star.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(AppTheme.accentText)
                .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
                .disabled(purchaseManager.isPurchasing || purchaseManager.isLoadingProducts)
            }

            SettingsDivider()

            Button {
                Task {
                    await purchaseManager.restorePurchases()
                }
            } label: {
                Label("Restore Purchase", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
            .disabled(purchaseManager.isPurchasing)

            if let statusMessage = purchaseManager.statusMessage {
                SettingsDivider()

                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var proStatusTitle: String {
        if purchaseManager.isProUnlocked {
            return "KinePair PRO"
        }

        if purchaseManager.hasRemainingTrialUses {
            if purchaseManager.remainingTrialUses == 1 {
                return String(localized: "Full-feature trial: 1 remaining")
            }
            return L10n.format("Full-feature trial: %d remaining", purchaseManager.remainingTrialUses)
        }

        return String(localized: "Free")
    }

    private var proStatusDetail: String {
        if purchaseManager.isProUnlocked {
            return String(localized: "Overlay, slow playback, loops, video export, and multiple comparisons are available.")
        }

        if purchaseManager.hasRemainingTrialUses {
            if purchaseManager.remainingTrialUses == 1 {
                return String(localized: "Start a normal comparison to try every PRO feature one more time.")
            }
            return L10n.format(
                "Start a normal comparison to try every PRO feature %d more times.",
                purchaseManager.remainingTrialUses
            )
        }

        return String(localized: "Basic comparison is free. PRO unlocks analysis and export tools.")
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        openURL(url)
    }

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingM) {
            Text(LocalizedStringKey(title))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)

            VStack(alignment: .leading, spacing: AppTheme.spacingM) {
                content()
            }
            .appCard()
        }
    }
}

private struct SettingsInfoRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.spacingM) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                Text(LocalizedStringKey(title))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)

                Text(LocalizedStringKey(detail))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .overlay(AppTheme.border)
    }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ viewController: SFSafariViewController, context: Context) {}
}
