import Foundation
private var testPreferenceDomains: [String] = []
func useTestLanguage(_ language: InterfaceLanguage = .chinese) {
    if testPreferenceDomains.isEmpty {
        atexit { for domain in testPreferenceDomains { UserDefaults.standard.removePersistentDomain(forName:domain) } }
    }
    let domain = "local.quotanest.tests." + UUID().uuidString
    testPreferenceDomains.append(domain)
    let defaults = UserDefaults(suiteName:domain)!
    Localization.shared = Localization(defaults:defaults,resources:Bundle(path:".build/localizations.bundle")!)
    Localization.shared.preference = language
    precondition(Localization.shared.preference == language)
}
