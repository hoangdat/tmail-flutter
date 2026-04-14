import 'package:get/get.dart';
import 'package:tmail_ui_user/features/base/event_bus/get_all_email_bus_handler.dart';
import 'package:tmail_ui_user/features/base/event_bus/mark_as_read_bus_handler.dart';

/// Central registry of all [GetxService] bus handlers.
///
/// Add one entry per handler here — bindings loop over this list automatically.
/// Forgetting to register a handler = it never appears here = obvious gap in code review.
final List<GetxService Function()> busHandlerFactories = [
  () => MarkAsReadBusHandler(),
  () => GetAllEmailBusHandler(),
];
