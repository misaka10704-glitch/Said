import XCTest
@testable import Said

final class MigrationNoteSanitizerTests: XCTestCase {
    func testStripSoundTags() {
        let input = "Hello [sound:foo.mp3]<br>[sound:bar.wav]"
        let output = MigrationNoteSanitizer.stripSoundTags(in: input)
        XCTAssertFalse(output.contains("[sound:"))
        XCTAssertTrue(output.contains("Hello"))
    }

    func testSanitizeRemovesTranslationAndTagsSound() {
        let result = MigrationNoteSanitizer.sanitizeFields(
            [
                "Hello world",
                "你好世界 [sound:ref.mp3]",
            ],
            tags: [],
            fieldNames: ["English", "Chinese"]
        )

        XCTAssertFalse(result.fields[1].contains("[sound:"))
        XCTAssertTrue(result.fields[1].isEmpty)
        XCTAssertTrue(SaidNoteTags.hasNeedsTranslation(result.tags))
        XCTAssertEqual(result.fields[0], "Hello world")
        XCTAssertTrue(result.hadTranslation)
    }

    func testSanitizeRemovesWordMeaningDiv() {
        let result = MigrationNoteSanitizer.sanitizeFields(
            [
                "/æ/",
                "<div class=\"said-word-meaning\">短元音</div>\n更多说明",
            ],
            tags: [],
            fieldNames: ["Phoneme", "Back"]
        )

        XCTAssertFalse(result.fields[1].contains("said-word-meaning"))
        XCTAssertTrue(SaidNoteTags.hasNeedsTranslation(result.tags))
    }

    func testContainsSoundTag() {
        XCTAssertTrue(MigrationNoteSanitizer.containsSoundTag("[sound:test.mp3]"))
        XCTAssertFalse(MigrationNoteSanitizer.containsSoundTag("plain text"))
    }
}
