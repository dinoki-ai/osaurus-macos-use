import CoreGraphics
import Foundation
import MacosUseSDK

// MARK: - JSON Helpers

private func jsonError(_ message: String) -> String {
  let escaped =
    message
    .replacingOccurrences(of: "\\", with: "\\\\")
    .replacingOccurrences(of: "\"", with: "\\\"")
    .replacingOccurrences(of: "\n", with: "\\n")
  return "{\"error\": \"\(escaped)\"}"
}

private func serializeResult<T: Encodable>(_ value: T) -> String {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  do {
    let jsonData = try encoder.encode(value)
    return String(data: jsonData, encoding: .utf8) ?? jsonError("Failed to encode result as UTF-8")
  } catch {
    return jsonError("Failed to serialize result: \(error.localizedDescription)")
  }
}

// MARK: - Modifier Flags Parsing

private func parseModifierFlags(_ flags: [String]?) -> CGEventFlags {
  guard let flags = flags else { return [] }

  var result: CGEventFlags = []
  for flag in flags {
    switch flag.lowercased() {
    case "capslock", "caps":
      result.insert(.maskAlphaShift)
    case "shift":
      result.insert(.maskShift)
    case "control", "ctrl":
      result.insert(.maskControl)
    case "option", "opt", "alt":
      result.insert(.maskAlternate)
    case "command", "cmd":
      result.insert(.maskCommand)
    case "help":
      result.insert(.maskHelp)
    case "function", "fn":
      result.insert(.maskSecondaryFn)
    case "numericpad", "numpad":
      result.insert(.maskNumericPad)
    default:
      break
    }
  }
  return result
}

// MARK: - Async Runner Helper

/// Runs an async @MainActor function synchronously and returns the result
private func runAsyncOnMain<T>(_ block: @escaping @MainActor () async -> T) -> T {
  let semaphore = DispatchSemaphore(value: 0)
  var result: T!

  Task { @MainActor in
    result = await block()
    semaphore.signal()
  }

  semaphore.wait()
  return result
}

// MARK: - Tool Implementations

// MARK: Open Application Tool
private struct OpenApplicationTool {
  let name = "open_application_and_traverse"

  struct Args: Decodable {
    let identifier: String
    let onlyVisibleElements: Bool?
  }

  func run(args: String) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return jsonError("Invalid arguments: expected 'identifier' field")
    }

    let result: ActionResult = runAsyncOnMain {
      var options = ActionOptions()
      options.traverseAfter = true
      options.onlyVisibleElements = input.onlyVisibleElements ?? false
      options.showAnimation = false

      return await performAction(
        action: .open(identifier: input.identifier),
        optionsInput: options
      )
    }

    return serializeResult(result)
  }
}

// MARK: Click Tool
private struct ClickTool {
  let name = "click_and_traverse"

  struct Args: Decodable {
    let pid: Int32
    let x: Double
    let y: Double
    let onlyVisibleElements: Bool?
  }

  func run(args: String) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return jsonError("Invalid arguments: expected 'pid', 'x', and 'y' fields")
    }

    let result: ActionResult = runAsyncOnMain {
      var options = ActionOptions()
      options.traverseAfter = true
      options.onlyVisibleElements = input.onlyVisibleElements ?? false
      options.showAnimation = false
      options.pidForTraversal = input.pid

      return await performAction(
        action: .input(action: .click(point: CGPoint(x: input.x, y: input.y))),
        optionsInput: options
      )
    }

    return serializeResult(result)
  }
}

// MARK: Type Tool
private struct TypeTool {
  let name = "type_and_traverse"

  struct Args: Decodable {
    let pid: Int32
    let text: String
    let onlyVisibleElements: Bool?
  }

  func run(args: String) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return jsonError("Invalid arguments: expected 'pid' and 'text' fields")
    }

    let result: ActionResult = runAsyncOnMain {
      var options = ActionOptions()
      options.traverseAfter = true
      options.onlyVisibleElements = input.onlyVisibleElements ?? false
      options.showAnimation = false
      options.pidForTraversal = input.pid

      return await performAction(
        action: .input(action: .type(text: input.text)),
        optionsInput: options
      )
    }

    return serializeResult(result)
  }
}

// MARK: Press Key Tool
private struct PressKeyTool {
  let name = "press_key_and_traverse"

  struct Args: Decodable {
    let pid: Int32
    let keyName: String
    let modifierFlags: [String]?
    let onlyVisibleElements: Bool?
  }

