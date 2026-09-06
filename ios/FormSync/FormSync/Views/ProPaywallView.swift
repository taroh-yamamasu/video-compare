import SwiftUI

struct ProPaywallView: View {
    let feature: ProFeature
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    paywallContent(size: proxy.size)
                        .padding(.horizontal, AppTheme.pageHorizontalPadding(for: proxy.size))
                        .padding(.vertical, AppTheme.pageVerticalPadding(for: proxy.size))
                        .frame(maxWidth: paywallContentWidthLimit(for: proxy.size), alignment: .topLeading)
                        .frame(maxWidth: .infinity)
                }
                .background(AppTheme.background.ignoresSafeArea())
            }
            .navigationTitle("KinePair PRO")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .disabled(purchaseManager.isPurchasing)
                }
            }
            .task {
                await purchaseManager.loadProducts()
            }
            .onChange(of: purchaseManager.isProUnlocked) { _, isProUnlocked in
                if isProUnlocked {
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private func paywallContent(size: CGSize) -> some View {
        if AppTheme.isRegularWidth(size) {
            let leadingColumnWidth = AppTheme.splitLeadingColumnWidth(for: size, preferred: 320)

            HStack(alignment: .top, spacing: AppTheme.spacingL) {
                VStack(alignment: .leading, spacing: AppTheme.spacingL) {
                    header
                    actionButtons
                }
                .frame(width: leadingColumnWidth, alignment: .topLeading)

                VStack(alignment: .leading, spacing: AppTheme.spacingL) {
                    benefits
                    messageView
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: AppTheme.spacingL) {
                header
                benefits
                messageView
                actionButtons
            }
        }
    }

    private func paywallContentWidthLimit(for size: CGSize) -> CGFloat {
        AppTheme.isRegularWidth(size) ? min(size.width, 840) : AppTheme.contentMaxWidth
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingM) {
            Text("KinePair PRO")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.accentText.opacity(0.72))

            Text(feature.title)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.accentText)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Text(feature.message)
                .font(.callout.weight(.semibold))
                .foregroundStyle(AppTheme.accentText.opacity(0.76))
                .lineLimit(3)
        }
        .padding(AppTheme.spacingL)
        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous))
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingM) {
            PaywallBenefitRow(systemImage: "square.stack.3d.up.fill", title: String(localized: "Unlock overlay, slow playback, and loops"))
            PaywallBenefitRow(systemImage: "video.fill", title: String(localized: "Export comparison videos in 1080p"))
            PaywallBenefitRow(systemImage: "clock.arrow.circlepath", title: String(localized: "Keep multiple comparisons on your device"))
            PaywallBenefitRow(systemImage: "checkmark.seal.fill", title: String(localized: "Save images without a watermark"))
        }
        .appCard(padding: AppTheme.spacingL)
    }

    @ViewBuilder
    private var messageView: some View {
        if !purchaseManager.isProUnlocked, purchaseManager.hasRemainingTrialUses {
            Label(
                purchaseManager.remainingTrialUses == 1
                    ? String(localized: "Start a normal comparison to try every PRO feature one more time.")
                    : L10n.format(
                        "Start a normal comparison to try every PRO feature %d more times.",
                        purchaseManager.remainingTrialUses
                    ),
                systemImage: "sparkles"
            )
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AppTheme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard()
        } else if let message = purchaseManager.statusMessage {
            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(purchaseManager.isProUnlocked ? AppTheme.accent : AppTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard()
        }
    }

    private var actionButtons: some View {
        VStack(spacing: AppTheme.spacingS) {
            Button {
                Task {
                    await purchaseManager.purchasePro()
                }
            } label: {
                if purchaseManager.isPurchasing {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Buy PRO \(purchaseManager.displayPrice)")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(AppTheme.accentText)
            .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
            .controlSize(.large)
            .disabled(purchaseManager.isPurchasing || purchaseManager.isLoadingProducts)

            Button {
                Task {
                    await purchaseManager.restorePurchases()
                }
            } label: {
                Text("Restore Purchase")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: AppTheme.radiusS))
            .disabled(purchaseManager.isPurchasing)
        }
    }
}

struct ProBadge: View {
    var body: some View {
        Image(systemName: "star.fill")
            .font(.system(size: 6, weight: .black))
            .foregroundStyle(AppTheme.accentText)
            .frame(width: 12, height: 12)
            .background(AppTheme.accent, in: Circle())
            .accessibilityLabel("PRO")
    }
}

extension View {
    func proBadgeOverlay(_ isVisible: Bool) -> some View {
        overlay(alignment: .topTrailing) {
            if isVisible {
                ProBadge()
                    .offset(x: 3, y: -3)
            }
        }
    }
}

private struct PaywallBenefitRow: View {
    let systemImage: String
    let title: String

    var body: some View {
        HStack(spacing: AppTheme.spacingM) {
            Image(systemName: systemImage)
                .font(.body.weight(.bold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 24)

            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
