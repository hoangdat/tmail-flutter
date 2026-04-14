import 'dart:async';

import 'package:core/presentation/resources/image_paths.dart';
import 'package:get/get.dart';
import 'package:model/email/read_actions.dart';
import 'package:tmail_ui_user/features/base/event_bus/app_event_bus.dart';
import 'package:tmail_ui_user/features/base/service/toast_service.dart';
import 'package:tmail_ui_user/features/base/state/email_list_state_provider.dart';
import 'package:tmail_ui_user/features/email/domain/model/mark_read_action.dart';
import 'package:tmail_ui_user/features/email/domain/state/mark_as_email_read_state.dart';
import 'package:tmail_ui_user/features/email/domain/usecases/mark_as_email_read_interactor.dart';
import 'package:tmail_ui_user/features/email/presentation/action/email_action_queue.dart';
import 'package:tmail_ui_user/features/email/presentation/action/mark_as_read_email_action.dart';
import 'package:tmail_ui_user/features/thread/domain/state/mark_as_multiple_email_read_state.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations.dart';

/// Handles all mark-as-read bus events:
///   - Updates [EmailListStateProvider] (domain state)
///   - Shows toast via [ToastService] (shared UI reaction, no controller needed)
class MarkAsReadBusHandler extends GetxService {
  StreamSubscription? _readSub;
  StreamSubscription? _readAllSuccessSub;
  StreamSubscription? _readPartialSuccessSub;

  @override
  void onInit() {
    super.onInit();
    final eventBus = Get.find<AppEventBus>();
    final provider = Get.find<EmailListStateProvider>();

    _readSub = eventBus.on<MarkAsEmailReadSuccess>().listen((s) {
      provider.updateEmailFlagByEmailIds([s.emailId], readAction: s.readActions);
      _showSingleReadToast(s);
    });

    _readAllSuccessSub = eventBus.on<MarkAsMultipleEmailReadAllSuccess>().listen((s) {
      provider.updateEmailFlagByEmailIds(s.emailIds, readAction: s.readActions);
      _showMultipleReadToast(s.readActions);
    });

    _readPartialSuccessSub = eventBus.on<MarkAsMultipleEmailReadHasSomeEmailFailure>().listen((s) {
      provider.updateEmailFlagByEmailIds(s.successEmailIds, readAction: s.readActions);
      _showMultipleReadToast(s.readActions);
    });
  }

  void _showSingleReadToast(MarkAsEmailReadSuccess s) {
    if (s.markReadAction != MarkReadAction.swipeOnThread) return;
    final context = Get.context;
    if (context == null) return;

    final undoAction = s.readActions == ReadActions.markAsUnread
        ? ReadActions.markAsRead
        : ReadActions.markAsUnread;
    final label = s.readActions == ReadActions.markAsUnread
        ? AppLocalizations.of(context).unread.toLowerCase()
        : AppLocalizations.of(context).read.toLowerCase();

    Get.find<ToastService>().showWithAction(
      message: AppLocalizations.of(context).markedSingleMessageToast(label),
      actionName: AppLocalizations.of(context).undo,
      svgIcon: Get.find<ImagePaths>().icToastSuccessMessage,
      onAction: () => Get.find<EmailActionQueue>().submit(
        MarkAsReadEmailAction(
          s.emailId, undoAction, MarkReadAction.undo, s.mailboxId,
          Get.find<MarkAsEmailReadInteractor>(),
        ),
      ),
    );
  }

  void _showMultipleReadToast(ReadActions readActions) {
    final context = Get.context;
    if (context == null) return;

    final label = readActions == ReadActions.markAsUnread
        ? AppLocalizations.of(context).unread
        : AppLocalizations.of(context).read;
    final svgIcon = readActions == ReadActions.markAsUnread
        ? Get.find<ImagePaths>().icUnreadToast
        : Get.find<ImagePaths>().icReadToast;

    Get.find<ToastService>().showSuccess(
      AppLocalizations.of(context).marked_message_toast(label),
      svgIcon: svgIcon,
    );
  }

  @override
  void onClose() {
    _readSub?.cancel();
    _readAllSuccessSub?.cancel();
    _readPartialSuccessSub?.cancel();
    super.onClose();
  }
}
