import 'package:flutter_test/flutter_test.dart';
import 'package:tmail_ui_user/features/thread/presentation/thread_view.dart';

import '../base/base_test_scenario.dart';

class LoginWithBasicAuthScenario extends BaseTestScenario {
  const LoginWithBasicAuthScenario(super.$, super.robots, {super.credentials});

  @override
  Future<void> runTestLogic() async {
    await expectViewVisible($(ThreadView));
  }
}
