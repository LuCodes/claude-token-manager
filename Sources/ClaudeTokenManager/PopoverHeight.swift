import AppKit
import SwiftUI

/// Reports the natural rendered height of a SwiftUI view up to the
/// NSPopover host. Used by Dropdown / History / Preferences so the popover
/// resizes to fit each screen's content instead of being pinned at 520pt.
struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    /// Take the max across siblings instead of `value = nextValue()`. The
    /// default-overwrite reduce was silently zeroing the height: the
    /// reportingContentHeight wrapper places the GR-measured view next to
    /// a `Spacer` in a VStack, and SwiftUI feeds the Spacer's default
    /// (0) to reduce after the real measurement, clobbering the actual
    /// height before it reaches `onPreferenceChange`.
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Wrap the view in a VStack pinned to the top by a trailing
    /// `Spacer(minLength: 0)`, with a GeometryReader background on the
    /// view itself that publishes its rendered height through
    /// `ContentHeightPreferenceKey`.
    ///
    /// The Spacer matters: when `popover.contentSize` is larger than the
    /// view's intrinsic height (true on the very first frame, and during
    /// the gap between a view-switch and the next layout pass), the host
    /// places the SwiftUI root inside an oversized AppKit view. Without
    /// the Spacer, AppKit's default placement leaves a visible empty band
    /// above the content; the Spacer forces the content to top-align and
    /// the empty band collapses below (where it stays invisible until the
    /// next preference fires and resizes the popover to fit).
    func reportingContentHeight() -> some View {
        VStack(spacing: 0) {
            self
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ContentHeightPreferenceKey.self,
                            value: geo.size.height
                        )
                    }
                )
            Spacer(minLength: 0)
        }
    }
}

/// Bounds the popover's height. The minimum keeps it readable on first
/// open before the first preference fires; the maximum leaves a small
/// margin under the menu bar so the popover never butts against screen
/// edges. Computed at access time so a screen swap is reflected naturally.
enum PopoverSizing {
    static let width: CGFloat = 380
    static let minHeight: CGFloat = 200

    static var maxHeight: CGFloat {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame.height ?? 800
        return max(minHeight, visible - 40)
    }

    /// Cap for the scrollable body area in a view that already accounts
    /// for `chromeHeight` of fixed header + footer space. Used by
    /// `AutoHeightScrollView` so the body scrolls only when the content
    /// would push the total view past `maxHeight`.
    static func maxScrollHeight(chromeHeight: CGFloat) -> CGFloat {
        max(120, maxHeight - chromeHeight)
    }
}

/// PreferenceKey used internally by `AutoHeightScrollView` to publish its
/// content's intrinsic height back up to its own state. Defined at file
/// scope because Swift forbids stored-static properties on types nested
/// inside a generic.
private struct AutoScrollContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    /// Max-based reduce, mirroring `ContentHeightPreferenceKey`. With a
    /// default-overwrite reduce, sibling subtrees that emit the default
    /// (0) clobber the GR's real measurement before it reaches
    /// `onPreferenceChange`, leaving the AutoHeightScrollView frozen at
    /// its initial fallback height.
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// A vertical ScrollView that takes its content's natural height up to
/// `maxHeight`. Below that cap there is no scrolling and no empty space
/// at the bottom; at or above the cap it scrolls. Used as the body
/// region in each popover view so headers and footers stay fixed while
/// only the middle scrolls.
struct AutoHeightScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: () -> Content

    @State private var measuredHeight: CGFloat = 0

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            content()
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: AutoScrollContentHeightKey.self,
                            value: geo.size.height
                        )
                    }
                )
        }
        .frame(height: clampedHeight)
        .onPreferenceChange(AutoScrollContentHeightKey.self) { value in
            // The first layout pass reports 0 before the content lays out.
            // Treat that as "unknown — keep prior height" rather than
            // collapsing the scroll view to zero.
            guard value > 0 else { return }
            measuredHeight = value
        }
    }

    private var clampedHeight: CGFloat {
        if measuredHeight <= 0 { return min(120, maxHeight) }
        return min(measuredHeight, maxHeight)
    }
}
