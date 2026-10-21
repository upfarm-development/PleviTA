// tvOS's own left sidebar, replacing the platform's top `TabView` (AppShellView.swift): a small icon rail on the left edge, on screen on every page.
#if os(tvOS)
import SwiftUI
import UIKit
import PleviCore

/// What a sidebar row focuses/selects.
enum TVSidebarTarget: Hashable {
    case section(AppSection)
}

struct TVSidebar: View {
    @Binding var selection: AppSection
    var focus: FocusState<TVSidebarTarget?>.Binding
    /// Choosing the section you are already in — from a video pushed off Home, say — goes back
    /// to that section's own screen, the way a tab bar does. Selecting it alone changes nothing.
    var onReselect: (AppSection) -> Void

    /// Search above Home, not `AppSection.allCases`' own declaration order, which exists for
    /// `TabView`/`ForEach` identity elsewhere and was never meant to double as a sidebar's visual
    /// order. Settings sits apart, below.
    private static let rowOrder: [AppSection] = [.search, .home, .channels, .playlists]

    /// Briefly true after a row is chosen — see `handOff()`.
    @State private var isHandingOff = false
    /// The section that was showing when focus came onto the rail. The page follows focus, so by the
    /// time Select is pressed `selection` is always the focused row; this is what tells "I came here
    /// from this section" (go back to its root) from "I moved here" (just go into it).
    @State private var sectionOnEntry: AppSection?
    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Self.rowOrder) { section in
                sectionRow(section)
            }
            // Settings sits a little apart from the other four icons.
            Color.clear.frame(height: 20)
            sectionRow(.settings)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
        .frame(width: PleviMetrics.tvSidebarRailWidth, alignment: .leading)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .clipShape(Capsule())
        // The full height of the screen, with the rail still centred in it, so that the focus section below covers the whole left edge.
        .frame(maxHeight: .infinity)
        .disabled(isHandingOff)
        .focusSection()
        // `.userInitiated`, so it applies every time focus moves in — pressing Left from the page included.
        .defaultFocus(focus, .section(selection), priority: .userInitiated)
        // The page follows focus: moving onto a row shows that section without pressing Select.
        .onChange(of: focus.wrappedValue) { old, new in
            guard case .section(let section)? = new else { return }
            if old == nil { sectionOnEntry = selection }
            if selection != section { selection = section }
        }
    }

    /// Sends focus to the page after a row is chosen.
    private func handOff() {
        isHandingOff = true
        focus.wrappedValue = nil
        navigation.pageEntryRequest += 1
        Task { @MainActor in
            await Self.waitUntilFocusLeavesSidebar(timeout: .seconds(4))
            isHandingOff = false
        }
    }

    /// Polls rather than awaiting the notification directly: a cancelled task cannot safely resume a
    /// `NotificationCenter` callback's continuation, and polling a plain flag sidesteps that at the
    /// cost of up to this interval's worth of latency.
    @MainActor
    private static func waitUntilFocusLeavesSidebar(timeout: Duration) async {
        var crossed = false
        let observer = NotificationCenter.default.addObserver(
            forName: UIFocusSystem.didUpdateNotification, object: nil, queue: .main
        ) { notification in
            guard let context = notification.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey] as? UIFocusUpdateContext,
                  let next = context.nextFocusedItem,
                  let midX = TVSidebarFocusMemory.midX(of: next), midX >= TVSidebarFocusMemory.sidebarEdge
            else { return }
            crossed = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let deadline = ContinuousClock.now + timeout
        while !crossed, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func sectionRow(_ section: AppSection) -> some View {
        Button {
            if sectionOnEntry == section {
                onReselect(section)
            }
            selection = section
            handOff()
        } label: {
            TVSidebarRowLabel(systemImage: section.systemImage, isSelected: selection == section)
        }
        .pleviSelectableStyle()
        .focused(focus, equals: .section(section))
        .accessibilityLabel(section.title)
    }
}

/// A rail icon: white disc with a dark glyph while focused, a faint disc for the current section, nothing otherwise.
private struct TVSidebarRowLabel: View {
    let systemImage: String
    let isSelected: Bool

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(isFocused ? Color(hex: "111114") : .white)
            .frame(width: 56, height: 56)
            .background(Circle().fill(fill))
            .contentShape(Circle())
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }

    private var fill: Color {
        if isFocused {
            .white
        } else if isSelected {
            Color.white.opacity(0.18)
        } else {
            .clear
        }
    }
}

// MARK: - Menu pressed while nothing has focus

/// Catches a Menu press that would otherwise leave the app.
struct TVMenuWhenNothingFocused: UIViewRepresentable {
    var action: () -> Void

    func makeUIView(context: Context) -> TVMenuCatcherView {
        let view = TVMenuCatcherView()
        view.action = action
        return view
    }

    func updateUIView(_ view: TVMenuCatcherView, context: Context) {
        view.action = action
    }
}

