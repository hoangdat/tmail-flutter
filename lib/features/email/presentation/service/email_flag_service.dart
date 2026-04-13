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
import 'package:tmail_ui_user/features/thread/domain/usecases/mark_as_multiple_email_read_interactor.dart';

class EmailFlagService {
  final MarkAsEmailReadInteractor _markAsEmailReadInteractor;
  final MarkAsMultipleEmailReadInteractor _markAsMultipleEmailReadInteractor;

  EmailFlagService(
    this._markAsEmailReadInteractor,
    this._markAsMultipleEmailReadInteractor,
  );

  Stream<Either<Failure, Success>> markAsRead(
    Session session,
    AccountId accountId,
    EmailId emailId,
    ReadActions readActions,
    MarkReadAction markReadAction,
    MailboxId? mailboxId,
  ) {
    return _markAsEmailReadInteractor.execute(
      session,
      accountId,
      emailId,
      readActions,
      markReadAction,
      mailboxId,
    );
  }

  Stream<Either<Failure, Success>> markAsReadMultiple(
    Session session,
    AccountId accountId,
    List<EmailId> emailIds,
    ReadActions readActions,
    Map<MailboxId, List<EmailId>> emailIdsByMailboxId,
  ) {
    return _markAsMultipleEmailReadInteractor.execute(
      session,
      accountId,
      emailIds,
      readActions,
      emailIdsByMailboxId,
    );
  }
}
