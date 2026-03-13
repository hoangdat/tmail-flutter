import 'package:flutter/material.dart';
import 'package:tmail_ui_user/features/composer/domain/model/drive_file_metadata.dart';
import 'package:tmail_ui_user/features/composer/presentation/drive/drive_post_message_handler.dart';
import 'package:universal_html/html.dart' as html;

class DrivePickerIframeWidget extends StatefulWidget {
  final String drivePickerUrl;
  final String driveOrigin;
  final void Function(DriveFileMetadata) onFileSelected;
  final VoidCallback onCancelled;

  const DrivePickerIframeWidget({
    super.key,
    required this.drivePickerUrl,
    required this.driveOrigin,
    required this.onFileSelected,
    required this.onCancelled,
  });

  @override
  State<DrivePickerIframeWidget> createState() =>
      _DrivePickerIframeWidgetState();
}

class _DrivePickerIframeWidgetState extends State<DrivePickerIframeWidget> {
  late DrivePostMessageHandler _handler;

  @override
  void initState() {
    super.initState();
    _handler = DrivePostMessageHandler(
      driveOrigin: widget.driveOrigin,
      onFileSelected: widget.onFileSelected,
      onCancelled: widget.onCancelled,
    );
    _handler.startListening();
  }

  @override
  void dispose() {
    _handler.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView.fromTagName(
      tagName: 'iframe',
      onElementCreated: (element) {
        final iframe = element as html.IFrameElement
          ..src = widget.drivePickerUrl
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%';

        iframe.onLoad.listen((_) {
          _handler.sendInitMessage(iframe);
        });
      },
    );
  }
}