  func run(args: String) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return jsonError("Invalid arguments: expected 'pid' and 'keyName' fields")
    }

    let flags = parseModifierFlags(input.modifierFlags)

    let result: ActionResult = runAsyncOnMain {
      var options = ActionOptions()
      options.traverseAfter = true
      options.onlyVisibleElements = input.onlyVisibleElements ?? false
      options.showAnimation = false
      options.pidForTraversal = input.pid

      return await performAction(
        action: .input(action: .press(keyName: input.keyName, flags: flags)),
        optionsInput: options
      )
    }

    return serializeResult(result)
  }
}

// MARK: Refresh Traversal Tool
private struct RefreshTraversalTool {
  let name = "refresh_traversal"

  struct Args: Decodable {
    let pid: Int32
    let onlyVisibleElements: Bool?
  }

  func run(args: String) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return jsonError("Invalid arguments: expected 'pid' field")
    }

    let result: ActionResult = runAsyncOnMain {
      var options = ActionOptions()
      options.traverseAfter = true
      options.onlyVisibleElements = input.onlyVisibleElements ?? false
      options.showAnimation = false
      options.pidForTraversal = input.pid

      return await performAction(
        action: .traverseOnly,
        optionsInput: options
      )
    }

    return serializeResult(result)
  }
}

// MARK: - C ABI Surface

private typealias osr_plugin_ctx_t = UnsafeMutableRawPointer

private typealias osr_free_string_t = @convention(c) (UnsafePointer<CChar>?) -> Void
private typealias osr_init_t = @convention(c) () -> osr_plugin_ctx_t?
private typealias osr_destroy_t = @convention(c) (osr_plugin_ctx_t?) -> Void
private typealias osr_get_manifest_t = @convention(c) (osr_plugin_ctx_t?) -> UnsafePointer<CChar>?
private typealias osr_invoke_t =
  @convention(c) (
    osr_plugin_ctx_t?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?
  ) -> UnsafePointer<CChar>?

private struct osr_plugin_api {
  var free_string: osr_free_string_t?
  var `init`: osr_init_t?
  var destroy: osr_destroy_t?
  var get_manifest: osr_get_manifest_t?
  var invoke: osr_invoke_t?
}

// MARK: - Plugin Context

private class PluginContext {
  let openAppTool = OpenApplicationTool()
  let clickTool = ClickTool()
  let typeTool = TypeTool()
  let pressKeyTool = PressKeyTool()
  let refreshTool = RefreshTraversalTool()
}

// MARK: - Helper Functions

private func makeCString(_ s: String) -> UnsafePointer<CChar>? {
  guard let ptr = strdup(s) else { return nil }
  return UnsafePointer(ptr)
}

// MARK: - API Implementation

