import 'dart:async';

import 'package:get/get.dart';
import 'package:jmap_dart_client/jmap/core/state.dart' as jmap;
import 'package:jmap_dart_client/jmap/mail/email/email.dart';
import 'package:jmap_dart_client/jmap/mail/email/keyword_identifier.dart';
import 'package:model/email/mark_star_action.dart';
import 'package:model/email/presentation_email.dart';
import 'package:model/email/read_actions.dart';
import 'package:tmail_ui_user/features/base/event_bus/app_event_bus.dart';
import 'package:tmail_ui_user/features/email/domain/state/mark_as_email_read_state.dart';
import 'package:tmail_ui_user/features/thread/domain/state/mark_as_multiple_email_read_state.dart';

class EmailListStateProvider extends GetxService {
  final emailsInCurrentMailbox = <PresentationEmail>[].obs;
  final listResultSearch = <PresentationEmail>[].obs;
  final isInSearchMode = false.obs;
  jmap.State? currentEmailState;

  StreamSubscription? _readSuccessSub;
  StreamSubscription? _readMultipleSuccessSub;

  @override
  void onInit() {
    super.onInit();
    final eventBus = Get.find<AppEventBus>();
    _readSuccessSub = eventBus.on<MarkAsEmailReadSuccess>().listen((s) { // van bi phinh khi co nhieu feature
      updateEmailFlagByEmailIds([s.emailId], readAction: s.readActions);
    });
    _readMultipleSuccessSub = eventBus.on<MarkAsMultipleEmailReadAllSuccess>().listen((s) {
      updateEmailFlagByEmailIds(s.emailIds, readAction: s.readActions);
    });
  }

  @override
  void onClose() {
    _readSuccessSub?.cancel();
    _readMultipleSuccessSub?.cancel();
    super.onClose();
  }

  void updateEmailFlagByEmailIds(
    List<EmailId> emailIds, {
    ReadActions? readAction,
    MarkStarAction? markStarAction,
    bool markAsAnswered = false,
    bool markAsForwarded = false,
    bool isLabelAdded = false,
    KeyWordIdentifier? labelKeyword,
  }) {
    if (readAction == null &&
        markStarAction == null &&
        !markAsAnswered &&
        !markAsForwarded &&
        labelKeyword == null) {
      return;
    }

    final currentEmails = isInSearchMode.value
        ? listResultSearch
        : emailsInCurrentMailbox;

    if (currentEmails.isEmpty) return;

    for (var email in currentEmails) {
      if (!emailIds.contains(email.id)) continue;

      switch (readAction) {
        case ReadActions.markAsRead:
          _updateKeyword(email, KeyWordIdentifier.emailSeen, true);
          break;
        case ReadActions.markAsUnread:
          _updateKeyword(email, KeyWordIdentifier.emailSeen, false);
          break;
        default:
          break;
      }

      switch (markStarAction) {
        case MarkStarAction.markStar:
          _updateKeyword(email, KeyWordIdentifier.emailFlagged, true);
          break;
        case MarkStarAction.unMarkStar:
          _updateKeyword(email, KeyWordIdentifier.emailFlagged, false);
          break;
        default:
          break;
      }

      if (markAsAnswered) {
        _updateKeyword(email, KeyWordIdentifier.emailAnswered, true);
      }

      if (markAsForwarded) {
        _updateKeyword(email, KeyWordIdentifier.emailForwarded, true);
      }

      if (labelKeyword != null) {
        _updateKeyword(email, labelKeyword, isLabelAdded);
      }
    }

    currentEmails.refresh();
  }

  void _updateKeyword(
    PresentationEmail presentationEmail,
    KeyWordIdentifier keyword,
    bool value,
  ) {
    if (value) {
      presentationEmail.keywords?[keyword] = true;
    } else {
      presentationEmail.keywords?.remove(keyword);
    }
  }

  void setCurrentEmailState(jmap.State? newState) {
    currentEmailState = newState;
  }

  void clear() {
    emailsInCurrentMailbox.clear();
    listResultSearch.clear();
    isInSearchMode.value = false;
    currentEmailState = null;
  }
}
