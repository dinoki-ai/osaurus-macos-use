import Foundation
import OsaurusPluginKit

// MARK: - Canonical Tool-Result Envelope (SDK-backed)
//
// The canonical failure shape and the generic builders now come from
// OsaurusPluginKit's `Envelope` (wave 2 SDK adoption). This file keeps only
// the plugin-specific pieces: mapping failed ElementActionResult/InputResult
// values into canonical failure envelopes at the invoke boundary.
//
// The host AUTO-WRAPS any non-envelope tool output as a SUCCESS
// ({"ok":true,"result":<raw output>}). That means a tool error returned as a
// bare string or as `{"error": "..."}` is silently misclassified as a
// success. Every *error* path must emit the canonical failure envelope:
//
//   {"ok":false,"kind":"<kind>","message":"...","retryable":<bool>}
//
// Success payloads are deliberately left raw — the host wraps them — so the
// existing widget/screenshot/observe/action shapes are unchanged.

extension Envelope {
  /// Failure envelope with a structured `data` payload so callers keep the
  /// machine-readable details (stale/removed/pid/...) that used to ride on
  /// the raw result shape. Bridges Encodable payloads into the SDK's
  /// `dataJSON` slot with the same encoder settings wave 1 used.
  static func failure(
    _ kind: Kind, _ message: String, retryable: Bool? = nil, data: some Encodable
  ) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let encoded = try? encoder.encode(data),
      let dataJSON = String(data: encoded, encoding: .utf8)
    else { return failure(kind, message, retryable: retryable) }
    return failure(kind, message, retryable: retryable, dataJSON: dataJSON)
  }

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
}