private var api: osr_plugin_api = {
  var api = osr_plugin_api()

  api.free_string = { ptr in
    if let p = ptr { free(UnsafeMutableRawPointer(mutating: p)) }
  }

  api.`init` = {
    let ctx = PluginContext()
    return Unmanaged.passRetained(ctx).toOpaque()
  }

  api.destroy = { ctxPtr in
    guard let ctxPtr = ctxPtr else { return }
    Unmanaged<PluginContext>.fromOpaque(ctxPtr).release()
  }

  api.get_manifest = { _ in
    let manifest = """
      {
        "plugin_id": "osaurus.macos-use",
        "version": "0.1.0",
        "description": "Control macOS applications via accessibility APIs - click, type, press keys, and traverse UI elements",
        "capabilities": {
          "tools": [
            {
              "id": "open_application_and_traverse",
              "description": "Opens or activates a specified application and then traverses its accessibility tree. Returns the UI element hierarchy.",
              "parameters": {
                "type": "object",
                "properties": {
                  "identifier": {
                    "type": "string",
                    "description": "The application's name (e.g., 'Calculator'), bundle ID (e.g., 'com.apple.calculator'), or file path"
                  },
                  "onlyVisibleElements": {
                    "type": "boolean",
                    "description": "If true, only return elements with valid position and size. Defaults to false."
                  }
                },
                "required": ["identifier"]
              },
              "requirements": ["accessibility"],
              "permission_policy": "ask"
            },
            {
              "id": "click_and_traverse",
              "description": "Simulates a mouse click at specific coordinates within the window of the target application and then traverses its accessibility tree.",
              "parameters": {
                "type": "object",
                "properties": {
                  "pid": {
                    "type": "integer",
                    "description": "The Process ID (PID) of the target application"
                  },
                  "x": {
                    "type": "number",
                    "description": "The X-coordinate for the click (screen coordinates)"
                  },
                  "y": {
                    "type": "number",
                    "description": "The Y-coordinate for the click (screen coordinates)"
                  },
                  "onlyVisibleElements": {
                    "type": "boolean",
                    "description": "If true, only return elements with valid position and size. Defaults to false."
                  }
                },
                "required": ["pid", "x", "y"]
              },
              "requirements": ["accessibility"],
              "permission_policy": "ask"
            },
            {
              "id": "type_and_traverse",
              "description": "Simulates typing text into the target application and then traverses its accessibility tree.",
              "parameters": {
                "type": "object",
                "properties": {
                  "pid": {
                    "type": "integer",
                    "description": "The Process ID (PID) of the target application"
                  },
                  "text": {
                    "type": "string",
                    "description": "The text to be typed"
                  },
                  "onlyVisibleElements": {
                    "type": "boolean",
                    "description": "If true, only return elements with valid position and size. Defaults to false."
                  }
                },
                "required": ["pid", "text"]
              },
              "requirements": ["accessibility"],
              "permission_policy": "ask"
            },
            {
              "id": "press_key_and_traverse",
              "description": "Simulates pressing a specific keyboard key with optional modifier keys, then traverses the accessibility tree.",
              "parameters": {
                "type": "object",
                "properties": {
                  "pid": {
                    "type": "integer",
                    "description": "The Process ID (PID) of the target application"
                  },
                  "keyName": {
                    "type": "string",
                    "description": "The name of the key (e.g., 'Return', 'Escape', 'Tab', 'ArrowUp', 'Delete', 'a', 'B'). Case-sensitive for letters."
                  },
                  "modifierFlags": {
                    "type": "array",
                    "items": { "type": "string" },
                    "description": "Optional modifier keys: CapsLock, Shift, Control, Option, Command, Function, NumericPad, Help"
                  },
                  "onlyVisibleElements": {
                    "type": "boolean",
                    "description": "If true, only return elements with valid position and size. Defaults to false."
                  }
                },
                "required": ["pid", "keyName"]
              },
              "requirements": ["accessibility"],
              "permission_policy": "ask"
            },
            {
              "id": "refresh_traversal",
              "description": "Only performs the accessibility tree traversal for the specified application. Useful for getting the current UI state without performing an action.",
              "parameters": {
                "type": "object",
                "properties": {
                  "pid": {
                    "type": "integer",
                    "description": "The Process ID (PID) of the application to traverse"
                  },
                  "onlyVisibleElements": {
                    "type": "boolean",
                    "description": "If true, only return elements with valid position and size. Defaults to false."
                  }
                },
                "required": ["pid"]
              },
              "requirements": ["accessibility"],
              "permission_policy": "ask"
            }
          ]
        }
      }
      """
    return makeCString(manifest)
  }

  api.invoke = { ctxPtr, typePtr, idPtr, payloadPtr in
    guard let ctxPtr = ctxPtr,
      let typePtr = typePtr,
      let idPtr = idPtr,
      let payloadPtr = payloadPtr
    else { return nil }

    let ctx = Unmanaged<PluginContext>.fromOpaque(ctxPtr).takeUnretainedValue()
    let type = String(cString: typePtr)
    let id = String(cString: idPtr)
    let payload = String(cString: payloadPtr)

    guard type == "tool" else {
      return makeCString(jsonError("Unknown capability type: \(type)"))
    }

    let result: String
    switch id {
    case ctx.openAppTool.name:
      result = ctx.openAppTool.run(args: payload)
    case ctx.clickTool.name:
      result = ctx.clickTool.run(args: payload)
    case ctx.typeTool.name:
      result = ctx.typeTool.run(args: payload)
    case ctx.pressKeyTool.name:
      result = ctx.pressKeyTool.run(args: payload)
    case ctx.refreshTool.name:
      result = ctx.refreshTool.run(args: payload)
    default:
      result = jsonError("Unknown tool: \(id)")
    }

    return makeCString(result)
  }

  return api
}()

// MARK: - Plugin Entry Point

@_cdecl("osaurus_plugin_entry")
public func osaurus_plugin_entry() -> UnsafeRawPointer? {
  return UnsafeRawPointer(&api)
}
