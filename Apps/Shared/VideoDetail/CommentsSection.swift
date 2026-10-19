
import SwiftUI
import PleviCore

struct CommentsSection: View {
    let state: LoadState<[Comment]>
    var onRetry: () -> Void

    private static var pageSize: Int {
        #if os(tvOS)
        10
        #else
        15
        #endif
    }
    @State private var visibleCount = pageSize

    @Environment(\.colorScheme) private var colorScheme
    private var palette: PleviPalette { PleviTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            switch state {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            case .failed(let error):
                VStack(spacing: 10) {
                    Text(error.errorDescription ?? "Couldn't load comments.")
                        .pleviBody()
                        .foregroundStyle(palette.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry", action: onRetry)
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            case .loaded(let roots):
                if roots.isEmpty {
                    ContentUnavailableView(
                        "Comments Not Available",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("This video has no comments, or they weren't downloaded.")
                    )
                    .padding(.vertical, 12)
                } else {
                    // `TVOSEagerStack`, not a bare `LazyVStack`: lazy is right on a phone and a deadlock risk on tvOS.
                    TVOSEagerStack(alignment: .leading, spacing: 18) {
                        ForEach(roots.prefix(visibleCount)) { comment in
                            CommentRow(comment: comment, depth: 0)
                        }
                    }

                    if visibleCount < roots.count {
                        loadMoreButton(total: roots.count)
                    }
                }
            }
        }
        .padding(16)
        .pleviCard()
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Comments")
                .pleviSectionHeading()
                .foregroundStyle(palette.ink)
            Spacer(minLength: 8)
            if case .loaded(let roots) = state, !roots.isEmpty {
                Text("\(visibleCount) / \(roots.count)")
                    .pleviMono()
                    .foregroundStyle(palette.secondary)
            }
        }
    }

    private func loadMoreButton(total: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                visibleCount = min(visibleCount + Self.pageSize, total)
            }
        } label: {
            Text("Load More Comments")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .padding(.top, 4)
        .accessibilityHint("Shows \(min(Self.pageSize, total - visibleCount)) more of \(total - visibleCount) remaining comments.")
    }
}

private struct CommentRow: View {
    let comment: Comment
    let depth: Int

    @State private var repliesExpanded = false
    @Environment(\.colorScheme) private var colorScheme
    private var palette: PleviPalette { PleviTheme.palette(for: colorScheme) }

    private var replies: [Comment] { comment.commentReplies ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                RemoteImage(path: comment.commentAuthorThumbnail, maxPixelSize: 80)
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(comment.commentAuthor ?? "Anonymous")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                        if comment.commentAuthorIsUploader == true {
                            Text("Creator")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(palette.accent, in: Capsule())
                                .foregroundStyle(.white)
                        }
                        Spacer(minLength: 8)
                        if let timeText = comment.commentTimeText {
                            Text(timeText)
                                .pleviMono()
                                .foregroundStyle(palette.secondary)
                                .lineLimit(1)
                        }
                    }

                    if let text = comment.commentText, !text.isEmpty {
                        // `pleviBody()`, not a hardcoded 12.5pt.
                        Text(text)
                            .pleviBody()
                            .foregroundStyle(palette.body)
                    }

                    actionsLine
                }
            }

            if repliesExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(replies) { reply in
                        CommentRow(comment: reply, depth: depth + 1)
                    }
                }
                .padding(.leading, 28)
            }
        }
    }

    /// The spec's own example: `"♡ 177", "5 replies"` on one line.
    @ViewBuilder
    private var actionsLine: some View {
        if (comment.commentLikecount ?? 0) > 0 || !replies.isEmpty {
            HStack(spacing: 14) {
                if let likes = comment.commentLikecount, likes > 0 {
                    Label("\(likes)", systemImage: "heart")
                        .pleviMono()
                        .foregroundStyle(palette.secondary)
                }
                if !replies.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            repliesExpanded.toggle()
                        }
                    } label: {
                        Text(repliesExpanded ? "Hide replies" : "\(replies.count) \(replies.count == 1 ? "reply" : "replies")")
                            .pleviMono()
                            // tvOS only: this is one of just two focus stops in the whole Comments card there, and it had no treatment of its own.
                            #if os(tvOS)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .tvFocusRing(cornerRadius: 8, scales: false)
                            #endif
                    }
                    .pleviSelectableStyle()
                    .foregroundStyle(palette.accent)
                }
            }
        }
    }
}

#Preview {
    ScrollView {
        CommentsSection(
            state: .loaded([
                Comment(
                    commentId: "1",
                    commentText: "Great video!",
                    commentAuthor: "Ada",
                    commentAuthorIsUploader: false,
                    commentTimeText: "2 days ago",
                    commentLikecount: 4,
                    commentParent: "root",
                    commentReplies: [
                        Comment(commentId: "2", commentText: "Agreed!", commentAuthor: "Bo", commentTimeText: "1 day ago", commentParent: "1")
                    ]
                )
            ]),
            onRetry: {}
        )
        .padding()
    }
}
