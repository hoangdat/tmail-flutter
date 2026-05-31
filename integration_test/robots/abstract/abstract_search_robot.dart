abstract class AbstractSearchRobot {
  Future<void> tapOnSearchField();
  Future<void> enterKeyword(String keyword);
  Future<void> tapOnShowAllResultsText();
  Future<void> scrollToEndListSearchFilter();
  Future<void> scrollToDateTimeButtonFilter();
  Future<void> openDateTimeBottomDialog();
  Future<void> selectDateTime(String dateTimeType);
  Future<void> openSortOrderBottomDialog();
  Future<void> selectSortOrder(String sortOrderName);
  Future<void> selectAttachmentFilter();
  Future<void> openLabelListModal();
}
