import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.77, green: 1.0, blue: 0.22)
    static let accentDim = Color(red: 0.50, green: 0.68, blue: 0.12)
    static let accentText = Color(red: 0.05, green: 0.06, blue: 0.05)
    static let backgroundPrimary = Color(red: 0.025, green: 0.026, blue: 0.032)
    static let backgroundSecondary = Color(red: 0.105, green: 0.105, blue: 0.13)
    static let surfaceElevated = Color(red: 0.155, green: 0.15, blue: 0.18)
    static let surfaceInteractive = Color.white.opacity(0.075)
    static let accentSurface = accent.opacity(0.14)
    static let segmentBackground = Color.white.opacity(0.09)
    static let selectedSegment = accent
    static let divider = Color.white.opacity(0.12)
    static let accentBorder = accent.opacity(0.35)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.68)
    static let tertiaryText = Color.white.opacity(0.48)
    static let selectedText = accentText
    static let unselectedText = Color.white.opacity(0.72)
    static let disabled = Color.white.opacity(0.34)
    static let destructive = Color(uiColor: .systemRed)

    // Compatibility aliases keep the existing comparison workspace unchanged.
    static let background = backgroundPrimary
    static let surface = backgroundSecondary
    static let elevatedSurface = surfaceElevated
    static let subtleSurface = surfaceInteractive
    static let border = divider
    static let primaryText = textPrimary
    static let secondaryText = textSecondary
    static let error = destructive

    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 12
    static let spacingL: CGFloat = 16
    static let spacingXL: CGFloat = 24
    static let spacingXXL: CGFloat = 32

    static let radiusS: CGFloat = 6
    static let radiusM: CGFloat = 8
    static let minimumTouchTarget: CGFloat = 44

    static let regularWidthBreakpoint: CGFloat = 700
    static let wideLandscapeBreakpoint: CGFloat = 980
    static let compactPhoneWidthBreakpoint: CGFloat = 380
    static let compactPhoneHeightBreakpoint: CGFloat = 700

    static let contentMaxWidth: CGFloat = 560
    static let formContentMaxWidth: CGFloat = 720
    static let regularContentMaxWidth: CGFloat = 860
    static let wideContentMaxWidth: CGFloat = 1080

    static func isRegularWidth(_ size: CGSize) -> Bool {
        size.width >= regularWidthBreakpoint
    }

    static func isCompactPhone(_ size: CGSize) -> Bool {
        size.width < compactPhoneWidthBreakpoint || size.height < compactPhoneHeightBreakpoint
    }

    static func pageHorizontalPadding(for size: CGSize) -> CGFloat {
        if size.width < 360 {
            return spacingM
        }

        return isRegularWidth(size) ? spacingXL : spacingL
    }

    static func pageVerticalPadding(for size: CGSize) -> CGFloat {
        isCompactPhone(size) ? spacingM : spacingL
    }

    static func contentWidthLimit(for size: CGSize) -> CGFloat {
        if size.width >= wideLandscapeBreakpoint {
            return wideContentMaxWidth
        }

        if isRegularWidth(size) {
            return regularContentMaxWidth
        }

        return contentMaxWidth
    }

    static func formWidthLimit(for size: CGSize) -> CGFloat {
        isRegularWidth(size) ? formContentMaxWidth : contentMaxWidth
    }

    static func clamped(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minimum), maximum)
    }

    static func splitLeadingColumnWidth(for size: CGSize, preferred: CGFloat) -> CGFloat {
        let availableWidth = Swift.max(size.width - pageHorizontalPadding(for: size) * 2, 1)
        return clamped(availableWidth * 0.34, min: Swift.min(preferred, 240), max: preferred)
    }
}

private struct AppCardModifier: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous)
                    .stroke(AppTheme.border)
            )
            .shadow(color: .black.opacity(0.24), radius: 16, x: 0, y: 10)
    }
}

extension View {
    func appCard(padding: CGFloat = AppTheme.spacingM) -> some View {
        modifier(AppCardModifier(padding: padding))
    }
}
