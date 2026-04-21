import Foundation
import WebKit
import Combine

/// Singleton that owns a hidden WKWebView used to talk to claude.ai as a
/// real browser would. Replaces the URLSession-based ClaudeAPIClient + the
/// Keychain-stored session cookie scheme. WebKit handles cookies, TLS,
/// Fetch Metadata headers, and CORS automatically.
@MainActor
public final class ClaudeWebSession: NSObject, ObservableObject {

    public static let shared = ClaudeWebSession()

    @Published public private(set) var isAuthenticated: Bool = false
    @Published public private(set) var organizationId: String? = nil
    @Published public private(set) var lastError: String? = nil

    private let webView: WKWebView
    private let decoder: JSONDecoder

    /// Active continuation for an in-flight WKWebView navigation.
    /// We only ever load one URL at a time (https://claude.ai/) so a single
    /// slot is sufficient.
    private var pendingNavigation: CheckedContinuation<Void, Error>?

    private override init() {
        let config = WKWebViewConfiguration()
        // .default() persists cookies on disk under
        // ~/Library/WebKit/<bundle-id>/, isolated from Safari.
        config.websiteDataStore = WKWebsiteDataStore.default()
        self.webView = WKWebView(frame: .zero, configuration: config)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let c = try d.singleValueContainer()
            let s = try c.decode(String.self)
            // ISO8601DateFormatter isn't Sendable, so we instantiate inside
            // the closure rather than capture it.
            let primary = ISO8601DateFormatter()
            primary.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = primary.date(from: s) { return date }
            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            if let date = fallback.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(
                in: c,
                debugDescription: "Cannot parse date: \(s)"
            )
        }
        self.decoder = decoder

        super.init()
        webView.navigationDelegate = self

        Task { await self.refreshAuthStatus() }
    }

    // MARK: - Public API

    /// Cookie store shared with the login window. Both must use this same
    /// store so the login cookies are visible to the background webView.
    public var websiteDataStore: WKWebsiteDataStore {
        webView.configuration.websiteDataStore
    }

    /// Re-checks the cookie jar and, if a session is present, fetches the
    /// active organization id. Drives `isAuthenticated`.
    public func refreshAuthStatus() async {
        let cookies = await websiteDataStore.httpCookieStore.allCookies()
        let hasSessionKey = cookies.contains { c in
            c.domain.contains("claude.ai") && c.name == "sessionKey" && !c.value.isEmpty
        }
        self.isAuthenticated = hasSessionKey

        if hasSessionKey {
            await fetchOrganizationId()
        } else {
            self.organizationId = nil
        }
    }

    /// Removes all claude.ai-scoped cookies and storage from the WebKit data
    /// store, then clears local state.
    public func logout() async {
        let dataTypes: Set<String> = [
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeIndexedDBDatabases
        ]
        let records = await websiteDataStore.dataRecords(ofTypes: dataTypes)
        let claudeRecords = records.filter { record in
            record.displayName.contains("claude.ai") ||
            record.displayName.contains("anthropic")
        }
        if !claudeRecords.isEmpty {
            await websiteDataStore.removeData(ofTypes: dataTypes, for: claudeRecords)
        }

        // Belt-and-braces: also wipe by date if the displayName filter missed
        // any (some WebKit versions report records under different names).
        await websiteDataStore.removeData(
            ofTypes: [WKWebsiteDataTypeCookies],
            modifiedSince: .distantPast
        )

        self.isAuthenticated = false
        self.organizationId = nil
        self.lastError = nil
    }

    /// Fetches the typed usage report for the current organization.
    public func fetchUsage() async throws -> RawUsageReport {
        guard isAuthenticated else { throw ClaudeWebError.notAuthenticated }
        if organizationId == nil { await fetchOrganizationId() }
        guard let orgId = organizationId else { throw ClaudeWebError.notAuthenticated }

        let data = try await executeAPIRequest(path: "/api/organizations/\(orgId)/usage")
        do {
            return try decoder.decode(RawUsageReport.self, from: data)
        } catch {
            throw ClaudeWebError.invalidResponse
        }
    }

    // MARK: - Internal

    private func fetchOrganizationId() async {
        // Fast path: claude.ai sets a `lastActiveOrg` cookie containing the
        // current org UUID. Try that first to avoid an extra API call.
        let cookies = await websiteDataStore.httpCookieStore.allCookies()
        if let lastActiveOrg = cookies.first(where: { $0.name == "lastActiveOrg" })?.value,
           !lastActiveOrg.isEmpty {
            self.organizationId = lastActiveOrg
            self.lastError = nil
            return
        }

        // Fallback: call /api/organizations and pick the first UUID.
        do {
            let data = try await executeAPIRequest(path: "/api/organizations")
            guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let firstOrg = arr.first,
                  let uuid = firstOrg["uuid"] as? String else {
                self.lastError = "Could not parse organizations response"
                return
            }
            self.organizationId = uuid
            self.lastError = nil
        } catch {
            self.lastError = "Could not fetch organization: \(error.localizedDescription)"
        }
    }

    private func loadURL(_ url: URL) async throws {
        if pendingNavigation != nil {
            throw ClaudeWebError.invalidResponse
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pendingNavigation = cont
            webView.load(URLRequest(url: url))
        }
    }

    private func executeAPIRequest(path: String) async throws -> Data {
        if webView.url?.host != "claude.ai" {
            try await loadURL(URL(string: "https://claude.ai/")!)
        }

        // callAsyncJavaScript awaits Promises natively (unlike evaluateJavaScript,
        // which returns the Promise object as an "unsupported type" error). The
        // body is the inside of an async function; arguments are passed safely
        // through `arguments:` rather than interpolated into the source.
        let body = """
        const r = await fetch(path, {
            method: 'GET',
            credentials: 'include',
            headers: { 'Accept': 'application/json' }
        });
        if (!r.ok) return JSON.stringify({ __error: 'HTTP ' + r.status });
        return await r.text();
        """

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            webView.callAsyncJavaScript(
                body,
                arguments: ["path": path],
                in: nil,
                in: .page
            ) { result in
                switch result {
                case .failure(let error):
                    cont.resume(throwing: error)
                case .success(let value):
                    guard let str = value as? String,
                          let data = str.data(using: .utf8) else {
                        cont.resume(throwing: ClaudeWebError.invalidResponse)
                        return
                    }
                    if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errMsg = dict["__error"] as? String {
                        cont.resume(throwing: ClaudeWebError.apiError(errMsg))
                        return
                    }
                    cont.resume(returning: data)
                }
            }
        }
    }
}

