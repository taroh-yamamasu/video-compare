import UIKit
import XCTest

final class FormSyncScreenshotUITests: XCTestCase {
    private var app: XCUIApplication!
    private var screenshotDirectory: URL!
    private var devicePrefix: String!

    override func setUpWithError() throws {
        continueAfterFailure = false

        let environment = ProcessInfo.processInfo.environment
        let projectDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let directoryPath = environment["FORMSYNC_SCREENSHOT_DIR"]
            ?? projectDirectory.appendingPathComponent("AppStore/Screenshots").path
        screenshotDirectory = URL(fileURLWithPath: directoryPath, isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)

        let fallbackDeviceName = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        let rawDeviceName = environment["SIMULATOR_DEVICE_NAME"] ?? fallbackDeviceName
        devicePrefix = sanitizeFileName(rawDeviceName)

        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait

        app = XCUIApplication()
    }

    func testCaptureJapaneseAppStoreScreenshots() throws {
        launch(language: "ja", locale: "ja_JP")
        try captureProductScreens(
            languagePrefix: "ja",
            settingsTitle: "設定",
            advancedSettingsTitle: "詳細設定",
            overlayTitle: "重ね",
            closeTitle: "閉じる"
        )
    }

    func testCaptureEnglishAppStoreScreenshots() throws {
        launch(language: "en", locale: "en_US")
        try captureProductScreens(
            languagePrefix: "en",
            settingsTitle: "Settings",
            advancedSettingsTitle: "Advanced Settings",
            overlayTitle: "Overlay",
            closeTitle: "Close"
        )
    }

    func testCaptureKoreanAppStoreScreenshots() throws {
        launch(language: "ko", locale: "ko_KR")
        try captureProductScreens(
            languagePrefix: "ko",
            settingsTitle: "설정",
            advancedSettingsTitle: "고급 설정",
            overlayTitle: "겹치기",
            closeTitle: "닫기"
        )
    }

    func testV13UpdateNoticeCanBeClosed() {
        app.launchArguments += [
            "-AppleLanguages", "(ja)",
            "-AppleLocale", "ja_JP",
            "-showV13UpdateNoticeForUITests"
        ]
        app.launch()

        let japaneseCloseButtons = app.buttons.matching(identifier: "閉じる")
        let englishCloseButtons = app.buttons.matching(identifier: "Close")
        XCTAssertTrue(
            japaneseCloseButtons.firstMatch.waitForExistence(timeout: 5)
                || englishCloseButtons.firstMatch.waitForExistence(timeout: 1)
        )

        if !tapFirstHittable(japaneseCloseButtons) {
            XCTAssertTrue(tapFirstHittable(englishCloseButtons))
        }

        XCTAssertTrue(app.buttons["home.trySample"].waitForExistence(timeout: 5))
    }

    private func captureProductScreens(
        languagePrefix: String,
        settingsTitle: String,
        advancedSettingsTitle: String,
        overlayTitle: String,
        closeTitle: String
    ) throws {
        waitForQuietUI()
        capture("\(languagePrefix)-01-home")

        tapElement(named: "home.trySample")
        XCTAssertTrue(app.buttons["compare.setReference.left"].waitForExistence(timeout: 8))
        waitForQuietUI()
        capture("\(languagePrefix)-02-sync-setup")

        tapElement(named: "compare.setReference.left")
        tapElement(named: "compare.setReference.right")
        tapElement(named: "compare.start")
        tapElement(named: "compare.fullscreen.enter")
        XCTAssertTrue(app.buttons["compare.fullscreen.exit"].waitForExistence(timeout: 5))
        tapElement(named: "compare.fullscreen.exit")
        waitForQuietUI()
        capture("\(languagePrefix)-03-side-by-side")

        if !app.buttons["compare.layout.overlayPreview"].isHittable {
            tapElement(
                named: "compare.details",
                fallback: advancedSettingsTitle
            )
        }
        tapElement(
            named: "compare.layout.overlayPreview",
            fallback: overlayTitle
        )
        waitForQuietUI()
        capture("\(languagePrefix)-04-overlay")

        tapElement(named: "compare.export")
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 8))
        waitForQuietUI()
        capture("\(languagePrefix)-05-export")

        tapElement(named: closeTitle)
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
        tapElement(named: "home.settings")
        XCTAssertTrue(app.navigationBars[settingsTitle].waitForExistence(timeout: 8))
        waitForQuietUI()
        capture("\(languagePrefix)-06-privacy-settings")
    }

    private func launch(language: String, locale: String) {
        app.launchArguments += [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
            "-resetComparisonDefaultsForUITests"
        ]
        app.launch()
        dismissOnboardingIfNeeded()
    }

    private func dismissOnboardingIfNeeded() {
        for title in ["Skip", "スキップ", "건너뛰기", "Close", "閉じる", "닫기"] {
            if app.buttons[title].waitForExistence(timeout: 1) {
                app.buttons[title].tap()
                waitForQuietUI(seconds: 0.4)
            }
        }
    }

    private func tapElement(named name: String, fallback: String? = nil) {
        if tapFirstHittable(app.buttons.matching(identifier: name)) {
            return
        }

        if let fallback, tapFirstHittable(app.buttons.matching(identifier: fallback)) {
            return
        }

        if let fallback, tapFirstHittable(app.staticTexts.matching(identifier: fallback)) {
            return
        }

        let targetName = fallback ?? name
        for _ in 0..<5 {
            app.swipeUp()
            waitForQuietUI(seconds: 0.25)

            if tapFirstHittable(app.buttons.matching(identifier: name)) {
                return
            }

            if tapFirstHittable(app.buttons.matching(identifier: targetName)) {
                return
            }

            if tapFirstHittable(app.staticTexts.matching(identifier: targetName)) {
                return
            }
        }

        XCTFail("Element not found: \(name)")
    }

    private func tapFirstHittable(_ query: XCUIElementQuery) -> Bool {
        if query.firstMatch.waitForExistence(timeout: 1), query.firstMatch.isHittable {
            query.firstMatch.tap()
            return true
        }

        for index in 0..<query.count {
            let element = query.element(boundBy: index)
            if element.exists, element.isHittable {
                element.tap()
                return true
            }
        }

        return false
    }

    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let fileURL = screenshotDirectory.appendingPathComponent("\(devicePrefix!)-\(name).png")
        do {
            try screenshot.pngRepresentation.write(to: fileURL, options: [.atomic])
        } catch {
            XCTFail("Failed to write screenshot \(name): \(error)")
        }
    }

    private func waitForQuietUI(seconds: TimeInterval = 1) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func sanitizeFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { $0.append($1) }
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
