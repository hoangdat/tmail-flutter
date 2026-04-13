import 'package:core/presentation/state/failure.dart';
import 'package:core/presentation/state/success.dart';
import 'package:dartz/dartz.dart';
import 'package:jmap_dart_client/jmap/account_id.dart';
import 'package:jmap_dart_client/jmap/core/session/session.dart';
import 'package:jmap_dart_client/jmap/mail/email/email.dart';
import 'package:jmap_dart_client/jmap/mail/mailbox/mailbox.dart';
import 'package:model/email/read_actions.dart';
import 'package:tmail_ui_user/features/email/domain/model/mark_read_action.dart';
import 'package:tmail_ui_user/features/email/domain/usecases/mark_as_email_read_interactor.dart';
import 'package:tmail_ui_user/features/email/presentation/action/email_action.dart';

class MarkAsReadEmailAction extends EmailAction { // co the phai equatable
  final EmailId emailId;
  final ReadActions readActions;
  final MarkReadAction markReadAction;
  final MailboxId? mailboxId;
  final MarkAsEmailReadInteractor _interactor;

  MarkAsReadEmailAction(
    this.emailId,
    this.readActions,
    this.markReadAction,
    this.mailboxId,
    this._interactor,
  );

  @override
  String get tag => 'MarkAsRead($emailId)';

  @override
  Stream<Either<Failure, Success>> execute(Session session, AccountId accountId) {
    return _interactor.execute(
      session, accountId, emailId, readActions, markReadAction, mailboxId,
    );
  }
}
