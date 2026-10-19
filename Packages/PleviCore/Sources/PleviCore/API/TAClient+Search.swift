
import Foundation

extension TAClient {
    public func search(query: String) async throws -> SearchResults {
        let response: SearchResponse = try await request(.search(query: query))
        return response.results
    }
}
