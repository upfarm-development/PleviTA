import Testing
@testable import PleviCore

@Suite("AuthStore.cleanedToken")
struct TokenCleaningTests {
    @Test("a plain token is left alone")
    func plain() {
        #expect(AuthStore.cleanedToken("0123456789abcdef") == "0123456789abcdef")
    }

    @Test("whitespace, quotes and line breaks around or inside it are removed")
    func whitespaceAndQuotes() {
        #expect(AuthStore.cleanedToken("  \"0123 4567\n89ab\"  ") == "012345678 9ab".replacingOccurrences(of: " ", with: ""))
    }

    @Test("a copied Authorization header's prefix is dropped")
    func prefixes() {
        #expect(AuthStore.cleanedToken("Token abc123") == "abc123")
        #expect(AuthStore.cleanedToken("Bearer abc123") == "abc123")
        #expect(AuthStore.cleanedToken("Authorization: Token abc123") == "abc123")
    }

    @Test("empty input stays empty")
    func empty() {
        #expect(AuthStore.cleanedToken("  \n ") == "")
    }
}
