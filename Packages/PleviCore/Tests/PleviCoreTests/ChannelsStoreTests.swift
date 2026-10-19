
import Foundation
import Testing
@testable import PleviCore

/// A mutable reference cell so `MockURLProtocol`'s `@Sendable` handler closures can count requests.
private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

extension MockedNetworkTests {

@MainActor
@Suite("ChannelsStore", .serialized)
struct ChannelsStoreTests {
    private nonisolated func makeServerURL() -> URL {
        URL(string: "https://mock-\(UUID().uuidString.prefix(8)).test")!
    }

    private nonisolated func makeClient(serverURL: URL) -> TAClient {
        let credentialStore = InMemoryCredentialStore()
        credentialStore.setToken("sometoken")
        return TAClient(serverURL: serverURL, credentialStore: credentialStore, urlSession: MockURLProtocol.makeSession())
    }

    private nonisolated func makeChannel(id: String, subscribed: Bool = false) -> Channel {
        Channel(channelId: id, channelName: "Channel \(id)", channelSubscribed: subscribed)
    }

    private nonisolated func pageBody(_ channels: [Channel], currentPage: Int, lastPage: Int) -> Data {
        let paginate = Paginate(
            pageSize: channels.count,
            pageFrom: 0,
            prevPages: currentPage > 1 ? Array(1..<currentPage) : [],
            currentPage: currentPage,
            maxHits: nil,
            lastPage: lastPage,
            nextPages: currentPage < lastPage ? Array((currentPage + 1)...lastPage) : [],
            totalHits: channels.count
        )
        let page = Paginated(data: channels, paginate: paginate)
        return try! JSONEncoder().encode(page)
    }

    @Test("loadFirstPage adds filter=subscribed only when the setting is on, and dedupes repeat calls")
    func loadFirstPageHonorsSubscribedOnlyAndDedupes() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "channels.\(UUID().uuidString)")!)
        let store = ChannelsStore(client: client, appSettings: settings)

        let requestCount = Box(0)
        MockURLProtocol.handler = { request in
            requestCount.value += 1
            #expect(request.url?.query?.contains("filter=subscribed") != true)
            let body = self.pageBody([self.makeChannel(id: "c1")], currentPage: 1, lastPage: 1)
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }

        await store.loadFirstPage()
        #expect(store.items.map(\.id) == ["c1"])
        #expect(requestCount.value == 1)

        // Same settings: no new network call.
        await store.loadFirstPage()
        #expect(requestCount.value == 1)

        // Flip the setting: a new request is made, this time with the filter.
        settings.channelsSubscribedOnly = true
        MockURLProtocol.handler = { request in
            requestCount.value += 1
            #expect(request.url?.query?.contains("filter=subscribed") == true)
            let body = self.pageBody([self.makeChannel(id: "c2", subscribed: true)], currentPage: 1, lastPage: 1)
            return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }
        await store.loadFirstPage()
        #expect(requestCount.value == 2)
        #expect(store.items.map(\.id) == ["c2"])
    }

    @Test("loadNextPageIfNeeded fetches and appends the next page near the end")
    func infiniteScrollAppendsNextPage() async throws {
        let serverURL = makeServerURL()
        let client = makeClient(serverURL: serverURL)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "channels.\(UUID().uuidString)")!)
        let store = ChannelsStore(client: client, appSettings: settings)

        let firstPage = [makeChannel(id: "c1"), makeChannel(id: "c2")]
        MockURLProtocol.handler = { request in
            let page = (request.url?.query ?? "").contains("page=2") ? 2 : 1
            if page == 1 {
                let body = self.pageBody(firstPage, currentPage: 1, lastPage: 2)
                return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
            } else {
                let body = self.pageBody([self.makeChannel(id: "c3")], currentPage: 2, lastPage: 2)
                return .init(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
            }
        }

        await store.loadFirstPage(force: true)
        #expect(store.items.count == 2)

        await store.loadNextPageIfNeeded(currentItem: store.items[1])
        #expect(store.items.count == 3)
        #expect(store.items.last?.id == "c3")
    }
}

}
