import Foundation
import OsaurusPluginABI
import OsaurusPluginKit
import OsaurusPluginTestSupport
import Testing

@testable import osaurus_macos_use

// MARK: - SDK Conformance Tests
//
// Standard wave-2 conformance checks from OsaurusPluginTestSupport:
// manifest registry conformance, ABI conformance against the plugin's real
// entry pointers, and the canonical-failure envelope shape.

@Suite("SDK Conformance")
struct SDKConformanceTests {

  @Test("manifest passes registry conformance")
  func manifestConformance() throws {
    try ManifestConformance.assertConformant(PluginManifest.json)
  }

  @Test("v1 entry point passes ABI conformance")
  func v1EntryConformance() throws {
    try ABIConformance.assertEntryConformance(
      osaurus_plugin_entry(), manifestJSON: PluginManifest.json)
  }

  @Test("v2 entry point passes ABI conformance and declares version 2")
  func v2EntryConformance() throws {
    // entry_v2 (re)installs the host into HostBridge.shared; serialize
    // with the mock-host test so a nil install can't race its window.
    hostBridgeTestLock.lock()
    defer { hostBridgeTestLock.unlock() }

    // nil host: enterV2 tolerates it (HostBridge stays uninstalled) and
    // must still return the fully-populated API table.
    let entry = osaurus_plugin_entry_v2(nil)
    try ABIConformance.assertEntryConformance(entry, manifestJSON: PluginManifest.json)
    let api = try #require(entry).assumingMemoryBound(to: OsrPluginAPI.self).pointee
    #expect(api.version == OsrABIVersion.v2)
  }

  @Test("failure envelopes are canonical")
  func canonicalFailureShape() throws {
    try assertCanonicalFailure(
      Envelope.failure(.invalidArgs, "bad args"), kind: .invalidArgs)
    try assertCanonicalFailure(
      Envelope.actionFailure(.stale(requested: 1, current: 2)), kind: .notFound)
    try assertCanonicalFailure(
      Envelope.inputFailure(.fail("boom")), kind: .executionError)
  }
}
