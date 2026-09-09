import SwiftUI
import UIKit

@main
struct FormSyncApp: App {
    @StateObject private var purchaseManager = PurchaseManager()

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-resetOnboardingForUITests") {
            UserDefaults.standard.removeObject(forKey: "hasSeenOnboarding")
            UserDefaults.standard.removeObject(forKey: "hasSeenV13UpdateNotice")
        }
        if ProcessInfo.processInfo.arguments.contains("-resetComparisonDefaultsForUITests") {
            SettingsStore().resetComparisonDefaults()
        }
        if ProcessInfo.processInfo.arguments.contains("-resetQuickExportPresetForUITests") {
            SettingsStore().resetQuickExportPreset()
        }
        if ProcessInfo.processInfo.arguments.contains("-showV13UpdateNoticeForUITests") {
            UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
            UserDefaults.standard.removeObject(forKey: "hasSeenV13UpdateNotice")
        }
        #endif

        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(AppTheme.accent)
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.foregroundColor: UIColor(AppTheme.accentText)],
            for: .selected
        )
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.foregroundColor: UIColor(AppTheme.unselectedText)],
            for: .normal
        )
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(purchaseManager)
                .preferredColorScheme(.dark)
                .tint(AppTheme.accent)
        }
    }
}
