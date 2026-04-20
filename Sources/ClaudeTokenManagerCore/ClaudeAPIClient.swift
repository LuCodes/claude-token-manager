import Foundation
import CryptoKit

public final class ClaudeAPIClient: @unchecked Sendable {
    public static let shared = ClaudeAPIClient()

    public struct Endpoints {
        public static let baseURL = "https://claude.ai/api"
        public static func usageReport(orgId: String) -> String {
            return "\(baseURL)/organizations/\(orgId)/usage"
        }
    }

    private let session: URLSession
    private let pinDelegate = PinnedURLSessionDelegate()
    private let decoder: JSONDecoder

    public init(session: URLSession? = nil) {
        if let session = session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 15
            self.session = URLSession(
                configuration: config,
                delegate: pinDelegate,
                delegateQueue: nil
            )
        }
        self.decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = formatter.date(from: str) { return date }
            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            if let date = fallback.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot parse date: \(str)"
            )
        }
    }

    public func fetchUsageReport(
        organizationId: String,
        sessionKey: SessionKey
    ) async throws -> RawUsageReport {
        guard !sessionKey.isEmpty else {
            throw DataSourceError.authenticationRequired
        }
        guard let url = URL(string: Endpoints.usageReport(orgId: organizationId)) else {
            throw DataSourceError.apiChanged(details: "invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("*/*", forHTTPHeaderField: "accept")
        request.setValue("web_claude_ai", forHTTPHeaderField: "anthropic-client-platform")
        request.setValue("1.0.0", forHTTPHeaderField: "anthropic-client-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("https://claude.ai/settings/usage", forHTTPHeaderField: "referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36",
            forHTTPHeaderField: "user-agent"
        )
        request.setValue("sessionKey=\(sessionKey.unsafeRawValue)",
                         forHTTPHeaderField: "cookie")
        request.timeoutInterval = 15

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw DataSourceError.networkError(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw DataSourceError.networkError(
                underlying: NSError(domain: "ClaudeAPIClient", code: -1)
            )
        }

        switch http.statusCode {
        case 200: break
        case 401, 403: throw DataSourceError.authenticationExpired
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            throw DataSourceError.rateLimited(retryAfter: retry)
        case 500...599:
            throw DataSourceError.networkError(
                underlying: NSError(domain: "ClaudeAPIClient", code: http.statusCode)
            )
        default:
            throw DataSourceError.apiChanged(
                details: "unexpected HTTP status \(http.statusCode)"
            )
        }

        do {
            return try decoder.decode(RawUsageReport.self, from: data)
        } catch {
            throw DataSourceError.parseError(details: "failed to decode usage JSON")
        }
    }
}

// MARK: - Response types

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
    }

    public struct ExtraUsage: Codable, Sendable {
        public let isEnabled: Bool
        public let utilization: Double?
        enum CodingKeys: String, CodingKey {
            case isEnabled = "is_enabled"
            case utilization
        }
    }
}

// MARK: - Certificate pinning

final class PinnedURLSessionDelegate: NSObject, URLSessionDelegate {
    /// SHA-256 hashes of the SubjectPublicKeyInfo (SPKI) DER we trust for claude.ai.
    /// Extracted 2026-04-20 via scripts/extract-spki-hash.sh.
    /// Source: Let's Encrypt E8 chain.
    /// When empty, falls back to system trust (pinning disabled).
    private let pinnedSPKIHashes: Set<String> = [
        "6bbYmCUydTiUdHfXo26WKlDxCgYO032WlolDxthhXoM=", // Leaf (claude.ai)
        "iFvwVyJSxnQdyaUvUERIf+8qk7gRze3612JMwoO3zdU=", // Intermediate (Let's Encrypt E8)
    ]

    private let hostToPin = "claude.ai"

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host.hasSuffix(hostToPin),
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        guard let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              let leafCert = chain.first else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Extract the SPKI (SubjectPublicKeyInfo) from the DER certificate
        // using a minimal ASN.1 parser. This works for any key type/curve.
        let certDER = SecCertificateCopyData(leafCert) as Data
        guard let spkiData = SPKIExtractor.extractSPKI(from: certDER) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let hash = SHA256.hash(data: spkiData)
        let hashBase64 = Data(hash).base64EncodedString()

        if pinnedSPKIHashes.isEmpty {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
            return
        }

        if pinnedSPKIHashes.contains(hashBase64) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

// MARK: - Minimal ASN.1 DER parser for SPKI extraction

/// Extracts the SubjectPublicKeyInfo section from an X.509 DER certificate.
/// Algorithm-agnostic: works with RSA, EC P-256, EC P-384, Ed25519, etc.
enum SPKIExtractor {

    /// Parse a DER-encoded X.509 certificate and return the raw bytes of the
    /// SubjectPublicKeyInfo (SPKI) field, including its ASN.1 header.
    static func extractSPKI(from certDER: Data) -> Data? {
        // X.509 structure (simplified):
        //   SEQUENCE (Certificate)
        //     SEQUENCE (TBSCertificate)
        //       [0] version (context-specific, optional)
        //       INTEGER serialNumber
        //       SEQUENCE signature algorithm
        //       SEQUENCE issuer
        //       SEQUENCE validity
        //       SEQUENCE subject
        //       SEQUENCE subjectPublicKeyInfo  ← this is what we want
        //       ...

        var offset = 0
        let bytes = [UInt8](certDER)

        // Parse outer SEQUENCE (Certificate)
        guard let outerContent = parseSequence(bytes: bytes, offset: &offset) else { return nil }

        // Parse TBSCertificate SEQUENCE
        var tbsOffset = 0
        guard let tbsContent = parseSequence(bytes: outerContent, offset: &tbsOffset) else { return nil }

        var pos = 0

        // Skip version if present (context-specific [0])
        if pos < tbsContent.count && tbsContent[pos] == 0xA0 {
            guard skipTLV(bytes: tbsContent, offset: &pos) else { return nil }
        }

        // Skip serialNumber (INTEGER)
        guard skipTLV(bytes: tbsContent, offset: &pos) else { return nil }

        // Skip signature algorithm (SEQUENCE)
        guard skipTLV(bytes: tbsContent, offset: &pos) else { return nil }

        // Skip issuer (SEQUENCE)
        guard skipTLV(bytes: tbsContent, offset: &pos) else { return nil }

        // Skip validity (SEQUENCE)
        guard skipTLV(bytes: tbsContent, offset: &pos) else { return nil }

        // Skip subject (SEQUENCE)
        guard skipTLV(bytes: tbsContent, offset: &pos) else { return nil }

        // Next is subjectPublicKeyInfo (SEQUENCE) — capture the full TLV
        let spkiStart = pos
        guard skipTLV(bytes: tbsContent, offset: &pos) else { return nil }
        let spkiEnd = pos

        return Data(tbsContent[spkiStart..<spkiEnd])
    }

    // MARK: - ASN.1 DER primitives

    /// Parse a SEQUENCE tag and return its content bytes. Advances offset past the full TLV.
    private static func parseSequence(bytes: [UInt8], offset: inout Int) -> [UInt8]? {
        guard offset < bytes.count, bytes[offset] == 0x30 else { return nil }
        offset += 1
        guard let length = parseLength(bytes: bytes, offset: &offset) else { return nil }
        guard offset + length <= bytes.count else { return nil }
        let content = Array(bytes[offset..<(offset + length)])
        offset += length
        return content
    }

    /// Skip over a complete TLV (Tag-Length-Value) without parsing the value.
    @discardableResult
    private static func skipTLV(bytes: [UInt8], offset: inout Int) -> Bool {
        guard offset < bytes.count else { return false }
        offset += 1 // skip tag
        guard let length = parseLength(bytes: bytes, offset: &offset) else { return false }
        guard offset + length <= bytes.count else { return false }
        offset += length
        return true
    }

    /// Parse a DER length field. Supports short form (1 byte) and long form (multi-byte).
    private static func parseLength(bytes: [UInt8], offset: inout Int) -> Int? {
        guard offset < bytes.count else { return nil }
        let first = bytes[offset]
        offset += 1

        if first < 0x80 {
            return Int(first)
        }

        let numBytes = Int(first & 0x7F)
        guard numBytes > 0, numBytes <= 4, offset + numBytes <= bytes.count else { return nil }

        var length = 0
        for i in 0..<numBytes {
            length = (length << 8) | Int(bytes[offset + i])
        }
        offset += numBytes
        return length
    }
}
