import Foundation

/// Backend boundary. Today backed by Swift SM-2 + SQLite (`AnkiCollection`).
/// Swap the implementation for ankitects/anki `rslib` C FFI without changing UI.
protocol AnkiBackend: AnyObject {
    func importApkg(from url: URL) throws
    func exportApkg(to url: URL) throws
    func listDecks() throws -> [AnkiDeckInfo]
    func nextCard(deckId: Int64?) throws -> AnkiCardSnapshot?
    func answer(cardId: Int64, ease: AnkiEase, timeMs: Int) throws
}

final class LocalAnkiBackend: AnkiBackend {
    private let store = AnkiStore.shared

    func importApkg(from url: URL) throws {
        _ = try store.importApkg(url)
    }

    func exportApkg(to url: URL) throws {
        try store.exportApkg(to: url)
    }

    func listDecks() throws -> [AnkiDeckInfo] {
        try store.requireCollection().listDecks()
    }

    func nextCard(deckId: Int64?) throws -> AnkiCardSnapshot? {
        try store.requireCollection().nextCard(deckId: deckId)
    }

    func answer(cardId: Int64, ease: AnkiEase, timeMs: Int) throws {
        try store.requireCollection().answer(cardId: cardId, ease: ease, timeMs: timeMs)
    }
}
