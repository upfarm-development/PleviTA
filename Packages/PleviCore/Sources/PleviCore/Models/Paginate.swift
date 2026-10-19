
import Foundation

/// Pagination metadata attached to every list response.
public struct Paginate: Codable, Sendable, Equatable {
    public var pageSize: Int?
    public var pageFrom: Int?
    public var prevPages: [Int]?
    public var currentPage: Int?
    public var maxHits: Int?
    public var lastPage: Int?
    public var nextPages: [Int]?
    public var totalHits: Int?

    enum CodingKeys: String, CodingKey {
        case pageSize = "page_size"
        case pageFrom = "page_from"
        case prevPages = "prev_pages"
        case currentPage = "current_page"
        case maxHits = "max_hits"
        case lastPage = "last_page"
        case nextPages = "next_pages"
        case totalHits = "total_hits"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pageSize = container.decodeFlexibleIntIfPresent(forKey: .pageSize)
        pageFrom = container.decodeFlexibleIntIfPresent(forKey: .pageFrom)
        prevPages = try? container.decodeIfPresent([Int].self, forKey: .prevPages)
        currentPage = container.decodeFlexibleIntIfPresent(forKey: .currentPage)
        maxHits = container.decodeFlexibleIntIfPresent(forKey: .maxHits)
        lastPage = container.decodeFlexibleIntIfPresent(forKey: .lastPage)
        nextPages = try? container.decodeIfPresent([Int].self, forKey: .nextPages)
        totalHits = container.decodeFlexibleIntIfPresent(forKey: .totalHits)
    }

    public init(
        pageSize: Int? = nil,
        pageFrom: Int? = nil,
        prevPages: [Int]? = nil,
        currentPage: Int? = nil,
        maxHits: Int? = nil,
        lastPage: Int? = nil,
        nextPages: [Int]? = nil,
        totalHits: Int? = nil
    ) {
        self.pageSize = pageSize
        self.pageFrom = pageFrom
        self.prevPages = prevPages
        self.currentPage = currentPage
        self.maxHits = maxHits
        self.lastPage = lastPage
        self.nextPages = nextPages
        self.totalHits = totalHits
    }

    /// True when the current page is not the last one, i.e. more pages can be fetched.
    public var hasNextPage: Bool {
        if let currentPage, let lastPage {
            return currentPage < lastPage
        }
        return !(nextPages?.isEmpty ?? true)
    }
}

/// Generic wrapper for every paginated Tube Archivist list response.
public struct Paginated<Element: Codable & Sendable>: Codable, Sendable {
    public var data: [Element]
    public var paginate: Paginate?

    enum CodingKeys: String, CodingKey {
        case data
        case paginate
    }

    public init(data: [Element], paginate: Paginate? = nil) {
        self.data = data
        self.paginate = paginate
    }
}
