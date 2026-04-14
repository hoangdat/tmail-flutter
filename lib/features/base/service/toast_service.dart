import 'package:core/presentation/extensions/color_extension.dart';
import 'package:core/presentation/resources/image_paths.dart';
import 'package:core/presentation/utils/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';

/// App-lifecycle service that wraps [AppToast] using [Get.overlayContext].
/// Use this from BusHandlers or any GetxService instead of passing BuildContext around.
class ToastService extends GetxService {
  AppToast get _toast => Get.find<AppToast>();
  ImagePaths get _imagePaths => Get.find<ImagePaths>();

  BuildContext? get _context => Get.context;
  BuildContext? get _overlayContext => Get.overlayContext;

  void showSuccess(String message, {String? svgIcon}) {
    if (_overlayContext == null) return;
    _toast.showToastSuccessMessage(
      _overlayContext!,
      message,
      leadingSVGIcon: svgIcon,
    );
  }

  /// Shows a toast with a single undo/action button.
  void showWithAction({
    required String message,
    required String actionName,
    required VoidCallback onAction,
    String? svgIcon,
    Widget? actionIcon,
  }) {
    if (_overlayContext == null || _context == null) return;
    _toast.showToastMessage(
      _overlayContext!,
      message,
      actionName: actionName,
      onActionClick: onAction,
      leadingSVGIcon: svgIcon ?? _imagePaths.icToastSuccessMessage,
      backgroundColor: AppColor.toastSuccessBackgroundColor,
      textColor: Colors.white,
      actionIcon: actionIcon ?? SvgPicture.asset(_imagePaths.icUndo),
    );
  }
}
