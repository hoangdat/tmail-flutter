import 'dart:async';

import 'package:get/get.dart';
import 'package:tmail_ui_user/features/base/event_bus/app_event_bus.dart';
import 'package:tmail_ui_user/features/base/state/email_list_state_provider.dart';
import 'package:tmail_ui_user/features/email/domain/state/mark_as_email_read_state.dart';
import 'package:tmail_ui_user/features/thread/domain/state/mark_as_multiple_email_read_state.dart';

/// Subscribes to mark-as-read events on the bus and updates EmailListStateProvider.
class MarkAsReadBusHandler extends GetxService {
  StreamSubscription? _readSub;
  StreamSubscription? _readMultipleSub;

  @override
  void onInit() {
    super.onInit();
    final eventBus = Get.find<AppEventBus>();
    final provider = Get.find<EmailListStateProvider>();

    _readSub = eventBus.on<MarkAsEmailReadSuccess>().listen((s) {
      provider.updateEmailFlagByEmailIds([s.emailId], readAction: s.readActions);
    });
    _readMultipleSub = eventBus.on<MarkAsMultipleEmailReadAllSuccess>().listen((s) {
      provider.updateEmailFlagByEmailIds(s.emailIds, readAction: s.readActions);
    });
  }

  @override
  void onClose() {
    _readSub?.cancel();
    _readMultipleSub?.cancel();
    super.onClose();
  }
}