// MARK: - WKNavigationDelegate

extension ClaudeWebSession: WKNavigationDelegate {
    nonisolated public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.pendingNavigation?.resume()
            self.pendingNavigation = nil
        }
    }

    nonisolated public func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor in
            self.pendingNavigation?.resume(throwing: error)
            self.pendingNavigation = nil
        }
    }

    nonisolated public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor in
            self.pendingNavigation?.resume(throwing: error)
            self.pendingNavigation = nil
        }
    }
}

// MARK: - Errors

public enum ClaudeWebError: Error, LocalizedError {
    case notAuthenticated
    case invalidResponse
    case apiError(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not logged in to claude.ai"
        case .invalidResponse:  return "Unexpected response from claude.ai"
        case .apiError(let m):  return "claude.ai error: \(m)"
        }
    }
}

// MARK: - Typed JSON model for /usage
//
// Preserved verbatim from the deleted ClaudeAPIClient so that
// ClaudeAIDataSource.convert(raw:) and existing tests keep working.

public struct RawUsageReport: Codable, Sendable {
    public let fiveHour: Pool?
    public let sevenDay: Pool?
    public let sevenDayOauthApps: Pool?
    public let sevenDayOpus: Pool?
    public let sevenDaySonnet: Pool?
    public let sevenDayCowork: Pool?
    public let sevenDayOmelette: Pool?
    public let iguanaNecktie: Pool?
    public let omelettePromotional: Pool?
    public let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOauthApps = "seven_day_oauth_apps"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayCowork = "seven_day_cowork"
        case sevenDayOmelette = "seven_day_omelette"
        case iguanaNecktie = "iguana_necktie"
        case omelettePromotional = "omelette_promotional"
        case extraUsage = "extra_usage"
    }

    public struct Pool: Codable, Sendable {
        public let utilization: Double
        public let resetsAt: Date
        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
        public init(utilization: Double, resetsAt: Date) {
            self.utilization = utilization
            self.resetsAt = resetsAt
        }
    }

    public struct ExtraUsage: Codable, Sendable {
        public let isEnabled: Bool
        public let utilization: Double?
        enum CodingKeys: String, CodingKey {
            case isEnabled = "is_enabled"
            case utilization
        }
        public init(isEnabled: Bool, utilization: Double?) {
            self.isEnabled = isEnabled
            self.utilization = utilization
        }
    }

    public init(
        fiveHour: Pool?,
        sevenDay: Pool?,
        sevenDayOauthApps: Pool?,
        sevenDayOpus: Pool?,
        sevenDaySonnet: Pool?,
        sevenDayCowork: Pool?,
        sevenDayOmelette: Pool?,
        iguanaNecktie: Pool?,
        omelettePromotional: Pool?,
        extraUsage: ExtraUsage?
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDayOauthApps = sevenDayOauthApps
        self.sevenDayOpus = sevenDayOpus
        self.sevenDaySonnet = sevenDaySonnet
        self.sevenDayCowork = sevenDayCowork
        self.sevenDayOmelette = sevenDayOmelette
        self.iguanaNecktie = iguanaNecktie
        self.omelettePromotional = omelettePromotional
        self.extraUsage = extraUsage
    }
}
