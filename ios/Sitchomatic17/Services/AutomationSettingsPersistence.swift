import Foundation

@MainActor
class AutomationSettingsPersistence {
    static let shared = AutomationSettingsPersistence()
    private let key = "automation_settings_v2"

    func save(_ settings: AutomationSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func load() -> AutomationSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(AutomationSettings.self, from: data) else {
            return AutomationSettings().normalizedTimeouts()
        }
        return settings.normalizedTimeouts()
    }

    func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
