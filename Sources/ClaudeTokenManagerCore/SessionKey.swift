import Foundation

/// Opaque wrapper around a sensitive session cookie.
/// Cannot be printed, logged, or serialized — by design.
public struct SessionKey: CustomStringConvertible,
                         CustomDebugStringConvertible {
    private let rawValue: String

    public init(_ value: String) {
        self.rawValue = value
    }

    /// Internal accessor used only when building HTTP requests.
    /// Callers must ensure the returned value is immediately passed to
    /// URLRequest.setValue and not stored anywhere else.
    internal var unsafeRawValue: String {
        return rawValue
    }

    public var isEmpty: Bool { rawValue.isEmpty }
    public var prefix6: String {
        String(rawValue.prefix(6)) + "\u{2026}"
    }

    public var description: String { "SessionKey(REDACTED)" }
    public var debugDescription: String { "SessionKey(REDACTED)" }
}

extension SessionKey: Sendable {}
