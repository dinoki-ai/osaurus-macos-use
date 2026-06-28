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
  }

  static func failure(_ kind: Kind, _ message: String, retryable: Bool? = nil) -> String {
    let retry = retryable ?? defaultRetryable(for: kind)
    return "{\"ok\":false,\"kind\":\"\(kind.rawValue)\",\"message\":\"\(escape(message))\",\"retryable\":\(retry)}"
  }

  static func successRaw(_ jsonPayload: String) -> String { "{\"ok\":true,\"result\":\(jsonPayload)}" }

  private static func defaultRetryable(for kind: Kind) -> Bool {
    switch kind {
    case .invalidArgs, .executionError, .unavailable: return true
    case .notFound: return false
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
