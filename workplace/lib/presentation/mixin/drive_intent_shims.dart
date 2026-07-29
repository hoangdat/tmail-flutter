abstract final class DriveIntentShims {
  static const String handlerName = 'driveIntentMessage';

  // The shim forwards `targetOrigin` as the second arg only to keep the handler
  // signature shared with web; mobile ignores it. Mobile WebViews have no
  // browser-stamped origin, and targetOrigin is the destination the page chose,
  // not the sender — so it can't be validated. See [validatesMessageOrigin] in
  // DriveIntentMessageHandlerMixin. Mitigation: we only open URLs from our API.
  static String get parentPostMessageShim => '''
    window.parent = {
      postMessage: function(data, targetOrigin) {
        window.flutter_inappwebview.callHandler(
          '$handlerName',
          typeof data === 'string' ? data : JSON.stringify(data),
          targetOrigin
        );
      }
    };
    ''';
}
