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

    private var statusItemContainer: StatusItemContainerView?
    private var burstIcon: BurstIconView?
    private var percentLabel: NSTextField?

    private let iconSize: CGFloat = 18
    private let horizontalPadding: CGFloat = 6
    private let iconLabelSpacing: CGFloat = 4

    let usageStore = UsageStore()

    func setup() {
        setupStatusItem()
        setupPopover()
        setupGlobalClickOutside()
        observeStoreChanges()
        observeActivity()
        observeAccessibility()
    }

    deinit {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let containerHeight = NSStatusBar.system.thickness
        let initialWidth: CGFloat = horizontalPadding * 2 + iconSize + iconLabelSpacing + 30

        let container = StatusItemContainerView(frame: NSRect(
            x: 0, y: 0, width: initialWidth, height: containerHeight
        ))
        container.wantsLayer = true

        let icon = BurstIconView(frame: NSRect(
            x: horizontalPadding,
            y: (containerHeight - iconSize) / 2,
            width: iconSize,
            height: iconSize
        ))
        icon.autoresizingMask = []
        container.addSubview(icon)
        self.burstIcon = icon

        let label = NSTextField(labelWithString: "–")
        label.font = NSFont.menuBarFont(ofSize: 0)
        label.textColor = .labelColor
        label.backgroundColor = .clear
        label.drawsBackground = false
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        label.alignment = .left
        container.addSubview(label)
        self.percentLabel = label

        self.statusItemContainer = container
        statusItem.length = initialWidth
        statusItem.button?.subviews.forEach { $0.removeFromSuperview() }

        if let button = statusItem.button {
            button.image = nil
            button.title = ""
            button.addSubview(container)
            container.frame = button.bounds
            container.autoresizingMask = [.width, .height]
            button.target = self
            button.action = #selector(buttonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        updateLabel()
    }

    private func updateLabel() {
        guard let label = percentLabel else { return }

        let text: String
        if let session = usageStore.snapshot.remoteProgressBars.first(where: { $0.id == "session" }) {
            text = "\(Int(session.clampedPercent.rounded(.down)))%"
        } else {
            text = usageStore.compactLabel
        }

        label.stringValue = text
        layoutContainerContents()
    }

    private func layoutContainerContents() {
        guard let container = statusItemContainer,
              let label = percentLabel,
              let icon = burstIcon else { return }

        label.sizeToFit()
        let labelWidth = ceil(label.bounds.width)
        let totalWidth = horizontalPadding + iconSize + iconLabelSpacing + labelWidth + horizontalPadding
        let height = container.frame.height

        statusItem.length = totalWidth
        container.frame = NSRect(x: 0, y: 0, width: totalWidth, height: height)

        icon.frame = NSRect(
            x: horizontalPadding,
            y: (height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        label.frame = NSRect(
            x: horizontalPadding + iconSize + iconLabelSpacing,
            y: (height - label.bounds.height) / 2,
            width: labelWidth,
            height: label.bounds.height
        )
    }

    private func observeStoreChanges() {
        storeSubscription = usageStore.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateLabel() }
        }
    }

    // MARK: - Activity animation

    private func observeActivity() {
        activityCancellable = usageStore.$isClaudeCodeActive
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                if isActive {
                    self?.burstIcon?.startBreathingAnimation()
                } else {
                    self?.burstIcon?.stopBreathingAnimation()
                }
            }
    }

    private func observeAccessibility() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @objc private func accessibilityDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                self.burstIcon?.stopBreathingAnimation()
            } else if self.usageStore.isClaudeCodeActive {
                self.burstIcon?.startBreathingAnimation()
            }
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
        host.view.frame = NSRect(x: 0, y: 0, width: 380, height: 520)
        popover.contentViewController = host
        popover.contentSize = NSSize(width: 380, height: 520)
    }

    @objc private func buttonClicked(_ sender: Any?) {
        togglePopover(sender)
    }

    private func togglePopover(_ sender: Any?) {
        guard let anchor = statusItem.button ?? statusItemContainer else { return }

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

// MARK: - Click-passthrough container

/// Lets the hosting NSStatusBarButton receive the click by making
/// this view (and all of its subviews) transparent to hit-testing.
final class StatusItemContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
