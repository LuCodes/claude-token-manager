import AppKit
import SwiftUI
import Combine
import ClaudeTokenManagerCore

@MainActor
final class StatusBarController: NSObject {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var storeSubscription: AnyCancellable?
    private var activityCancellable: AnyCancellable?
    private var globalMonitor: Any?

    /// Tracked separately from button.title so we can re-render when the
    /// active state changes without recomputing the label string.
    private var currentLabel: String = ""

    private let iconSize: CGFloat = 18

    let usageStore = UsageStore()

    func setup() {
        setupStatusItem()
        setupPopover()
        setupGlobalClickOutside()
        observeStoreChanges()
        observeActivity()
    }

    deinit {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
    }

    // MARK: - Status Item
    //
    // Earlier versions placed a custom layer-backed NSView (StatusItemContainerView
    // hosting BurstIconView + an NSTextField) inside the status item button.
    // On macOS 26 that triggers ~30 Hz redraws of the status item — each one
    // regenerates a Gaussian-blurred shadow image via vImage convolution —
    // which kept ~one CPU core busy whenever the app was running, even with
    // no animation, no refresh, no activity monitor. Switching to the native
    // `button.image` + `button.title` API drops the steady-state CPU to ~0%.

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem.button else { return }
        button.image = BurstIconView.renderTemplateImage(
            size: NSSize(width: iconSize, height: iconSize)
        )
        button.imagePosition = .imageLeft
        button.imageHugsTitle = true
        button.target = self
        button.action = #selector(buttonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        renderTitle()
    }

    private func computeLabelText() -> String {
        if let session = usageStore.snapshot.remoteProgressBars.first(where: { $0.id == "session" }) {
            return "\(Int(session.clampedPercent.rounded(.down)))%"
        }
        return usageStore.compactLabel
    }

    /// Compose the title string and assign it to the status item button.
    /// The active indicator is a leading bullet inserted only on state
    /// transitions, so no re-render happens during a typical refresh.
    private func renderTitle() {
        guard let button = statusItem.button else { return }

        let prefix = usageStore.isClaudeCodeActive ? "• " : ""
        let next = prefix + currentLabel
        guard button.title != next else { return }
        button.title = next
    }

    private func updateLabel() {
        let text = computeLabelText()
        guard text != currentLabel else { return }
        currentLabel = text
        renderTitle()
    }

    private func observeStoreChanges() {
        storeSubscription = usageStore.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateLabel() }
        }
    }

    private func observeActivity() {
        activityCancellable = usageStore.$isClaudeCodeActive
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.renderTitle()
            }
    }

    // MARK: - Popover

    private var heightPropagatorHost: NSHostingController<AnyView>?

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .semitransient
        popover.animates = true

        // Bridge the SwiftUI ContentHeightPreferenceKey emitted by each
        // popover view (Dropdown / History / Preferences) into popover
        // sizing. Each view sets `.frame(width: 380).fixedSize(vertical:
        // true).reportingContentHeight()`, so the value we receive is the
        // exact natural height of the currently-visible screen.
        let rootView = AnyView(
            DropdownView()
                .environmentObject(usageStore)
                .onPreferenceChange(ContentHeightPreferenceKey.self) { [weak self] height in
                    self?.applyContentHeight(height)
                }
        )

        let host = NSHostingController(rootView: rootView)
        // Keep `sizingOptions = []` so NSHostingController never overrides
        // preferredContentSize from SwiftUI intrinsic — we drive the size
        // ourselves through `applyContentHeight`. Initial guess matches
        // the historical fixed value so the first frame is visually close
        // to the final layout.
        host.sizingOptions = []
        host.preferredContentSize = NSSize(width: PopoverSizing.width, height: 520)
        host.view.frame = NSRect(x: 0, y: 0, width: PopoverSizing.width, height: 520)
        heightPropagatorHost = host
        popover.contentViewController = host
        popover.contentSize = NSSize(width: PopoverSizing.width, height: 520)
    }

    /// Reflects the active SwiftUI screen's natural height into the
    /// popover, clamped to `[PopoverSizing.minHeight, PopoverSizing.maxHeight]`.
    /// During the breakdown's open/close animation in HistoryView this
    /// fires at every interpolated frame; the early-out on a 1pt threshold
    /// stops a runaway feedback where each apply triggers another layout
    /// pass that re-publishes the same value.
    private func applyContentHeight(_ proposed: CGFloat) {
        guard proposed > 0 else { return }
        let clamped = min(PopoverSizing.maxHeight, max(PopoverSizing.minHeight, proposed))
        let target = NSSize(width: PopoverSizing.width, height: clamped)
        if abs(popover.contentSize.height - target.height) < 1 { return }

        // NSPopover animates contentSize on its own when `popover.animates`
        // is true; wrapping the assignment in NSAnimationContext is
        // redundant and (in practice on macOS 26) prevents the new value
        // from sticking once the popover is already shown. Mirroring the
        // same size into `host.preferredContentSize` keeps it pinned across
        // close/reopen cycles, so the popover comes back at the screen's
        // last height instead of resetting to the 520pt initial guess.
        popover.contentSize = target
        heightPropagatorHost?.preferredContentSize = target
    }

    @objc private func buttonClicked(_ sender: Any?) {
        togglePopover(sender)
    }

    private func togglePopover(_ sender: Any?) {
        guard let anchor = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            popover.contentViewController?.view.window?.makeFirstResponder(nil)
        }
    }

    private func setupGlobalClickOutside() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            if self?.popover.isShown == true {
                self?.popover.performClose(nil)
            }
        }
    }
}
