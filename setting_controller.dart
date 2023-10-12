// ignore_for_file: unused_local_variable

import 'package:easy_app_installer/easy_app_installer.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart';
import 'package:imot/common/Other/date_utils.dart';
import 'package:imot/common/Other/general_function.dart';
import 'package:imot/common/cache/box_cache.dart';
import 'package:imot/common/shared/app_enum.dart';
import 'package:upgrader/upgrader.dart';
import 'package:path/path.dart' as p;

class SettingController extends GetxController {
  RxBool isLoading = false.obs;
  AppcastItem? _appcastItem;

  AppcastItem? get appcastItem => _appcastItem;
  Rx<String> downloadPercentage = ''.obs;
  final upgrader = Upgrader();

  Future<void> checkUpdate() async {
    isLoading(true);
    _appcastItem = null;
    //print('checking app update');
    try {
      await upgrader.initialize();
      upgrader.debugDisplayAlways = true;
      upgrader.debugDisplayOnce = true;
      upgrader.debugLogging = true;

      final appcast = Appcast();
      var url = '${dotenv.get('BASE_URL_API')}/v2/systems/check/versios/update';
      await appcast.parseAppcastItemsFromUri(url);

      final bestItem = appcast.bestItem();

      _appcastItem = bestItem;

      if (bestItem == null) {
        GLFunc.showSnackbar(
          message: 'ไม่พบการอัปเดต',
          type: SnackType.INFO,
          showIsEasyLoading: true,
        );
        return;
      }
    } finally {
      isLoading(false);
      update();
    }
  }

  void handleDownloadStateChanged(
      EasyAppInstallerState newState, String? attachParam) {
    switch (newState) {
      case EasyAppInstallerState.onPrepared:
        break;
      case EasyAppInstallerState.onDownloading:
        break;
      case EasyAppInstallerState.onSuccess:
        if (attachParam != null) {
          BoxCacheUtil.box.write('update_path', {
            'path': attachParam,
            'version': appcastItem?.versionString,
          });
        }
        break;
      case EasyAppInstallerState.onFailed:
        break;
      case EasyAppInstallerState.onCanceled:
        break;
    }
  }

  Future<void> onDownload([bool isUpdate = false]) async {
    String? reqUrl = appcastItem?.fileURL;

    if (isUpdate && reqUrl == null) {
      await checkUpdate();
    }

    reqUrl = appcastItem!.fileURL;

    String? lastName = p.basename(reqUrl ?? '');

    if (GetUtils.isNullOrBlank(lastName)!) {
      lastName =
          'iMOT-${appcastItem!.versionString ?? dateUtils.formattedDate(DateTime.now(), 'yyyyMMdd')}.apk';
    }

    if (reqUrl!.contains('play.google.com')) {
      await EasyAppInstaller.instance.openAppMarket(
        applicationPackageName: 'com.interexpress.imot',
        isOpenSystemMarket: false,
      );
    } else {
      final path = await EasyAppInstaller.instance.downloadAndInstallApk(
        fileUrl: reqUrl,
        fileDirectory: await GLFunc.instance.getLocalPath,
        fileName: lastName,
        explainContent:
            'ต้องการอนุญาตเพื่อติดตั้งแอปอื่น เพื่ออัปเดต ใช่หรือไม่',
        positiveText: 'ตกลง',
        negativeText: 'ปิด',
        isDeleteOriginalFile: true,
        onDownloadingListener: (total) {
          if (total != -1) {
            //print("${total.toStringAsFixed(0)}%");
            downloadPercentage(total.toStringAsFixed(0));
            if (total < 100) {
              EasyLoading.showProgress(total / 100, status: 'กำลังดาวน์โหลด');
            } else {
              EasyLoading.showSuccess('ดาวน์โหลดสำเร็จ');
            }

            update();
          }
        },
        onStateListener: (ns, at) {
          handleDownloadStateChanged(ns, at);
        },
      );

      GLFunc.showSnackbar(
        message: 'ดาวโหลดไฟล์สำเร็จแล้ว',
        type: SnackType.INFO,
        showIsEasyLoading: true,
      );
      if (isUpdate) {}
    }
  }

  Future<void> onInstall() async {
    if (GetPlatform.isAndroid) {
      var last = BoxCacheUtil.box.read('update_path');

      final path = await EasyAppInstaller.instance.installApk(last['path']);
      //print("gfs installApk: $path");
    } else if (GetPlatform.isIOS) {}
  }
}
