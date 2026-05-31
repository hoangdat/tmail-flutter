import 'package:flutter_test/flutter_test.dart';
import 'package:labels/labels.dart';
import 'package:tmail_ui_user/features/thread/presentation/widgets/email_tile_builder.dart'
  if (dart.library.html) 'package:tmail_ui_user/features/thread/presentation/widgets/email_tile_web_builder.dart';

import '../../base/base_test_scenario.dart';
import '../../mixin/provisioning_label_scenario_mixin.dart';
import '../../robots/labels/label_list_context_menu_robot.dart';

class SearchEmailWithTagScenario extends BaseTestScenario
    with ProvisioningLabelScenarioMixin {
  const SearchEmailWithTagScenario(super.$, super.robots);

  @override
  Future<void> runTestLogic() async {
    const emailUser = String.fromEnvironment('BASIC_AUTH_EMAIL');

    final searchRobot = robots.searchRobot();
    final labelListContextMenuRobot = LabelListContextMenuRobot($);

    final labels = await provisionLabelsByDisplayNames(
      ['Search Tag 1', 'Search Tag 2', 'Search Tag 3'],
    );
    await $.pumpAndSettle();

    int emailCount = 3;
    for (final label in labels) {
      await provisionEmail(
        buildEmailsForLabel(
          label: label,
          toEmail: emailUser,
          count: emailCount,
        ),
        requestReadReceipt: false,
      );
    }

    if (labels.isNotEmpty) {
      await $.waitUntilVisible($(labels.first.safeDisplayName));
    }

    await searchRobot.tapOnSearchField();

    for (final label in labels) {
      final labelDisplayName = label.safeDisplayName;

      await searchRobot.openLabelListModal();
      await _expectLabelListContextMenuVisible();

      await labelListContextMenuRobot.selectLabelByName(labelDisplayName);
      await _expectEmailListDisplayedCorrectByTag(
        tagDisplayName: labelDisplayName,
        emailCount: emailCount,
      );

      await $.pumpAndSettle(duration: const Duration(seconds: 1));
    }
  }

  Future<void> _expectLabelListContextMenuVisible() async {
    await expectViewVisible($(#label_list_bottom_sheet_context_menu));
  }

  Future<void> _expectEmailListDisplayedCorrectByTag({
    required String tagDisplayName,
    required int emailCount,
  }) async {
    await $.waitUntilVisible($(tagDisplayName));
    for (int i = 0; i < 3; i++) {
      final count = $.tester.widgetList<EmailTileBuilder>(
        $(EmailTileBuilder).which<EmailTileBuilder>((widget) =>
            widget.subjectContains(tagDisplayName)),
      ).length;
      if (count >= emailCount) break;
      await $.pump(const Duration(seconds: 1));
    }

    final listEmailTileWithTag = $(EmailTileBuilder).which<EmailTileBuilder>((widget) =>
        widget.subjectContains(tagDisplayName)).allCandidates;

    expect(listEmailTileWithTag.length, greaterThanOrEqualTo(emailCount));
  }
}

extension on EmailTileBuilder {
  bool subjectContains(String text) {
    return presentationEmail.subject?.contains(text) == true;
  }
}
