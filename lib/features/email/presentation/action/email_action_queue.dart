import 'dart:async';

import 'package:core/presentation/state/failure.dart';
import 'package:core/presentation/state/success.dart';
import 'package:core/utils/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:tmail_ui_user/features/base/event_bus/app_event_bus.dart';
import 'package:tmail_ui_user/features/base/state/session_state_provider.dart';
import 'package:tmail_ui_user/features/email/presentation/action/cancellation_token.dart';
import 'package:tmail_ui_user/features/email/presentation/action/email_action.dart';

/// Single app-lifecycle service that executes any [EmailAction].
/// Always fires domain states on [AppEventBus].
/// Callbacks only fire if the [CancellationToken] is not cancelled.
class EmailActionQueue extends GetxService {
  final AppEventBus _eventBus;
  final SessionStateProvider _sessionProvider;
  final _activeSubs = <String, StreamSubscription>{};

  EmailActionQueue(this._eventBus, this._sessionProvider);

  void submit(
    EmailAction action, {
    CancellationToken? token, // ko cancel dc network, chi cancel callback
    ValueChanged<Success>? onSuccess,
    ValueChanged<Failure>? onFailure,
  }) {
    final session = _sessionProvider.session.value;
    final accountId = _sessionProvider.accountId.value;
    if (session == null || accountId == null) return; // not return

    log('EmailActionQueue::submit ${action.tag}');

    late StreamSubscription sub;
    sub = action.execute(session, accountId).listen(
      (result) => result.fold(
        (failure) {
          _eventBus.fire(failure);
          if (token?.isCancelled != true) onFailure?.call(failure);
        },
        (success) {
          _eventBus.fire(success);
          if (token?.isCancelled != true) onSuccess?.call(success);
        },
      ),
      onDone: () => _activeSubs.remove(action.tag),
    );
    _activeSubs[action.tag] = sub;
  }

  @override
  void onClose() {
    for (final s in _activeSubs.values) {
      s.cancel();
    }
    _activeSubs.clear();
    super.onClose();
  }
}
