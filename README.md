# osaurus-macos-use

An Osaurus plugin for controlling macOS applications via accessibility APIs. Based on [mcp-server-macos-use](https://github.com/mediar-ai/mcp-server-macos-use).

## Prerequisites

**Accessibility permissions are required.** Grant permission in:

- System Preferences > Security & Privacy > Privacy > Accessibility

Add the application using this plugin (e.g., Osaurus, or your terminal if running from CLI).

## Tools

### `open_application_and_traverse`

Opens or activates a specified application and traverses its accessibility tree.

**Parameters:**

- `identifier` (required): App name, bundle ID, or file path
- `onlyVisibleElements` (optional): Filter to visible elements only

**Example:**

```json
{
  "identifier": "Calculator"
}
```

### `click_and_traverse`

Simulates a mouse click at specific coordinates and traverses the accessibility tree.

**Parameters:**

- `pid` (required): Process ID of the target application
- `x` (required): X-coordinate for the click
- `y` (required): Y-coordinate for the click
- `onlyVisibleElements` (optional): Filter to visible elements only

**Example:**

```json
{
  "pid": 12345,
  "x": 100.0,
  "y": 200.0
}
```

### `type_and_traverse`

Simulates typing text into the target application and traverses the accessibility tree.

**Parameters:**

- `pid` (required): Process ID of the target application
- `text` (required): The text to type
- `onlyVisibleElements` (optional): Filter to visible elements only

**Example:**

```json
{
  "pid": 12345,
  "text": "Hello, world!"
}
```

### `press_key_and_traverse`

Simulates pressing a keyboard key with optional modifiers and traverses the accessibility tree.

**Parameters:**

- `pid` (required): Process ID of the target application
- `keyName` (required): Key name (e.g., `Return`, `Escape`, `Tab`, `ArrowUp`, `a`, `B`)
- `modifierFlags` (optional): Array of modifiers (`Shift`, `Command`, `Control`, `Option`, `Function`, `CapsLock`, `NumericPad`, `Help`)
- `onlyVisibleElements` (optional): Filter to visible elements only

**Example:**

```json
{
  "pid": 12345,
  "keyName": "Return",
  "modifierFlags": ["Command"]
}
```

### `refresh_traversal`

Traverses the accessibility tree without performing any action. Useful for getting the current UI state.

**Parameters:**

- `pid` (required): Process ID of the application to traverse
- `onlyVisibleElements` (optional): Filter to visible elements only

**Example:**

```json
{
  "pid": 12345
}
```

## Development

1. Build:

   ```bash
   swift build -c release
   cp .build/release/libosaurus-macos-use.dylib ./libosaurus-macos-use.dylib
   ```

2. Install locally:
   ```bash
   osaurus tools install .
   ```

## Publishing

### Code Signing (Required for Distribution)

```bash
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  .build/release/libosaurus-macos-use.dylib
```

### Package and Distribute

```bash
osaurus tools package osaurus.macos-use 0.1.0
```

This creates `osaurus.macos-use-0.1.0.zip` for distribution.

## Typical Workflow

1. **Open an application** to get its PID and initial UI state:

   ```json
   { "identifier": "Notes" }
   ```

2. **Use the PID** from the response for subsequent actions:

   ```json
   { "pid": 12345, "x": 150, "y": 300 }
   ```

3. **Refresh the traversal** to see current UI state:
   ```json
   { "pid": 12345, "onlyVisibleElements": true }
   ```

## Response Format

All tools return an `ActionResult` JSON object containing:

- `openResult`: Application info (when using `open_application_and_traverse`)
- `traversalPid`: The PID used for traversal
- `traversalAfter`: The accessibility tree data with elements, coordinates, and attributes
- `primaryActionError`: Any error from the action
- `traversalAfterError`: Any error from the traversal

## Credits

- [MacosUseSDK](https://github.com/mediar-ai/MacosUseSDK) by mediar-ai
- [mcp-server-macos-use](https://github.com/mediar-ai/mcp-server-macos-use) by mediar-ai
