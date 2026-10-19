
import Foundation
import Testing
@testable import PleviCore

@Suite("CommentTree")
struct CommentTreeTests {

    @Test("builds a reply tree from a flat comment list")
    func buildsTreeFromFlatList() throws {
        let flat = try Fixture.decode([PleviCore.Comment].self, from: "comment_list.json")
        let tree = CommentTree.build(from: flat)

        #expect(tree.count == 2) // c1 (with a nested reply) and c3
        let c1 = try #require(tree.first(where: { $0.commentId == "c1" }))
        #expect(c1.commentReplies?.count == 1)
        #expect(c1.commentReplies?.first?.commentId == "c2")

        let c3 = try #require(tree.first(where: { $0.commentId == "c3" }))
        #expect(c3.commentReplies == nil)
    }

    @Test("passes through an already-nested shape unchanged")
    func passesThroughNestedShape() {
        let nested = [
            PleviCore.Comment(commentId: "root1", commentParent: "root", commentReplies: [
                PleviCore.Comment(commentId: "reply1", commentParent: "root1")
            ])
        ]
        let tree = CommentTree.build(from: nested)
        #expect(tree.count == 1)
        #expect(tree.first?.commentReplies?.count == 1)
    }
}
