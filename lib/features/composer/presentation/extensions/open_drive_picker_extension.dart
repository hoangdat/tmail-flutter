import 'package:core/utils/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tmail_ui_user/features/composer/domain/model/drive_file_metadata.dart';
import 'package:tmail_ui_user/features/composer/presentation/composer_controller.dart';
import 'package:tmail_ui_user/features/composer/presentation/widgets/web/drive_picker_iframe_widget.dart';

extension OpenDrivePickerExtension on ComposerController {
  void openDrivePicker(BuildContext context) {
    if (!kIsWeb) return;

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          width: 600,
          height: 500,
          child: DrivePickerIframeWidget(
            drivePickerUrl: 'http://localhost:8081',
            driveOrigin: 'http://localhost:8081',
            onFileSelected: (metadata) {
              Navigator.of(dialogContext).pop();
              log('ComposerController::openDrivePicker: file selected: $metadata');
              _insertDriveFileCard(metadata);
            },
            onCancelled: () {
              Navigator.of(dialogContext).pop();
            },
          ),
        ),
      ),
    );
  }

  /// Insert a styled card into the email body showing the Drive file info.
  void _insertDriveFileCard(DriveFileMetadata metadata) {
    final sizeStr = _formatFileSize(metadata.size);
    final html = '''
<div style="display:inline-block;border:1px solid #dadce0;border-radius:8px;padding:12px 16px;margin:8px 0;font-family:sans-serif;max-width:400px;">
  <div style="font-size:14px;font-weight:500;color:#1a73e8;">
    <a href="${metadata.contentUrl}" target="_blank" style="color:#1a73e8;text-decoration:none;">${_escapeHtml(metadata.name)}</a>
  </div>
  <div style="font-size:12px;color:#5f6368;margin-top:4px;">
    ${_escapeHtml(metadata.contentType)} &middot; $sizeStr
  </div>
</div><br>
''';
    richTextWebController?.editorController.insertHtml(html);
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }
}
