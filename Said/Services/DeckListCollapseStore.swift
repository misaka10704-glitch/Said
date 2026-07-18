import Foundation

final class DeckListCollapseStore {
    static let shared = DeckListCollapseStore()
    static let userDefaultsKey = "said_deck_list_collapsed_v1"

    private init() {}

    func collapsedDeckIDs() -> Set<Int64> {
        guard let raw = UserDefaults.standard.array(forKey: Self.userDefaultsKey) as? [String] else {
            return []
        }
        return Set(raw.compactMap { Int64($0) })
    }

    func save(_ ids: Set<Int64>) {
        let values = ids.map(String.init).sorted()
        UserDefaults.standard.set(values, forKey: Self.userDefaultsKey)
    }

    func expand(deckID: Int64) {
        var ids = collapsedDeckIDs()
        guard ids.remove(deckID) != nil else { return }
        save(ids)
    }

    func prune(keeping validIDs: Set<Int64>) {
        let pruned = collapsedDeckIDs().intersection(validIDs)
        if pruned.count != collapsedDeckIDs().count {
            save(pruned)
        }
    }
}
