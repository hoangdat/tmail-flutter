import 'package:core/presentation/state/failure.dart';
import 'package:core/presentation/state/success.dart';
import 'package:dartz/dartz.dart';
import 'package:jmap_dart_client/jmap/account_id.dart';
import 'package:jmap_dart_client/jmap/core/session/session.dart';
import 'package:jmap_dart_client/jmap/mail/email/email.dart';
import 'package:jmap_dart_client/jmap/mail/mailbox/mailbox.dart';
import 'package:model/email/read_actions.dart';
import 'package:tmail_ui_user/features/email/presentation/action/email_action.dart';
import 'package:tmail_ui_user/features/thread/domain/usecases/mark_as_multiple_email_read_interactor.dart';

class MarkAsReadMultipleEmailAction extends EmailAction {
  final List<EmailId> emailIds;
  final ReadActions readActions;
  final Map<MailboxId, List<EmailId>> emailIdsByMailboxId;
  final MarkAsMultipleEmailReadInteractor _interactor;

  MarkAsReadMultipleEmailAction(
    this.emailIds,
    this.readActions,
    this.emailIdsByMailboxId,
    this._interactor,
  );

  @override
  String get tag => 'MarkAsReadMultiple(${emailIds.length})';

  @override
  Stream<Either<Failure, Success>> execute(Session session, AccountId accountId) {
    return _interactor.execute(
      session, accountId, emailIds, readActions, emailIdsByMailboxId,
    );
  }
}
