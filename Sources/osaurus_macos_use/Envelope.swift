import Foundation

// MARK: - Canonical Tool-Result Envelope
//
// The host AUTO-WRAPS any non-envelope tool output as a SUCCESS
// ({"ok":true,"result":<raw output>}). That means a tool error returned as a
// bare string or as `{"error": "..."}` is silently misclassified as a success.
//
// To make failures observable, every *error* path must emit the canonical
// failure envelope produced here:
//
//   {"ok":false,"kind":"<kind>","message":"...","retryable":<bool>}
//
// Success payloads are deliberately left raw — the host wraps them — so the
// existing widget/screenshot/observe/action shapes are unchanged.
enum Envelope {
  enum Kind: String {
    case invalidArgs = "invalid_args"
    case executionError = "execution_error"
    case notFound = "not_found"
    case unavailable = "unavailable"
    case timeout = "timeout"
  }

  static func failure(_ kind: Kind, _ message: String, retryable: Bool? = nil) -> String {
    let retry = retryable ?? defaultRetryable(for: kind)
    return "{\"ok\":false,\"kind\":\"\(kind.rawValue)\",\"message\":\"\(escape(message))\",\"retryable\":\(retry)}"
  }

  /// Failure envelope with a structured `data` payload so callers keep the
  /// machine-readable details (stale/removed/pid/...) that used to ride on
  /// the raw result shape.
  static func failure(
    _ kind: Kind, _ message: String, retryable: Bool? = nil, data: some Encodable
  ) -> String {
    let base = failure(kind, message, retryable: retryable)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let encoded = try? encoder.encode(data),
      let dataJSON = String(data: encoded, encoding: .utf8)
    else { return base }
    return String(base.dropLast()) + ",\"data\":\(dataJSON)}"
  }

  static func successRaw(_ jsonPayload: String) -> String { "{\"ok\":true,\"result\":\(jsonPayload)}" }

  // MARK: Failed-result normalization
  //
  // The host auto-wraps any non-envelope output as a success, so a raw
  // `{"success":false, ...}` ElementActionResult/InputResult reads as a
  // successful call. Every failed result must be converted here before it
  // crosses the invoke boundary.

  struct ActionFailureData: Encodable {
    let stale: Bool?
    let removed: Bool?
    let cancelled: Bool?
    let pid: Int32?
    let app: String?
  }

  static func kind(forFailedAction result: ElementActionResult) -> Kind {
    if result.invalidArgs == true { return .invalidArgs }
    if result.stale == true || result.removed == true { return .notFound }
    return .executionError
  }

  static func actionFailure(_ result: ElementActionResult) -> String {
    return failure(
      kind(forFailedAction: result),
      result.error ?? "Action failed",
      data: ActionFailureData(
        stale: result.stale, removed: result.removed, cancelled: result.cancelled,
        pid: result.pid, app: result.app))
  }

  static func inputFailure(_ result: InputResult) -> String {
    return failure(.executionError, result.error ?? "Input failed")
  }

  private static func defaultRetryable(for kind: Kind) -> Bool {
    switch kind {
    case .executionError, .unavailable, .timeout: return true
    case .invalidArgs, .notFound: return false
    }
  }

  static func escape(_ s: String) -> String {
    var out = ""
    out.reserveCapacity(s.count + 2)
    for ch in s {
      switch ch {
      case "\\": out += "\\\\"
      case "\"": out += "\\\""
      case "\n": out += "\\n"
      case "\r": out += "\\r"
      case "\t": out += "\\t"
      default:
        if let a = ch.asciiValue, a < 0x20 {
          out += String(format: "\\u%04x", a)
        } else {
          out.append(ch)
        }
      }
    }
    return out
  }
}