final class TVMenuCatcherView: UIView, UIGestureRecognizerDelegate {
    var action: () -> Void = {}
    private let recognizer = UITapGestureRecognizer()
    private weak var attachedWindow: UIWindow?

    override init(frame: CGRect) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        recognizer.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        recognizer.addTarget(self, action: #selector(fired))
        recognizer.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attachedWindow?.removeGestureRecognizer(recognizer)
        attachedWindow = window
        window?.addGestureRecognizer(recognizer)
    }

    @objc private func fired() {
        PlaybackLog.shared.log("app", "Menu pressed with nothing handling it; going back instead of leaving the app")
        action()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive press: UIPress) -> Bool {
        guard let window = attachedWindow else { return false }
        let presented = window.rootViewController?.presentedViewController
        let dismissing = presented?.isBeingDismissed == true
        let focused = UIFocusSystem.focusSystem(for: window)?.focusedItem
        let focusedView = focused as? UIView
        // Focus that has not let go of a menu that is already closing: a view that is no longer in
        // any window, or is in a different one from the page.
        let focusIsStale = focusedView.map { $0.window == nil || $0.window !== window } ?? false
        let take = dismissing || ((focused == nil || focusIsStale) && presented == nil)
        PlaybackLog.shared.log("app", "Menu press: focused=\(focused.map { String(describing: type(of: $0)) } ?? "none") "
            + "stale=\(focusIsStale) presented=\(presented != nil) dismissing=\(dismissing) "
            + "windowIsKey=\(window.isKeyWindow) windows=\(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).count) taken=\(take)",
            force: true)
        return take
    }
}

// MARK: - Returning focus to where it came from

/// Remembers the item focus left the page from whenever it crosses into the sidebar, so that `TVSidebarFocusReturn` can send it back there.
@MainActor
final class TVSidebarFocusMemory: NSObject {
    /// Anything whose centre is further left than this is the sidebar's. `fileprivate`, not
    /// `private`: `TVSidebar.waitUntilFocusLeavesSidebar(timeout:)` reuses this same boundary
    /// for the opposite crossing, rather than a second copy of the same number.
    fileprivate static let sidebarEdge: CGFloat = 150

    private(set) weak var returnItem: UIFocusItem?
    /// The guide on screen right now, if any — told when `returnItem` changes under it.
    weak var guideView: TVSidebarFocusReturnView?

    override init() {
        super.init()
        // Selector-based, so it is removed automatically when this object goes. The focus system
        // posts on the main thread.
        NotificationCenter.default.addObserver(
            self, selector: #selector(focusDidUpdate(_:)),
            name: UIFocusSystem.didUpdateNotification, object: nil
        )
    }

    @objc private func focusDidUpdate(_ notification: Notification) {
        guard let context = notification.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey] as? UIFocusUpdateContext,
              let previous = context.previouslyFocusedItem,
              let next = context.nextFocusedItem,
              let previousX = Self.midX(of: previous), let nextX = Self.midX(of: next)
        else { return }
        if previousX >= Self.sidebarEdge, nextX < Self.sidebarEdge {
            returnItem = previous
            guideView?.refresh()
        }
    }

    fileprivate static func midX(of item: UIFocusItem) -> CGFloat? {
        guard let space = item.parentFocusEnvironment?.focusItemContainer?.coordinateSpace else { return nil }
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        guard let window else { return nil }
        return space.convert(item.frame, to: window).midX
    }
}

/// While focus is on the rail, a `UIFocusGuide` just right of it pointing at the item focus entered the sidebar from.
struct TVSidebarFocusReturn: UIViewRepresentable {
    let memory: TVSidebarFocusMemory

    func makeUIView(context: Context) -> TVSidebarFocusReturnView {
        let view = TVSidebarFocusReturnView(memory: memory)
        memory.guideView = view
        return view
    }

    func updateUIView(_ view: TVSidebarFocusReturnView, context: Context) {
        view.refresh()
    }
}

final class TVSidebarFocusReturnView: UIView {
    private let guide = UIFocusGuide()
    private let memory: TVSidebarFocusMemory

    init(memory: TVSidebarFocusMemory) {
        self.memory = memory
        super.init(frame: .zero)
        backgroundColor = .clear
        addLayoutGuide(guide)
        NSLayoutConstraint.activate([
            guide.leadingAnchor.constraint(equalTo: leadingAnchor),
            guide.trailingAnchor.constraint(equalTo: trailingAnchor),
            guide.topAnchor.constraint(equalTo: topAnchor),
            guide.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func refresh() {
        // Only an item that can still take focus: one in a section that has since been hidden,
        // or on a page since popped, would make the guide a dead end and Right would do nothing.
        if let item = memory.returnItem, item.canBecomeFocused {
            guide.preferredFocusEnvironments = [item]
        } else {
            guide.preferredFocusEnvironments = []
        }
    }
}
#endif
