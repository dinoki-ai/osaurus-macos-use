import Foundation
import OsaurusPluginABI
import OsaurusPluginKit
import Testing

@testable import osaurus_macos_use

// MARK: - Agent Scope Isolation Tests
//
// Wave 2 keys the element-cache snapshots, most-recent-pid tracking, and
// automation-session state by the active agent id (ABI v4+ hosts). These
// tests drive the keyed stores with synthetic agent ids and verify:
//   - two agents see fully independent recent-pid / cache / session state,
//   - a nil agent id falls back to the single "global" scope (wave-1
//     behavior, which the 116 wave-1 tests exercise end-to-end),
//   - every action result echoes the scope it used ("agent_scope"),
//   - the invoke boundary picks the agent id up from a v4 HostBridge.
//
// Synthetic ids are UUID-suffixed so scopes never collide across tests,
// and the tests never mutate the "global" scope (the wave-1 suites depend
// on its state).

@Suite("Agent Scope Isolation", .serialized)
struct AgentScopeIsolationTests {

  private func syntheticAgent(_ label: String) -> String {
    "test-agent-\(label)-\(UUID().uuidString)"
  }

  @Test("two synthetic agents track independent recent pids")
  func recentPidIsolation() {
    let agentA = syntheticAgent("a")
    let agentB = syntheticAgent("b")

    _ = AgentScope.withScope(agentA) {
      AccessibilityManager.shared.beginNewSnapshot(pid: 11111)
    }

    #expect(
      AgentScope.withScope(agentA) { AccessibilityManager.shared.mostRecentPid() } == 11111)
    #expect(
      AgentScope.withScope(agentB) { AccessibilityManager.shared.mostRecentPid() } == nil)

    _ = AgentScope.withScope(agentB) {
      AccessibilityManager.shared.beginNewSnapshot(pid: 22222)
    }

    // B taking a snapshot must not disturb A's recent pid, and vice versa.
    #expect(
      AgentScope.withScope(agentA) { AccessibilityManager.shared.mostRecentPid() } == 11111)
    #expect(
      AgentScope.withScope(agentB) { AccessibilityManager.shared.mostRecentPid() } == 22222)
  }

  @Test("element-cache snapshots are per agent")
  func elementCacheIsolation() {
    let agentA = syntheticAgent("a")
    let agentB = syntheticAgent("b")

    let snapId = AgentScope.withScope(agentA) {
      AccessibilityManager.shared.beginNewSnapshot(pid: 33333)
    }
    let elementId = "s\(snapId)-1"

    // Agent A remembers the snapshot: the id parses, the snapshot exists,
    // but no element was cached under it -> .removed.
    let lookupA = AgentScope.withScope(agentA) {
      AccessibilityManager.shared.lookup(id: elementId)
    }
    guard case .removed = lookupA else {
      Issue.record("Expected .removed for agent A, got \(lookupA)")
      return
    }

    // Agent B never saw that snapshot -> .stale, proving the snapshot
    // dictionary is not shared across scopes.
    let lookupB = AgentScope.withScope(agentB) {
      AccessibilityManager.shared.lookup(id: elementId)
    }
    guard case .stale = lookupB else {
      Issue.record("Expected .stale for agent B, got \(lookupB)")
      return
    }

    // Snapshot counters are per scope too: agent B's first snapshot is s1
    // regardless of how many snapshots agent A has taken.
    let firstB = AgentScope.withScope(agentB) {
      AccessibilityManager.shared.beginNewSnapshot(pid: 44444)
    }
    #expect(firstB == 1)
  }

  @Test("automation sessions are per agent")
  func sessionIsolation() {
    let agentA = syntheticAgent("a")
    let agentB = syntheticAgent("b")

    AgentScope.withScope(agentA) {
      AutomationSession.shared.startSession(title: "Agent A flow", totalSteps: 3)
    }

    let stateA = AgentScope.withScope(agentA) { AutomationSession.shared.currentState() }
    #expect(stateA.isActive == true)
    #expect(stateA.title == "Agent A flow")

    let stateB = AgentScope.withScope(agentB) { AutomationSession.shared.currentState() }
    #expect(stateB.isActive == false)
    #expect(stateB.title == "Automation in progress")

    AgentScope.withScope(agentA) {
      AutomationSession.shared.endSession(reason: "test done")
    }
    #expect(
      AgentScope.withScope(agentA) { AutomationSession.shared.currentState() }.isActive == false)
  }

  @Test("nil agent id falls back to the global scope")
  func nilScopeFallsBackToGlobal() {
    // Outside any scope pin, the key is "global".
    #expect(AgentScope.currentKey() == AgentScope.globalKey)
    // A nil pin (v1 host / outside an agent frame) is the same scope.
    AgentScope.withScope(nil) {
      #expect(AgentScope.currentKey() == AgentScope.globalKey)
    }

    // Unscoped writes and withScope(nil) reads hit the same slot; a
    // synthetic agent gets a fresh one. (Exercised on a private store so
    // the wave-1 suites' global singleton state stays untouched.)
    let store = AgentKeyedStore<Int> { 0 }
    store.withState { $0 = 42 }
    #expect(AgentScope.withScope(nil) { store.withState { $0 } } == 42)
    #expect(AgentScope.withScope(syntheticAgent("fresh")) { store.withState { $0 } } == 0)
    #expect(store.withState(forKey: AgentScope.globalKey) { $0 } == 42)
  }

  @Test("action results echo the agent scope they used")
  func actionResultsEchoScope() throws {
    let agentA = syntheticAgent("a")

    let scoped = AgentScope.withScope(agentA) { ElementActionResult.ok() }
    #expect(scoped.agentScope == agentA)

    let global = ElementActionResult.ok()
    #expect(global.agentScope == AgentScope.globalKey)

    // Wire shape: the field serializes as "agent_scope".
    let data = try JSONEncoder().encode(scoped)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(json["agent_scope"] as? String == agentA)

    // Failure envelopes carry it under data.agent_scope.
    let failure = AgentScope.withScope(agentA) {
      Envelope.actionFailure(.stale(requested: 1, current: 2))
    }
    let failureJSON =
      try JSONSerialization.jsonObject(with: failure.data(using: .utf8)!) as! [String: Any]
    #expect((failureJSON["data"] as? [String: Any])?["agent_scope"] as? String == agentA)

    // Input results too.
    let input = AgentScope.withScope(agentA) { InputResult.ok() }
    #expect(input.agentScope == agentA)
  }

  @Test("invoke boundary picks up the agent id from a v4 host")
  func invokeUsesHostAgentId() throws {
    var host = OsrHostAPI(
      version: OsrABIVersion.v4,
      get_active_agent_id: mockGetActiveAgentId
    )
    let entry = withUnsafePointer(to: &host) {
      osaurus_plugin_entry_v2(UnsafeRawPointer($0))
    }
    // Uninstall before returning so concurrent suites keep seeing the
    // no-host (global) behavior.
    defer { HostBridge.shared.install(nil) }

    let api = try #require(entry).assumingMemoryBound(to: OsrPluginAPI.self).pointee
    #expect(api.version == OsrABIVersion.v2)

    let ctx = try #require(api.`init`?())
    defer { api.destroy?(ctx) }

    // A stale-id click is deterministic (no live app or TCC permission
    // needed) and its failure envelope must attribute the mock agent's
    // scope, not "global".
    let resultPtr = "tool".withCString { typePtr in
      "click_element".withCString { idPtr in
        #"{"id": "s99999999-1"}"#.withCString { payloadPtr in
          api.invoke?(ctx, typePtr, idPtr, payloadPtr)
        }
      }
    }
    let result = try #require(resultPtr).pointee != 0 ? String(cString: resultPtr!) : ""
    api.free_string?(resultPtr)

    let json =
      try JSONSerialization.jsonObject(with: result.data(using: .utf8)!) as! [String: Any]
    #expect(json["ok"] as? Bool == false)
    #expect(json["kind"] as? String == "not_found")
    let data = json["data"] as? [String: Any]
    #expect(data?["stale"] as? Bool == true)
    #expect(data?["agent_scope"] as? String == mockAgentUUID)
  }
}

// MARK: - Mock host plumbing
//
// `get_active_agent_id` is a C function pointer: it cannot capture state,
// so the mock uuid lives in file-scope constants. The bridge frees the
// returned string via libc free() on pre-v6 hosts, pairing with strdup.

private let mockAgentUUID = "3f2504e0-4f89-11d3-9a0c-0305e82c3301"

private let mockGetActiveAgentId: OsrGetActiveAgentIdFn = {
  strdup(mockAgentUUID).map { UnsafePointer($0) }
}
