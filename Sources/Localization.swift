import Foundation

enum InterfaceLanguage: String, CaseIterable {
    case system, chinese = "zh-Hans", english = "en"
}

final class Localization {
    static var shared = Localization()
    static let changed = Notification.Name("QuotaNestInterfaceLanguageChanged")
    private let defaults: UserDefaults
    private let resources: Bundle
    private let systemLanguages: () -> [String]
    init(defaults: UserDefaults = .standard, resources: Bundle = .main, systemLanguages: @escaping () -> [String] = { Locale.preferredLanguages }) {
        self.defaults = defaults; self.resources = resources; self.systemLanguages = systemLanguages
    }
    var preference: InterfaceLanguage {
        get { InterfaceLanguage(rawValue:defaults.string(forKey:"interfaceLanguage") ?? "") ?? .system }
        set {
            defaults.set(newValue.rawValue,forKey:"interfaceLanguage")
            NotificationCenter.default.post(name:Self.changed,object:self)
        }
    }
    var language: String {
        switch preference {
        case .chinese: return "zh-Hans"
        case .english: return "en"
        case .system: return systemLanguages().first?.lowercased().hasPrefix("zh") == true ? "zh-Hans" : "en"
        }
    }
    var locale: Locale { Locale(identifier:language) }
    func text(_ key: String, _ arguments: [String] = []) -> String {
        let bundle = resources.path(forResource:language,ofType:"lproj").flatMap(Bundle.init(path:))
        let format = bundle?.localizedString(forKey:key,value:key,table:nil) ?? key
        return arguments.isEmpty ? format : String(format:format,locale:locale,arguments:arguments)
    }
}

func L(_ key: String, _ arguments: String...) -> String { Localization.shared.text(key,arguments) }
