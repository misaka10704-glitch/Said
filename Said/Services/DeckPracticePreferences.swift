import Foundation

struct DeckPracticePreferences: Codable {
    var curtainEnabled: Bool = true
    var centerSentence: Bool = true
    var sentenceFontSize: Double = 21
    var noteTypeID: Int64?
}

final class DeckPracticePreferencesStore {
    static let shared = DeckPracticePreferencesStore()
    private let key = "said_deck_practice_preferences_v1"

    func preferences(for deckID: Int64) -> DeckPracticePreferences {
        guard let data = UserDefaults.standard.data(forKey: key),
              let values = try? JSONDecoder().decode([String: DeckPracticePreferences].self, from: data) else {
            return DeckPracticePreferences()
        }
        return values[String(deckID)] ?? DeckPracticePreferences()
    }

    func save(_ preferences: DeckPracticePreferences, for deckID: Int64) {
        var values: [String: DeckPracticePreferences] = [:]
        if let data = UserDefaults.standard.data(forKey: key) {
            values = (try? JSONDecoder().decode([String: DeckPracticePreferences].self, from: data)) ?? [:]
        }
        values[String(deckID)] = preferences
        UserDefaults.standard.set(try? JSONEncoder().encode(values), forKey: key)
    }
}
