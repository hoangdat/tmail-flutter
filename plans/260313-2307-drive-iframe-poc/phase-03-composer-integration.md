# Phase 3 — Composer Integration

## Overview
- **Priority**: High
- **Status**: TODO
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

### Modify
- `lib/features/composer/presentation/widgets/web/bottom_bar_composer_widget.dart` — add button + callback
- `lib/features/composer/presentation/composer_controller.dart` — add `openDrivePicker()` method
- `lib/features/composer/presentation/composer_view_web.dart` — pass new callback to bottom bar

### Create
- None (widget created in Phase 2)

### Reference
- `core/presentation/resources/image_paths.dart` — for icon (reuse existing or use placeholder)

## Implementation Steps

1. **Add callback to `BottomBarComposerWidget`**
   - Add `VoidCallback attachFromDriveAction` parameter
   - Add new `TMailButtonWidget.fromIcon` button after the attach file button (line ~100)
   - Use existing icon (e.g., `icAttachFile` with different tooltip) or a placeholder icon
   - Tooltip: "Attach from Drive"

2. **Add `openDrivePicker()` to `ComposerController`**
   ```dart
   void openDrivePicker(BuildContext context) {
     // Only on web
     if (!PlatformInfo.isWeb) return;

     showDialog(
       context: context,
       builder: (_) => Dialog(
         child: SizedBox(
           width: 600,
           height: 500,
           child: DrivePickerIframeWidget(
             drivePickerUrl: 'http://localhost:8081',
             driveOrigin: 'http://localhost:8081',
             onFileSelected: (metadata) {
               Navigator.of(context).pop();
               // POC: log or show toast with metadata
               log('Drive file selected: ${metadata.name}, ${metadata.size}, ${metadata.contentType}');
               // Future: convert to attachment and upload
             },
             onCancelled: () {
               Navigator.of(context).pop();
             },
           ),
         ),
       ),
     );
   }
   ```

3. **Wire in composer view**
   - In `composer_view_web.dart`, find where `BottomBarComposerWidget` is constructed
   - Pass `attachFromDriveAction: () => controller.openDrivePicker(context)`

4. **Guard for web-only**
   - Button only visible when `PlatformInfo.isWeb` is true
   - Use conditional rendering in bottom bar

## Security
- Drive picker URL should come from config, not user input
- Dialog constrains iframe size (no fullscreen takeover)

## Success Criteria
- [ ] "Attach from Drive" button visible in composer bottom bar (web only)
- [ ] Clicking button opens dialog with iframe
- [ ] Selecting a file in Drive picker closes dialog and logs metadata
- [ ] Cancelling in Drive picker closes dialog
- [ ] Existing composer functionality unaffected

## Todo
- [ ] Add attachFromDriveAction callback to BottomBarComposerWidget
- [ ] Add button in bottom bar row
- [ ] Add openDrivePicker method to ComposerController
- [ ] Wire callback in composer_view_web.dart
- [ ] End-to-end test: button → dialog → select file → metadata logged
