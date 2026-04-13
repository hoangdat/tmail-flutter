import 'package:get/get.dart';
import 'package:jmap_dart_client/jmap/mail/mailbox/mailbox.dart';
import 'package:model/mailbox/presentation_mailbox.dart';

/// App-lifecycle provider for mailbox state.
/// Holds mapMailboxById and selectedMailbox — pure mailbox data.
class MailboxStateProvider extends GetxService {
  final selectedMailbox = Rxn<PresentationMailbox>();
  Map<MailboxId, PresentationMailbox> mapMailboxById = {};

  void updateMapMailboxById(Map<MailboxId, PresentationMailbox> newMap) {
    mapMailboxById = newMap;
  }

  void setSelectedMailbox(PresentationMailbox? mailbox) {
    selectedMailbox.value = mailbox;
  }

  void clear() {
    selectedMailbox.value = null;
    mapMailboxById = {};
  }
}
