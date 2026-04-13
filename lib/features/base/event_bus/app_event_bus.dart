import 'dart:async';

import 'package:core/utils/app_logger.dart';
import 'package:get/get.dart';

/// A lightweight broadcast event bus registered as a GetxService.
/// Use [fire] to publish events, [on<T>] to subscribe to typed events.
class AppEventBus extends GetxService {
  final _controller = StreamController<Object>.broadcast();

  /// Returns a stream of events of type [T].
  Stream<T> on<T>() => _controller.stream.where((e) => e is T).cast<T>();

  /// Publishes [event] to all current subscribers.
  void fire(Object event) {
    logDebug('AppEventBus::fire: ${event.runtimeType}', webConsoleEnabled: true);
    _controller.add(event);
  }

  @override
  void onClose() {
    _controller.close();
    super.onClose();
  }
}
