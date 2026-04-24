
import '../factories/robot_factory.dart';
import '../mixin/scenario_utils_mixin.dart';
import '../models/user_credentials.dart';
import 'base_scenario.dart';

abstract class BaseTestScenario extends BaseScenario with ScenarioUtilsMixin {
  final RobotFactory robots;
  final UserCredentials? credentials;

  const BaseTestScenario(super.$, this.robots, {this.credentials});

  @override
  Future<void> execute() async {
    await robots.loginRobot().loginWithBasicAuth(
      username: credentials?.username ?? const String.fromEnvironment('USERNAME'),
      hostUrl: credentials?.hostUrl ?? const String.fromEnvironment('BASIC_AUTH_URL'),
      email: credentials?.email ?? const String.fromEnvironment('BASIC_AUTH_EMAIL'),
      password: credentials?.password ?? const String.fromEnvironment('PASSWORD'),
    );
    await runTestLogic();
  }

  Future<void> runTestLogic();
}
