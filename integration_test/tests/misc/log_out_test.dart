import '../../base/test_base.dart';
import '../../scenarios/misc/log_out_scenario.dart';

void main() {
  TestBase().runPatrolTest(
    description: 'Should see Twake welcome screen when log out successfully',
    scenarioBuilder: ($, robots, _) => LogOutScenario($, robots),
  );
}