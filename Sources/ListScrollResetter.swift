import SwiftUI
import AppKit

/// Resets the sidebar List's underlying NSScrollView to the top when the search
/// changes.
///
/// On macOS a `List` is backed by an AppKit `NSScrollView` that SwiftUI reuses.
/// When the result set shrinks (e.g. clicking a Chinese keyword) while a tool
/// far down the old list is still selected, SwiftUI asynchronously re-aligns the
/// List to that selection and clips the first row. `ScrollViewReader.scrollTo`
/// and changing the List `.id` do not override that AppKit offset, so we address
/// the scroll view directly, after layout has settled.
struct ListScrollResetter: NSViewRepresentable {
    let trigger: String

    final class Coordinator {
        var lastTrigger: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard context.coordinator.lastTrigger != trigger else { return }
        context.coordinator.lastTrigger = trigger
        // Two passes: SwiftUI may re-apply its selection alignment after the
        // first layout pass.
        for delay in [0.05, 0.30, 0.60] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                Self.resetSidebarScroll(startingAt: view)
            }
        }
    }

    private static func resetSidebarScroll(startingAt view: NSView) {
        guard let root = view.window?.contentView else { return }
        var candidates: [NSScrollView] = []
        collectScrollViews(in: root, into: &candidates)
        // A SwiftUI List is backed by NSTableView; the detail/console use plain
        // NSViews. Prefer table-backed scrollers, then take the leftmost one.
        // This never touches the detail or console scroll position.
        let tableScrollers = candidates.filter { $0.documentView is NSTableView }
        let pool = tableScrollers.isEmpty ? candidates : tableScrollers
        let target = pool.min { left, right in
            left.convert(left.bounds, to: nil).minX
                < right.convert(right.bounds, to: nil).minX
        }
        if let target = target { scrollToTop(target) }
    }

    private static func collectScrollViews(
        in view: NSView, into result: inout [NSScrollView]
    ) {
        if let scrollView = view as? NSScrollView { result.append(scrollView) }
        for subview in view.subviews {
            collectScrollViews(in: subview, into: &result)
        }
    }

    private static func scrollToTop(_ scrollView: NSScrollView) {
        let clip = scrollView.contentView
        let document = scrollView.documentView
        let topY: CGFloat
        if document?.isFlipped == true {
            topY = 0
        } else {
            topY = max(0, (document?.bounds.height ?? 0) - clip.bounds.height)
        }
        clip.scroll(to: NSPoint(x: 0, y: topY))
        scrollView.reflectScrolledClipView(clip)
    }
}
