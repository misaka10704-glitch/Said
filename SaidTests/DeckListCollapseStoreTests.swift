import XCTest
@testable import Said

final class DeckListCollapseStoreTests: XCTestCase {
    private let key = DeckListCollapseStore.userDefaultsKey

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    func testSaveAndLoadCollapsedDeckIDs() {
        let store = DeckListCollapseStore.shared
        store.save([101, 202, 303])

        XCTAssertEqual(store.collapsedDeckIDs(), [101, 202, 303])
    }

    func testExpandRemovesDeckID() {
        let store = DeckListCollapseStore.shared
        store.save([10, 20])
        store.expand(deckID: 10)

        XCTAssertEqual(store.collapsedDeckIDs(), [20])
    }

    func testPruneDropsMissingDeckIDs() {
        let store = DeckListCollapseStore.shared
        store.save([1, 2, 99])
        store.prune(keeping: [1, 2, 3])

        XCTAssertEqual(store.collapsedDeckIDs(), [1, 2])
    }
}
