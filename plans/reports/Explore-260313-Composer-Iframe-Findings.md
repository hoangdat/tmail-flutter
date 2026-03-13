# Exploration Report: TMail Flutter Email Composer & Iframe Integration

**Date:** 2026-03-13 | **Codebase:** tmail-flutter

## Executive Summary

The TMail Flutter codebase is a JMAP-based email client with a **well-established email composer** using the `html_editor_enhanced` library. The codebase already implements **postMessage-based iframe communication** patterns for scroll/event handling. There are **no existing HtmlElementView usage patterns**, but the architecture supports **web-based iframe integration**.

---

## 1. Email Composer Architecture

### Main Components

| Component | Path | Purpose |
|-----------|------|---------|
| **Composer Controller** | `lib/features/composer/presentation/composer_controller.dart` | Main state management for composer (attachments, recipients, email content) |
| **Composer View (Web)** | `lib/features/composer/presentation/composer_view_web.dart` | Main UI layout for web platform |
| **Web Editor View** | `lib/features/composer/presentation/view/web/web_editor_view.dart` | HTML editor wrapper/state management |
| **Web Editor Widget** | `lib/features/composer/presentation/widgets/web/web_editor_widget.dart` | Actual HtmlEditor component w/ postMessage listeners |
| **Attachment Widget** | `lib/features/composer/presentation/widgets/web/attachment_composer_widget.dart` | List of uploaded attachments |
| **Bottom Bar** | `lib/features/composer/presentation/widgets/web/bottom_bar_composer_widget.dart` | Attach, Insert Image, Send buttons |

### Key Classes

**ComposerController:**
- Location: `/Users/datph/FlutterProject/tmail-flutter/lib/features/composer/presentation/composer_controller.dart`
- Key methods:
  - `openFilePickerByType()` (line 1160) - Triggers file picker dialog
  - `uploadAttachmentsAction()` (line 1197) - Sends files to server
  - `deleteAttachmentUploaded()` (line 1216) - Removes attachment
  - `insertImage()` (line 1674) - Opens image picker for inline images
  - `_handleUploadInlineSuccess()` (line 1686) - Handles inline image upload completion

**WebEditorWidget:**
- Location: `/Users/datph/FlutterProject/tmail-flutter/lib/features/composer/presentation/widgets/web/web_editor_widget.dart`
- Implements `MessageEvent` listener on lines 115-132
- Uses `window.addEventListener("message", _editorListener!)` to receive postMessage events
- Parses JSON from event data to handle editor interactions
- Uses `universal_html/html.dart` for DOM access (line 12)

---

## 2. Attachment/File Upload Flow

### Current Implementation

```
User clicks "Attach File" button
    ↓
openFilePickerByType(FileType.any)
    ↓
LocalFilePickerInteractor.execute()
    ↓
User selects file(s) from device
    ↓
_handlePickFileSuccess() validates file size
    ↓
uploadAttachmentsAction() creates upload URI from JMAP session
    ↓
UploadController.justUploadAttachmentsAction()
    ↓
File uploaded to server via multipart request
    ↓
UploadFileState tracks progress/status
    ↓
AttachmentComposerWidget renders list of uploaded files
```

### Upload Controller
- Location: `/Users/datph/FlutterProject/tmail-flutter/lib/features/upload/presentation/controller/upload_controller.dart`
- Manages `listUploadAttachments` observable list
- Tracks upload progress with `UploadingAttachmentUploadState`
- Emits `SuccessAttachmentUploadState` on completion (line 111)
- File deletion: `deleteFileUploaded()` method

### Key Data Models
- **UploadFileState:** `/lib/features/upload/presentation/model/upload_file_state.dart`
- **FileInfo:** `model/lib/upload/file_info.dart`
- **Attachment:** `model/lib/email/attachment.dart`

---

## 3. Existing postMessage/JS Interop Patterns

### Pattern #1: HtmlUtils Script Registry
**Location:** `/Users/datph/FlutterProject/tmail-flutter/core/lib/utils/html/html_utils.dart`

