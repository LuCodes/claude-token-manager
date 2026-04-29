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

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .semitransient
        popover.animates = true

        let rootView = DropdownView()
            .environmentObject(usageStore)
            .frame(width: 380, height: 520, alignment: .top)

        let host = NSHostingController(rootView: rootView)
        // Opt out of NSHostingController's default sizingOptions, which sync
        // preferredContentSize from SwiftUI's intrinsic content size. On
        // macOS 14+ the intrinsic height of DropdownView (header + un-scrolled
        // body + footer ≈ 1000pt+) bubbled up as the popover's preferred size,
        // pushing the popover off-screen so only the footer remained visible.
        host.sizingOptions = []
        host.preferredContentSize = NSSize(width: 380, height: 520)
        host.view.frame = NSRect(x: 0, y: 0, width: 380, height: 520)
        popover.contentViewController = host
        popover.contentSize = NSSize(width: 380, height: 520)
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
