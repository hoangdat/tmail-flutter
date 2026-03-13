import 'dart:convert';
import 'dart:js_interop';

import 'package:core/utils/app_logger.dart';
import 'package:tmail_ui_user/features/composer/domain/model/drive_file_metadata.dart';
import 'package:universal_html/html.dart' as html;

typedef OnDriveFileSelected = void Function(DriveFileMetadata metadata);
typedef OnDriveCancelled = void Function();

/// Handles postMessage communication between TMail and Drive picker iframe.
/// Messages are exchanged as JSON strings for reliable JS↔Dart interop.
class DrivePostMessageHandler {
  final String driveOrigin;
  final OnDriveFileSelected onFileSelected;
  final OnDriveCancelled onCancelled;

  void Function(html.Event)? _listener;

  DrivePostMessageHandler({
    required this.driveOrigin,
    required this.onFileSelected,
    required this.onCancelled,
  });

  void startListening() {
    _listener = (html.Event event) {
      if (event is html.MessageEvent) {
        _handleMessage(event);
      }
    };
    html.window.addEventListener('message', _listener!);
    log('DrivePostMessageHandler::startListening: driveOrigin=$driveOrigin');
  }

  /// Send init message as JSON string to iframe
  void sendInitMessage(html.IFrameElement iframe) {
    final message = jsonEncode({'type': 'init', 'mode': 'file-picker'});
    iframe.contentWindow?.postMessage(message, driveOrigin);
    log('DrivePostMessageHandler::sendInitMessage: sent to $driveOrigin');
  }

  void _handleMessage(html.MessageEvent event) {
    // Origin validation
    if (event.origin != driveOrigin) {
      return; // silently ignore non-drive messages (MetaMask, extensions, etc.)
    }

    try {
      final rawData = event.data;
      if (rawData == null) return;

      // The iframe sends JSON strings, but handle both cases
      String jsonString;
      if (rawData is String) {
        jsonString = rawData;
      } else {
        // Fallback: try JSON.stringify for JS objects
        final jsStr = _jsonStringify((rawData as JSAny));
        if (jsStr == null) return;
        jsonString = jsStr.toDart;
      }

      log('DrivePostMessageHandler::_handleMessage: data=$jsonString');

      final payload = jsonDecode(jsonString) as Map<String, dynamic>;
      final type = payload['type'] as String?;

      switch (type) {
        case 'file-selected':
          final metadata = payload['metadata'];
          if (metadata is Map<String, dynamic>) {
            final contentUrl = payload['contentUrl'] as String? ?? '';
            final enrichedMetadata = Map<String, dynamic>.from(metadata)
              ..['contentUrl'] = contentUrl;
            final driveFile = DriveFileMetadata.fromJson(enrichedMetadata);
            log('DrivePostMessageHandler: file selected: $driveFile');
            onFileSelected(driveFile);
          }
          break;
        case 'cancelled':
          log('DrivePostMessageHandler: cancelled');
          onCancelled();
          break;
        default:
          log('DrivePostMessageHandler: unknown type=$type');
      }
    } catch (e) {
      logError('DrivePostMessageHandler::_handleMessage: error=$e');
    }
  }

  void dispose() {
    if (_listener != null) {
      html.window.removeEventListener('message', _listener!);
      _listener = null;
    }
  }
}

@JS('JSON.stringify')
external JSString? _jsonStringify(JSAny? value);
