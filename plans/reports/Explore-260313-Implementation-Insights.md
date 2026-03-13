# Implementation Insights: Adding Iframe Support to TMail Composer

**Context:** Following exploration of email composer and attachment flow

---

## Quick Reference: Critical Classes & Methods

### Attachment Upload Entry Points

**Method:** `ComposerController.openFilePickerByType()`
```
Path: lib/features/composer/presentation/composer_controller.dart:1160
Triggers file picker for user to select files
Then calls: _handlePickFileSuccess() → uploadAttachmentsAction()
Result: Files queued for upload to server
```

**Method:** `ComposerController.uploadAttachmentsAction()`
```
Path: lib/features/composer/presentation/composer_controller.dart:1197
Validates files against size limits
Creates upload URI from JMAP session
Calls: UploadController.justUploadAttachmentsAction()
Result: Files sent to server with progress tracking
```

**Method:** `ComposerController.deleteAttachmentUploaded()`
```
Path: lib/features/composer/presentation/composer_controller.dart:1216
Simple delegation to UploadController.deleteFileUploaded()
Result: Attachment removed from list
```

### Observable State for UI Binding

**UploadController reactive properties:**
```dart
final listUploadAttachments = <UploadFileState>[].obs;  // Observable list
final uploadInlineViewState = Rx<Either<Failure, Success>>(Right(UIState.idle));
```

Wrapped in `Obx()` widgets to auto-refresh UI when files change.

---

## postMessage Message Format

### From Iframe to Parent (existing pattern)

All messages follow this structure:
```json
{
  "view": "unique-view-id",
  "type": "toDart: <event-name>",
  "...": "event-specific data"
}
```

**Examples from codebase:**

Scroll event:
```json
{ "view": "view123", "type": "toDart: onScrollChanged", "deltaY": 42 }
```

Touch event:
```json
{ "view": "view123", "type": "toDart: onScrollEnd", "velocity": 1.5 }
```

Keyboard event:
```json
{ "view": "view123", "type": "toDart: iframeKeydown", "key": "Enter", "code": "Enter", "shift": false }
```

Selection change (custom):
```json
{ "view": "view123", "name": "onSelectionChange", "hasSelection": true, "x": 100, "y": 200 }
```

### From Parent to Iframe

Execute JavaScript directly:
```dart
editorController.evaluateJavascriptWeb('someJsCode()');
```

---

## Where to Hook iframe Support

### 1. Define iframe Scripts (like HtmlUtils does)

**File:** `core/lib/utils/html/html_interaction.dart`

Add new methods for iframe attachment handling:
```dart
static String scriptHandleIframeFileAttach(String viewId) => '''
  <script type="text/javascript">
    document.addEventListener('drop', function (e) {
      e.preventDefault();
      e.stopPropagation();
      const files = e.dataTransfer.files;
      const payload = {
        view: '$viewId',
        type: 'toDart: iframeFileDrop',
        fileCount: files.length,
        // Note: Can't send actual file data via postMessage
        // Parent must handle drop event directly
      };
      window.parent.postMessage(JSON.stringify(payload), "*");
    });
  </script>
''';
```

### 2. Register Message Listener

**File:** Add new widget or extend WebEditorWidget

```dart
void initState() {
  // ... existing code ...
  
  _iframeListener = (event) {
    if (event is MessageEvent) {
      final data = jsonDecode(event.data);
      
      if (data['type'] == 'toDart: iframeFileDrop') {
        // Forward to controller
        widget.onIframeFileDrop?.call(data);
      }
    }
  };
  
  window.addEventListener("message", _iframeListener!);
}

void dispose() {
  window.removeEventListener("message", _iframeListener!);
  super.dispose();
}
```

### 3. Wire to Controller

**File:** Extend `ComposerController`

```dart
void handleIframeFileDrop(Map<String, dynamic> dropData) {
  // Note: postMessage cannot transfer File objects
  // Instead, use drop event on Flutter side with desktop_drop package
  // Or use input[type=file] inside iframe
}
```

---

## File Attachment Data Flow Architecture

```
┌─────────────────────────────────────────┐
│  Web Browser / Flutter Web              │
└────────────────┬────────────────────────┘
                 │
         ┌───────┴────────┐
         │                │
    ┌────▼────┐      ┌────▼──────────┐
    │ Flutter │      │ Iframe (HTML) │
    │ Widget  │      │   Content    │
    │  View   │      │   (Optional) │
    └────┬────┘      └────┬──────────┘
         │                │
    ┌────▼────────────────▼────────┐
    │   postMessage Bridge Layer    │
    │ (window.addEventListener)    │
    └────┬───────────────────────┬──┘
         │                       │
    ┌────▼──────────────┐    ┌──▼─────────────┐
    │ ComposerController│    │ UploadController│
    │ (attachment mgmt) │    │ (file upload)   │
    └────┬──────────────┘    └──┬──────────────┘
         │                       │
    ┌────▼───────────────────────▼────┐
    │  File Picker / File Upload API   │
    │  (LocalFilePickerInteractor)     │
    └────┬──────────────────────────┬──┘
         │                          │
    ┌────▼────────────┐  ┌─────────▼──┐
    │ Device Storage  │  │ JMAP Server│
    │ (local files)   │  │ (upload)   │
    └─────────────────┘  └────────────┘
```

