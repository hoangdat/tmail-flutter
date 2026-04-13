import 'package:core/presentation/state/failure.dart';
import 'package:core/presentation/state/success.dart';
import 'package:dartz/dartz.dart';
import 'package:jmap_dart_client/jmap/account_id.dart';
import 'package:jmap_dart_client/jmap/core/properties/properties.dart';
import 'package:jmap_dart_client/jmap/core/session/session.dart';
import 'package:jmap_dart_client/jmap/core/sort/comparator.dart';
import 'package:jmap_dart_client/jmap/core/unsigned_int.dart';
import 'package:tmail_ui_user/features/base/state/mailbox_state_provider.dart';
import 'package:tmail_ui_user/features/email/presentation/action/email_action.dart';
import 'package:tmail_ui_user/features/mailbox_dashboard/presentation/controller/search_controller.dart'
    as search;
import 'package:tmail_ui_user/features/thread/domain/model/email_filter.dart';
import 'package:tmail_ui_user/features/thread/domain/state/get_all_email_state.dart';
import 'package:tmail_ui_user/features/thread/domain/usecases/get_emails_in_mailbox_interactor.dart';
import 'package:tmail_ui_user/features/thread/presentation/extensions/list_presentation_email_extensions.dart';

class GetEmailsInMailboxAction extends EmailAction {
  final GetEmailsInMailboxInteractor _interactor;
  final MailboxStateProvider _mailboxStateProvider;
  final search.SearchController _searchController;
  final UnsignedInt? limit;
  final Set<Comparator>? sort;
  final EmailFilter? emailFilter;
  final Properties? propertiesCreated;
  final Properties? propertiesUpdated;
  final bool getLatestChanges;
  final bool useCache;
  final bool forceEmailQuery;

  GetEmailsInMailboxAction(
    this._interactor,
    this._mailboxStateProvider,
    this._searchController, {
    this.limit,
    this.sort,
    this.emailFilter,
    this.propertiesCreated,
    this.propertiesUpdated,
    this.getLatestChanges = true,
    this.useCache = true,
    this.forceEmailQuery = false,
  });

  @override
  String get tag => 'GetEmailsInMailbox(${emailFilter?.mailboxId?.id.value})';

  @override
  Stream<Either<Failure, Success>> execute(
    Session session,
    AccountId accountId,
  ) async* {
    yield* _interactor
        .execute(
          session,
          accountId,
          limit: limit,
          sort: sort,
          emailFilter: emailFilter,
          propertiesCreated: propertiesCreated,
          propertiesUpdated: propertiesUpdated,
          getLatestChanges: getLatestChanges,
          useCache: useCache,
          forceEmailQuery: forceEmailQuery,
        )
        .map((result) => result.fold(
              (failure) => Left<Failure, Success>(failure),
              (success) {
                if (success is GetAllEmailSuccess) {
                  return Right<Failure, Success>(_syncSuccess(success));
                }
                return Right<Failure, Success>(success);
              },
            ));
  }

  GetAllEmailSuccess _syncSuccess(GetAllEmailSuccess success) {
    final syncedEmails = success.emailList.syncPresentationEmail(
      mapMailboxById: _mailboxStateProvider.mapMailboxById,
      selectedMailbox: _mailboxStateProvider.selectedMailbox.value,
      searchQuery: _searchController.searchQuery,
      isSearchEmailRunning: _searchController.isSearchEmailRunning,
    );

    return GetAllEmailSuccess(
      emailList: syncedEmails,
      currentEmailState: success.currentEmailState,
      currentMailboxId: success.currentMailboxId,
    );
  }
}
