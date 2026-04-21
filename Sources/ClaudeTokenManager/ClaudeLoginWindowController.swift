import AppKit
import WebKit
import ClaudeTokenManagerCore

@MainActor
final class ClaudeLoginWindowController: NSWindowController, WKNavigationDelegate, NSWindowDelegate {

    /// Strong reference held while the login window is up so the controller
    /// is not deallocated when the SwiftUI view that opened it disappears.
    private static var active: ClaudeLoginWindowController?

    private let session: ClaudeWebSession
    private let completion: (Bool) -> Void
    private let webView: WKWebView
    private var didComplete = false
    private var pollTimer: Timer?

    static func present(session: ClaudeWebSession, completion: @escaping (Bool) -> Void) {
        let ctrl = ClaudeLoginWindowController(session: session, completion: completion)
        active = ctrl
        ctrl.showWindow(nil)
        ctrl.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(session: ClaudeWebSession, completion: @escaping (Bool) -> Void) {
        self.session = session
        self.completion = completion

        let config = WKWebViewConfiguration()
        // CRITICAL: share the singleton's data store so cookies set during
        // login are immediately visible to the background webView.
        config.websiteDataStore = session.websiteDataStore

        let initialFrame = NSRect(x: 0, y: 0, width: 480, height: 720)
        self.webView = WKWebView(frame: initialFrame, configuration: config)

        let window = NSWindow(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in to claude.ai"
        window.center()
        window.contentView = webView
        window.isReleasedWhenClosed = false

        super.init(window: window)

        window.delegate = self
        webView.navigationDelegate = self
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))

        // Safety net: WebKit can set the sessionKey cookie AFTER didFinish
        // (or after a JS-driven redirect that does not trigger our delegate
        // hooks). A 500ms poll catches every case until the window closes.
        startAuthPolling()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        pollTimer?.invalidate()
    }

    // MARK: - Auth detection

    private func startAuthPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkLoginCompletion()
            }
        }
    }

    /// Fires from didFinish, didCommit, AND the 500ms polling timer.
    /// Authoritative signal: the `sessionKey` cookie is present in the
    /// shared data store. URL-leaving-`/login` is also required to avoid
    /// a stale-cookie false positive when the user arrives mid-session.
    private func checkLoginCompletion() async {
        guard !didComplete else { return }

        let cookies = await session.websiteDataStore.httpCookieStore.allCookies()
        let cookieOK = cookies.contains { c in
            c.domain.contains("claude.ai") && c.name == "sessionKey" && !c.value.isEmpty
        }

        let urlStr = webView.url?.absoluteString ?? ""
        let urlOK = urlStr.contains("claude.ai") && !urlStr.contains("/login")

        guard cookieOK && urlOK else { return }

        didComplete = true
        pollTimer?.invalidate()
        pollTimer = nil

        await session.refreshAuthStatus()
        completion(session.isAuthenticated)
        Self.active = nil
        self.close()
    }

    // MARK: - WKNavigationDelegate

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            await self.checkLoginCompletion()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        Task { @MainActor in
            await self.checkLoginCompletion()
        }
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.pollTimer?.invalidate()
            self.pollTimer = nil
            if !self.didComplete {
                self.didComplete = true
                self.completion(false)
            }
            Self.active = nil
        }
    }
}
