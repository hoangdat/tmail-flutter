import 'dart:async';

import 'package:get/get.dart';
import 'package:model/extensions/presentation_mailbox_extension.dart';
import 'package:tmail_ui_user/features/base/event_bus/app_event_bus.dart';
import 'package:tmail_ui_user/features/base/state/email_list_state_provider.dart';
import 'package:tmail_ui_user/features/base/state/mailbox_state_provider.dart';
import 'package:tmail_ui_user/features/thread/domain/state/get_all_email_state.dart';

/// Subscribes to GetAllEmailSuccess on the bus and updates EmailListStateProvider.
class GetAllEmailBusHandler extends GetxService {
  StreamSubscription? _successSub;

  @override
  void onInit() {
    super.onInit();
    final eventBus = Get.find<AppEventBus>();

    _successSub = eventBus.on<GetAllEmailSuccess>().listen(_onSuccess);
  }

  void _onSuccess(GetAllEmailSuccess success) {
    final selectedMailbox = Get.find<MailboxStateProvider>().selectedMailbox.value;
    final isVirtualFolder = selectedMailbox?.isVirtualFolder == true;
    if (success.currentMailboxId != null &&
        (isVirtualFolder || success.currentMailboxId != selectedMailbox?.id)) {
      return;
    }

    final provider = Get.find<EmailListStateProvider>();
    provider.emailsInCurrentMailbox.value = success.emailList;
    provider.currentEmailState = success.currentEmailState;
  }

  @override
  void onClose() {
    _successSub?.cancel();
    super.onClose();
  }
}
