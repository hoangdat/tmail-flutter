import 'package:core/presentation/state/failure.dart';
import 'package:core/presentation/state/success.dart';
import 'package:dartz/dartz.dart';
import 'package:jmap_dart_client/jmap/account_id.dart';
import 'package:jmap_dart_client/jmap/core/session/session.dart';

/// Base class for all email actions submitted to [EmailActionQueue].
/// Each subclass encapsulates the parameters and stream creation for one action type.
abstract class EmailAction {
  /// Short identifier for logging and dedup (e.g. 'MarkAsRead(emailId)').
  String get tag;

  /// Creates the domain stream. Called by the queue with session/account.
  Stream<Either<Failure, Success>> execute(Session session, AccountId accountId);

  // co the phai kiem nhiem update global state
}
