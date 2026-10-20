import Testing
@testable import AgryCore

@Suite struct DisplayTextTests {
    @Test func plainTextIsUnchanged() {
        #expect(DisplayText.sanitize("Deploying v2.4.1 → prod") == "Deploying v2.4.1 → prod")
    }

    @Test func removesDirectionOverrides() {
        #expect(DisplayText.sanitize("hi\u{202E}evil") == "hievil")
    }

    @Test func removesDirectionIsolatesAndMarks() {
        #expect(DisplayText.sanitize("\u{2066}a\u{2069}\u{200F}b\u{061C}") == "ab")
    }

    @Test func removesZeroWidthCharacters() {
        #expect(DisplayText.sanitize("a\u{200B}b\u{2060}c\u{FEFF}") == "abc")
    }

    @Test func removesControlCharacters() {
        #expect(DisplayText.sanitize("a\u{7}b\u{9B}c") == "abc")
    }

    @Test func keepsEmojiSequences() {
        // Zero-width joiners hold multi-person emoji together.
        #expect(DisplayText.sanitize("done 👩‍💻") == "done 👩‍💻")
    }
}
