import Foundation

enum L10n {
    static func format(_ key: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        String(
            format: String(localized: key),
            locale: .current,
            arguments: arguments
        )
    }
}