The codebase defines reusable JavaScript snippets with postMessage communication:

```dart
static const registerDropListener = (
  script: '''
    document.querySelector(".note-editable").addEventListener(
      "drop",
      (event) => window.parent.postMessage(
        JSON.stringify({"name": "registerDropListener"})))''',
  name: 'registerDropListener');

static ({String name, String script}) registerSelectionChangeListener(
  String viewId,
) => (
  script: '''
    const sendSelectionChangeMessage = (data) => {
      // When iframe
      if (window.parent) {
        window.parent.postMessage(JSON.stringify({
          ...data,
          viewId: '$viewId',
          name: 'onSelectionChange',
        }), '*');
      }
      // When WebView
      if (window.flutter_inappwebview) {
        window.flutter_inappwebview.callHandler('onSelectionChange', data);
      }
    };
    // ... script continues ...
  ''',
  name: 'registerSelectionChangeListener'
);
```

### Pattern #2: Event Listener Registration
**Location:** `/Users/datph/FlutterProject/tmail-flutter/lib/features/composer/presentation/widgets/web/web_editor_widget.dart` (lines 113-132)

```dart
_editorListener = (event) {
  try {
    if (event is MessageEvent) {
      final data = jsonDecode(event.data);
      
      if (data['name'] == HtmlUtils.registerDropListener.name) {
        _editorController.evaluateJavascriptWeb(HtmlUtils.removeLineHeight1px.name);
      } else if (data['name'] == _selectionChangeScript.name
          && data['viewId'] == _createdViewId) {
        handleSelectionChange(data);
      }
    }
  } catch (e) {
    logWarning('_WebEditorState::_editorListener: Unable to parse message data = $e');
  }
};

window.addEventListener("message", _editorListener!);
```

### Pattern #3: HtmlInteraction Library
**Location:** `/Users/datph/FlutterProject/tmail-flutter/core/lib/utils/html/html_interaction.dart`

Defines additional iframe communication scripts:
- **Scroll events:** `scriptsWheelEventListener()` - sends `deltaY` via postMessage
- **Touch events:** `scriptsTouchEventListener()` - sends touch data via postMessage
- **Keyboard events:** `scriptHandleIframeKeyboardListener()` - sends key/code/shift via postMessage
- **Click events:** `scriptsHandleIframeClickListener()` - notifies parent on iframe click
- **Link hover:** `scriptsHandleLinkHoverListener()` - sends link rect data on hover

All use pattern: `window.parent.postMessage(JSON.stringify({ view: viewId, type: "toDart: ...", ...data }), "*")`

### Pattern #4: Universal HTML Import
**Location:** `/Users/datph/FlutterProject/tmail-flutter/lib/main/universal_import/html_web.dart`

```dart
export 'package:universal_html/html.dart';
```

This allows cross-platform DOM access:
- On Web: uses `dart:html`
- On Mobile: uses `universal_html` stub

---

## 4. No Existing HtmlElementView Usage

**Finding:** Search for `HtmlElementView` and `IframeElement` returns **5 files** but none actually use iframe elements:
- Files mentioning "iframe" in context of script injections only
- No Flutter widget instantiation of HtmlElementView
- No custom iframe composition

This means:
- **Opportunity:** Adding iframe support would be a new pattern
- **Advantage:** Can be designed cleanly without legacy constraints
- **Integration point:** Use existing postMessage infrastructure as reference

---

## 5. Attachment UI Components

### AttachmentComposerWidget
**Location:** `/Users/datph/FlutterProject/tmail-flutter/lib/features/composer/presentation/widgets/web/attachment_composer_widget.dart`

```dart
class AttachmentComposerWidget extends StatefulWidget {
  final List<UploadFileState> listFileUploaded;
  final bool isCollapsed;
  final OnDeleteAttachmentAction onDeleteAttachmentAction;
  final OnToggleExpandAttachmentAction onToggleExpandAttachmentAction;
  final OnPreviewAttachmentAction onPreviewAttachmentAction;
  // ...
}
```

