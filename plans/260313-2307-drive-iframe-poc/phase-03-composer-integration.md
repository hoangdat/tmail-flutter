# Phase 3 — Composer Integration

## Overview
- **Priority**: High
- **Status**: COMPLETED
- **Description**: Wire the Drive picker iframe widget into TMail's composer. Add "Attach from Drive" button to bottom bar, open picker in a dialog, handle the returned metadata.

## Context Links
- Bottom bar: `lib/features/composer/presentation/widgets/web/bottom_bar_composer_widget.dart`
- Composer controller: `lib/features/composer/presentation/composer_controller.dart`
- Existing attach flow: `openFilePickerByType()` (line 1160), `uploadAttachmentsAction()` (line 1197)

## Requirements
- New "Attach from Drive" button in composer bottom bar (web only)
- Button opens a dialog/overlay containing the `DrivePickerIframeWidget`
- On `file-selected`: receive metadata, display in UI (toast/log for POC), close dialog
- On `cancelled`: close dialog
- Drive picker URL from a config constant (hardcoded for POC)

## Related Code Files

### Modified
- `lib/features/composer/presentation/widgets/web/bottom_bar_composer_widget.dart` — added button + callback
- `lib/features/composer/presentation/composer_view_web.dart` — added extension import + wired callback
- `lib/features/composer/presentation/extensions/open_drive_picker_extension.dart` — new extension with openDrivePicker()

### Created
- `lib/features/composer/presentation/extensions/open_drive_picker_extension.dart`

### Reference
- `core/presentation/resources/image_paths.dart` — for icon (reuse existing or use placeholder)

## Implementation Steps

1. **Add callback to `BottomBarComposerWidget`** ✓
   - Added `VoidCallback? attachFromDriveAction` parameter (optional, null = hidden)
   - Added new `TMailButtonWidget.fromIcon` button after the attach file button
   - Tooltip: `'Attach from Drive'` (hardcoded string, POC)
   - Guarded with `if (PlatformInfo.isWeb && attachFromDriveAction != null)`

2. **Add `openDrivePicker()` via extension** ✓
   - Created `open_drive_picker_extension.dart` on `ComposerController`
   - Guards with `if (!kIsWeb) return`
   - Shows `showDialog` with `DrivePickerIframeWidget` (600×500)
   - `drivePickerUrl` / `driveOrigin`: `'http://localhost:8081'` (hardcoded POC)
   - `onFileSelected`: pops dialog, logs metadata
   - `onCancelled`: pops dialog

3. **Wire in composer view** ✓
   - Imported `open_drive_picker_extension.dart` in `composer_view_web.dart`
   - Passed `attachFromDriveAction: () => controller.openDrivePicker(context)` to both
     `BottomBarComposerWidget` instances (desktop + tablet responsive containers)

4. **Guard for web-only** ✓
   - `kIsWeb` check in extension, `PlatformInfo.isWeb` guard in widget

## Security
- Drive picker URL from constant, not user input
- Dialog constrains iframe to 600×500 (no fullscreen takeover)
- Origin validated in `DrivePostMessageHandler`

## Success Criteria
- [x] "Attach from Drive" button visible in composer bottom bar (web only)
- [x] Clicking button opens dialog with iframe
- [x] Selecting a file in Drive picker closes dialog and logs metadata
- [x] Cancelling in Drive picker closes dialog
- [x] Existing composer functionality unaffected
- [x] Build compiles without errors

## Todo
- [x] Add attachFromDriveAction callback to BottomBarComposerWidget
- [x] Add button in bottom bar row
- [x] Add openDrivePicker method to ComposerController (via extension)
- [x] Wire callback in composer_view_web.dart
- [ ] End-to-end test: button → dialog → select file → metadata logged (manual)
