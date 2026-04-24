import '../../base/test_base.dart';
import '../../models/test_shard.dart';
import '../../scenarios/search_email_with_sort_order_scenario.dart';

void main() {
  TestBase().runPatrolTest(
    description: 'Should see list email displayed by sort order selected when search email successfully',
    shard: TestShard.searchEmails,
    userSlot: 0,
    scenarioBuilder: ($, robots, credentials) =>
        SearchEmailWithSortOrderScenario($, robots, credentials: credentials),
  );
}