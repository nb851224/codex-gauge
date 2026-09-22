import Foundation

enum L10n {
    private static let bundle: Bundle = {
        if let resourceURL = Bundle.main.resourceURL,
           let packagedBundle = Bundle(
               url: resourceURL.appendingPathComponent("CodexGauge_CodexGauge.bundle")
           ) {
            return packagedBundle
        }
        return Bundle.module
    }()

    static var locale: Locale {
        let identifier = bundle.preferredLocalizations.first ?? "en"
        return Locale(identifier: identifier)
    }

    static func text(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }
}
