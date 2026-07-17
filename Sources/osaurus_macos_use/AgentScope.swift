import Foundation
import OsaurusPluginABI

// MARK: - Agent Scope
//
// Wave-1 flagged cross-agent GUI-state leakage: element-cache snapshots,
// most-recent-pid tracking, and automation-session state all lived in
// process-global singletons, so two agents driving this plugin through the
// same host clobbered each other's snapshots and misrouted implicit-pid
// input. On ABI v4+ hosts, `HostBridge.activeAgentId()` identifies the
// agent behind each invoke; that id now keys the GUI state.
//
// The id is only meaningful inside the invoke callback frame, so the invoke
// boundary resolves it ONCE and pins it here for the duration of the call.
// Tool bodies hop to the main thread (`DispatchQueue.main.sync`) while the
// invoke thread blocks, so the pin is process-global rather than
// thread-local; `withScope` serializes pinned sections so a concurrent
// invoke from another agent can never observe the wrong pin.
//
// Under a v1 host, outside a per-agent frame, or in unit tests the id is
// nil and everything falls back to the single "global" scope — exactly the
// wave-1 behavior.

enum AgentScope {
  /// Scope key used when no agent id is available.
  static let globalKey = "global"

  /// Quick lock guarding `current` (read from any thread via `currentKey`).
  private static let pinLock = NSLock()
  /// Held for the whole pinned section so concurrent invokes from
  /// different agents cannot interleave their scope pins.
  private static let serialLock = NSLock()
  nonisolated(unsafe) private static var current: String?

  /// The scope key for the in-flight invoke: the active agent's uuid, or
  /// "global" when none is pinned.
  static func currentKey() -> String {
    pinLock.lock()
    defer { pinLock.unlock() }
    return current ?? globalKey
  }

  /// Pin `agentId` (nil = global) for the duration of `body`.
  /// The invoke boundary calls this with `HostBridge.shared.activeAgentId()`.
  static func withScope<T>(_ agentId: String?, _ body: () -> T) -> T {
    serialLock.lock()
    defer { serialLock.unlock() }
    pinLock.lock()
    let previous = current
    current = agentId
    pinLock.unlock()
    defer {
      pinLock.lock()
      current = previous
      pinLock.unlock()
    }
    return body()
  }
}

// MARK: - Agent-Keyed Store

/// Minimal keyed store: one `State` value per agent scope, created lazily
/// on first access. This is the wrapper the GUI-state singletons
/// (`AccessibilityManager`, `AutomationSession`) hang their mutable state
/// on — the accessibility/SkyLight/input code itself is untouched.
///
/// All access runs under one lock; `body` must not re-enter the store and
/// should not perform slow work (copy data out instead).
final class AgentKeyedStore<State>: @unchecked Sendable {
  private let lock = NSLock()
  private var states: [String: State] = [:]
  private let makeState: @Sendable () -> State

  init(makeState: @escaping @Sendable () -> State) {
    self.makeState = makeState
  }

  /// Run `body` with exclusive access to the state for the current scope.
  func withState<T>(_ body: (inout State) -> T) -> T {
    withState(forKey: AgentScope.currentKey(), body)
  }

  /// Run `body` with exclusive access to the state for an explicit key.
  func withState<T>(forKey key: String, _ body: (inout State) -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    var state = states[key] ?? makeState()
    let result = body(&state)
    states[key] = state
    return result
  }
}
