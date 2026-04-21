import AppKit
import SwiftUI
import Combine
import ClaudeTokenManagerCore

@MainActor
final class StatusBarController: NSObject {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var storeSubscription: AnyCancellable?
    private var globalMonitor: Any?

    let usageStore = UsageStore()

    func setup() {
        setupStatusItem()
        setupPopover()
        setupGlobalClickOutside()
        observeStoreChanges()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem.button else { return }

        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "pdf"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            button.image = image
        }

        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.font = NSFont.menuBarFont(ofSize: 0)

        button.action = #selector(togglePopover(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        updateLabel()
    }

    private func updateLabel() {
        guard let button = statusItem?.button else { return }

        let text: String
        if let session = usageStore.snapshot.remoteProgressBars.first(where: { $0.id == "session" }) {
            text = "\(Int(session.clampedPercent.rounded(.down)))%"
        } else {
            text = usageStore.compactLabel
        }

        button.title = text
    }

    private func observeStoreChanges() {
        storeSubscription = usageStore.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateLabel() }
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

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
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
