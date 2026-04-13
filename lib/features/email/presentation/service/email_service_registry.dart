import 'package:get/get.dart';
import 'package:tmail_ui_user/features/email/domain/usecases/mark_as_email_read_interactor.dart';
import 'package:tmail_ui_user/features/email/presentation/service/email_flag_service.dart';
import 'package:tmail_ui_user/features/thread/domain/usecases/mark_as_multiple_email_read_interactor.dart';

class EmailServiceRegistry extends GetxService {
  final MarkAsEmailReadInteractor _markAsEmailReadInteractor;
  final MarkAsMultipleEmailReadInteractor _markAsMultipleEmailReadInteractor;

  EmailServiceRegistry(
    this._markAsEmailReadInteractor,
    this._markAsMultipleEmailReadInteractor,
  );

  late final flag = EmailFlagService(
    _markAsEmailReadInteractor,
    _markAsMultipleEmailReadInteractor,
  );
}