---

## Attachment State Transitions

```
UploadFileState state machine:

[ Initial ]
    │
    ├─→ uploading (progress 0-99%)
    │       │
    │       ├─→ [succeed] → 100% → [display in list]
    │       │
    │       └─→ [uploadFailed] → [show error toast, remove from list]
    │
    └─→ [deleted] → [remove from list]
```

**State tracking:**
- `UploadFileStatus.uploading` - file being sent
- `UploadFileStatus.succeed` - upload complete
- `UploadFileStatus.uploadFailed` - failed
- Progress: `percentUploading` (0-100)

---

## Key Integration Points with Existing Code

### 1. Reactive List Updates
```dart
// ComposerController uses this observable
final uploadController = UploadController(...);

// Wrapped in UI like this
final attachmentWidget = Obx(() {
  if (controller.uploadController.listUploadAttachments.isNotEmpty) {
    return AttachmentComposerWidget(
      listFileUploaded: controller.uploadController.listUploadAttachments,
      // ...
    );
  }
  return const SizedBox.shrink();
});
```

If iframe adds files, just update `listUploadAttachments` and UI auto-updates.

### 2. Upload URI Generation
```dart
// Must happen BEFORE upload attempt
final uploadUri = session.getUploadUri(
  accountId,
  jmapUrl: dynamicUrlInterceptors.jmapUrl
);
```

This comes from JMAP session, so iframe must trigger upload flow AFTER auth.

### 3. File Size Validation
```dart
uploadController.validateTotalSizeAttachmentsBeforeUpload(
  totalSizePreparedFiles: success.pickedFiles.totalSize,
  onValidationSuccess: () => uploadAttachmentsAction(pickedFiles: success.pickedFiles)
);
```

Max attachment size is: `mailboxDashBoardController.maxSizeAttachmentsPerEmail?.value`

---

## Existing Error Handling Patterns

### File Pick Failures
```dart
void _handlePickFileFailure(LocalFilePickerFailure failure) {
  if (currentOverlayContext != null && currentContext != null 
      && failure.exception is! PickFileCanceledException) {
    appToast.showToastErrorMessage(
      currentOverlayContext!,
      AppLocalizations.of(currentContext!).thisFileCannotBePicked
    );
  }
}
```

Pattern: Show toast + check if user cancelled (don't show error toast).

### Upload Failures
```dart
void _handleProgressUploadStateStream(Either<Failure, Success> uploadState) {
  uploadState.fold(
    (failure) {
      if (failure is ErrorAttachmentUploadState) {
        _uploadingStateFiles.updateElementByUploadTaskId(
          failure.uploadId,
          (currentState) => currentState?.copyWith(
            uploadStatus: UploadFileStatus.uploadFailed
          )
        );
        deleteFileUploaded(failure.uploadId);
        _showToastMessageWhenUploadAttachmentsFailure(failure);
      }
    },
    // ... success case ...
  );
}
```

Pattern: Update state → show toast → delete from list.

---

## Testing Considerations

### Mock Points
1. **File Picker** - MockLocalFilePickerInteractor
2. **Upload API** - Mock JMAP session
3. **postMessage** - Mock window.addEventListener in tests

### Observable Testing
```dart
// Files are observable - test can verify:
expect(uploadController.listUploadAttachments.length, 0);
// Add files
uploadAttachmentsAction(pickedFiles: [...]);
// Verify update
expect(uploadController.listUploadAttachments.length, 1);
```

---

## Performance Notes

1. **Upload is async** - doesn't block UI
2. **Progress tracked via streams** - reactive UI updates only when state changes
3. **File size validated before upload** - prevents unnecessary network requests
4. **postMessage is async** - iframe can continue rendering while uploading

---

## Platform Considerations

### Web Only
- postMessage communication
- iframe elements (HtmlElementView not available on mobile)
- Window object access

### Mobile
- File picker via `file_picker` package
- No iframe support in current implementation
- Desktop drop for drag-and-drop

**Code handles this via:**
```dart
if (!kIsWeb) {
  // Mobile-specific logic
}
```

---

## Summary: What Exists vs. What's Needed

| Feature | Exists | Location |
|---------|--------|----------|
| File picker | ✓ | LocalFilePickerInteractor |
| File upload | ✓ | UploadController |
| Progress tracking | ✓ | UploadFileState |
| UI attachment list | ✓ | AttachmentComposerWidget |
| postMessage infrastructure | ✓ | HtmlUtils, HtmlInteraction |
| **Iframe widget** | ✗ | Would use HtmlElementView |
| **Iframe → Flutter bridge** | Partial | Pattern exists, not iframe-specific |
| **Iframe file drop handling** | ✗ | Needs implementation |

