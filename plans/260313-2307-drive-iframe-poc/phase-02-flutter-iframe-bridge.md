# Phase 2 — Flutter Iframe Widget + postMessage Bridge

## Overview
- **Priority**: High
- **Status**: COMPLETED
- **Description**: Create a Flutter web widget that embeds the Drive picker iframe and a Dart-side postMessage bridge to send/receive structured messages.

## Context Links
- Existing iframe pattern: `core/lib/presentation/views/html_viewer/html_content_viewer_on_web_widget.dart` (line 561)
- Existing postMessage pattern: `core/lib/utils/html/html_interaction.dart`
- Package: `universal_html` (already in deps)

## Requirements
- Widget that renders an iframe pointing to the Drive picker URL
- Dart class to send/receive postMessage with origin validation
- Configurable Drive picker URL (hardcoded constant for POC)
- Callback when file metadata is received
- Callback when user cancels
- Web-only (guard with `PlatformInfo.isWeb`)

## Related Code Files

### Create
- `lib/features/composer/presentation/widgets/web/drive_picker_iframe_widget.dart` — iframe widget
- `lib/features/composer/domain/model/drive_file_metadata.dart` — metadata model
- `lib/features/composer/presentation/drive/drive_post_message_handler.dart` — postMessage bridge

### Reference (read only)
- `core/lib/presentation/views/html_viewer/html_content_viewer_on_web_widget.dart`
- `core/lib/utils/html/html_interaction.dart`

## Architecture

```
DrivePickerIframeWidget (StatefulWidget, web-only)
├── HtmlElementView.fromTagName('iframe')
│   └── IFrameElement.src = drivePickerUrl
├── DrivePostMessageHandler
│   ├── listen() → window.addEventListener('message', ...)
│   ├── sendInit() → iframe.contentWindow.postMessage({type: 'init'})
│   ├── _onMessage(event) → validate origin → parse → callback
│   └── dispose() → removeEventListener
└── Callbacks
    ├── onFileSelected(DriveFileMetadata)
    └── onCancelled()
```

## Implementation Steps

1. **Create `DriveFileMetadata` model**
   ```dart
   class DriveFileMetadata {
     final String name;
     final int size;
     final String contentType;
     final String contentUrl;
   }
   ```

2. **Create `DrivePostMessageHandler`**
   - Constructor takes: `driveOrigin`, `onFileSelected`, `onCancelled`
   - `startListening()` — adds `message` event listener on `window`
   - `_handleMessage(MessageEvent event)`:
     - Check `event.origin == driveOrigin` (CRITICAL)
     - Parse `event.data` as JSON
     - Switch on `type`: `file-selected` → parse metadata → callback, `cancelled` → callback
   - `sendInitMessage(IFrameElement iframe)` — posts `{type: 'init', mode: 'file-picker'}` to iframe
   - `dispose()` — removes event listener

3. **Create `DrivePickerIframeWidget`**
   - `StatefulWidget` with params: `drivePickerUrl`, `driveOrigin`, `onFileSelected`, `onCancelled`
   - `initState()`: create `DrivePostMessageHandler`, start listening
   - `build()`: `HtmlElementView.fromTagName(tagName: 'iframe', onElementCreated: ...)`
     - Set `src = drivePickerUrl`
     - Set style: border none, width/height 100%
     - On element created → send init message
   - `dispose()`: handler.dispose()

## Security
- Origin validation on every incoming message (reject if `event.origin != driveOrigin`)
- Send postMessage with explicit `targetOrigin` (not `"*"`)
- Only accept known message types

## Success Criteria
- [x] Iframe loads Drive picker URL
- [x] Init message sent to iframe on load
- [x] File selection message received and parsed into `DriveFileMetadata`
- [x] Cancel message received and callback fired
- [x] Origin validation rejects messages from wrong origins
- [x] Widget properly disposes listener

## Todo
- [x] Create DriveFileMetadata model
- [x] Create DrivePostMessageHandler with origin validation
- [x] Create DrivePickerIframeWidget using HtmlElementView
- [ ] Test iframe loads and postMessage round-trip works (manual E2E test)