- Renders files in a `Wrap` widget (responsive grid)
- Shows upload progress bar with percent
- Supports preview and delete actions
- Integrated into `ComposerView` via `Obx()` reactive wrapper

### File Attachment Buttons

**Bottom Bar Attach Button** (line 91-99):
```dart
TMailButtonWidget.fromIcon(
  icon: imagePaths.icAttachFile,
  onTapActionCallback: attachFileAction,  // → controller.openFilePickerByType()
)
```

**Bottom Bar Insert Image Button** (line 101-109):
```dart
TMailButtonWidget.fromIcon(
  icon: imagePaths.icInsertImage,
  onTapActionCallback: insertImageAction,  // → controller.insertImage()
)
```

---

## 6. HTML Editor Integration

### Library: html_editor_enhanced
Used via `HtmlEditorController` to:
- Manage rich text editing
- Execute custom JavaScript
- Handle drag-drop events
- Manage formatting options

### Key Methods
- `editorController.evaluateJavascriptWeb()` - Execute JS in editor iframe
- `editorController.getText()` - Get HTML content
- `editorController.setFocus()` - Focus editor

### Editor Options (WebEditorWidget lines 161-199)
- `disableDragAndDrop: true` (intentional - custom handling)
- `normalizeHtmlTextWhenDropping: true`
- Custom CSS styling via `customBodyCssStyle`
- Custom internal CSS via `customInternalCSS`
- Spell check enabled
- Link tooltips enabled

---

## 7. Web/Platform Detection

**Location:** `/Users/datph/FlutterProject/tmail-flutter/lib/features/composer/presentation/composer_controller.dart` (line 1161)

```dart
void openFilePickerByType(BuildContext context, FileType fileType) async {
  if (!kIsWeb) {
    popBack();  // Mobile-specific behavior
  }
  consumeState(_localFilePickerInteractor.execute(fileType: fileType));
}
```

The codebase uses `kIsWeb` to branch logic for web vs. mobile platforms.

---

## 8. Key File Paths Summary

| Category | File Path |
|----------|-----------|
| Composer Main | `/lib/features/composer/presentation/composer_controller.dart` |
| Web Composer View | `/lib/features/composer/presentation/composer_view_web.dart` |
| HTML Editor | `/lib/features/composer/presentation/widgets/web/web_editor_widget.dart` |
| Attachments | `/lib/features/composer/presentation/widgets/web/attachment_composer_widget.dart` |
| Upload Controller | `/lib/features/upload/presentation/controller/upload_controller.dart` |
| HTML Scripts | `/core/lib/utils/html/html_utils.dart` |
| HTML Interaction | `/core/lib/utils/html/html_interaction.dart` |
| Universal HTML | `/lib/main/universal_import/html_web.dart` |

---

## 9. Architecture Observations

### Strengths
1. **Clean separation:** UI (views/widgets) → Logic (controller) → Data (upload controller)
2. **Reactive:** Uses GetX observables for state management
3. **Extensible:** Well-documented postMessage patterns already in place
4. **Cross-platform:** Universal HTML abstraction layer
5. **Modular attachments:** Separate UploadController handles all file logic

### Integration Points for iframe
1. **Message listener:** Reuse pattern from `WebEditorWidget._editorListener`
2. **Scripts:** Add iframe-specific scripts to `HtmlInteraction` class
3. **Upload flow:** No changes needed - file upload already works via UploadController
4. **State management:** Attach iframe state to ComposerController

---

## Key Takeaways

1. **Composer exists and is fully functional** with file attachment support
2. **postMessage communication is established** - used for editor scroll, touch, keyboard events
3. **No iframe widgets currently** - provides clean slate for new implementation
4. **Upload infrastructure is solid** - file picker, progress tracking, server upload all present
5. **HtmlUtils/HtmlInteraction** provide reusable patterns for JavaScript injection
6. **Universal HTML abstraction** allows cross-platform DOM access

