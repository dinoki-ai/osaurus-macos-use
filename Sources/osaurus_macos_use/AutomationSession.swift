import Foundation

// MARK: - Automation Session
//
// Side-effect-free telemetry holder. v0.4 removed the on-screen HUD and the
// global Esc-cancel monitor: when the driver runs fully backgrounded the
// user neither sees nor needs to interrupt the agent's actions.
//
// The `start_/update_/end_automation_session` tools are still part of the
// surface area so existing agent prompts keep working; they just record a
// title/narration/step pair the agent can read back. Nothing in the input
// path consults this state any more.

// Wave 2: session state is keyed by agent scope so concurrent agents on an
// ABI v4+ host keep independent title/narration/step records. Nil agent id
// (v1 host, unit tests) uses the single "global" scope as before.

final class AutomationSession: @unchecked Sendable {
  static let shared = AutomationSession()

  private struct SessionState {
    var isActive: Bool = false
    var title: String = "Automation in progress"
    var narration: String? = nil
    var stepIndex: Int? = nil
    var totalSteps: Int? = nil
  }

  private let store = AgentKeyedStore<SessionState> { SessionState() }

  private init() {}

  // MARK: - State

  func isActive() -> Bool {
    store.withState { $0.isActive }
  }

  /// Snapshot used by the session tools to report current state. The
  /// `isCancelled` field is retained for response-shape stability with
  /// older clients but is now always `false`.
  func currentState() -> (
    title: String, narration: String?, stepIndex: Int?, totalSteps: Int?,
    isActive: Bool, isCancelled: Bool
  ) {
    store.withState { s in
      (s.title, s.narration, s.stepIndex, s.totalSteps, s.isActive, false)
    }
  }

  // MARK: - Lifecycle

  func startSession(title: String, totalSteps: Int? = nil, narration: String? = nil) {
    store.withState { s in
      s.isActive = true
      s.title = title.isEmpty ? "Automation in progress" : title
      s.narration = narration
      s.stepIndex = nil
      s.totalSteps = totalSteps
    }
  }

  func updateSession(
    title: String? = nil, narration: String? = nil,
    stepIndex: Int? = nil, totalSteps: Int? = nil
  ) {
    store.withState { s in
      if let title = title { s.title = title }
      if let narration = narration { s.narration = narration }
      if let stepIndex = stepIndex { s.stepIndex = stepIndex }
      if let totalSteps = totalSteps { s.totalSteps = totalSteps }
    }
  }

  func endSession(reason: String? = nil) {
    store.withState { s in
      s.isActive = false
      s.narration = nil
      s.stepIndex = nil
      s.totalSteps = nil
      s.title = "Automation in progress"
    }
    _ = reason
  }
}
