import 'package:get/get.dart';
import 'package:jmap_dart_client/jmap/account_id.dart';
import 'package:jmap_dart_client/jmap/core/session/session.dart';

class SessionStateProvider extends GetxService {
  final session = Rxn<Session>();
  final accountId = Rxn<AccountId>();

  void setSession(Session newSession, AccountId newAccountId) {
    session.value = newSession;
    accountId.value = newAccountId;
  }

  void clear() {
    session.value = null;
    accountId.value = null;
  }
}
