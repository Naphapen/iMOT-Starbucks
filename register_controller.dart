import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart';
import 'package:imot/common/Other/dialog_utils.dart';
import 'package:imot/common/Other/general_function.dart';
import 'package:imot/common/cache/box_cache.dart';
import 'package:imot/common/shared/app_enum.dart';
import 'package:imot/common/widgets/buttons/button_component.dart';
import 'package:imot/Api_Repository_Service/repositories/user_repository.dart';
import 'package:imot/Api_Repository_Service/services/system_info_service.dart';

class RegisterController extends GetxController {
  RxBool isLoading = false.obs;
  RxBool isShowPassword = false.obs;
  RxBool isValidEmployee = false.obs;
  RxMap<String, dynamic>? employeeInfo;

  final SystemInfoService systemAppInfo = SystemInfoService();

  final TextEditingController employeeNo = TextEditingController();
  final TextEditingController username = TextEditingController();
  final TextEditingController password = TextEditingController();
  final form = GlobalKey<FormState>();

  @override
  void onInit() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    super.onInit();
  }

  @override
  void onClose() {
    employeeInfo?.clear();
    super.onClose();
  }

  UserRepository get userRepo => UserRepository.instance();

  Future<String?> get fcmToken => FirebaseMessaging.instance.getToken();
  String? get mobileId => BoxCacheUtil.appUuId();

  Future<void> getEmployee() async {
    try {
      isLoading(true);
      isValidEmployee(false);
      GLFunc.instance.showLoading();
      if (GetUtils.isNullOrBlank(employeeNo.text)!) {
        //print('employee empty');
        return;
      }

      var res = await userRepo.getEmployee(employeeNo.text);
      employeeInfo = RxMap(res);
      isValidEmployee(true);
    } on DioError catch (e) {
      isValidEmployee(false);
      GLFunc.showSnackbar(
        message: e.response?.data?['message']['th'],
        type: SnackType.ERROR,
        showIsEasyLoading: true,
      );
    } finally {
      isLoading(false);
      GLFunc.instance.hideLoading();
    }
  }

  Future<void> register(Map regis) async {
    if (!await GLFunc.isClientOnline()) {
      GLFunc.showSnackbar(
        message: 'offline.desc'.tr,
        type: SnackType.ERROR,
        showIsEasyLoading: true,
      );
    }

    isLoading(true);
    var version = await SystemInfoService().getAppInfo();

    regis['mobileVersion'] = version.version;
    regis['username'] = username.text;
    regis['password'] = password.text;

    await GLFunc.instance.showLoading().then(
          (value) =>
              UserRepository.instance().postRigister(regis).then((value) {
            dialogUtils.showDialogCustomIcon(
              titleIcon: const Icon(
                Icons.check_circle,
                size: 85,
                color: Colors.green,
              ),
              description: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text('${value['message']['th']}',
                    style: const TextStyle(
                      fontSize: 14.5,
                    )),
              ),
              actions: [
                ButtonWidgets.cancelButtonOutline(
                  label: 'label.close',
                ),
              ],
              actionWithContent: true,
            );
          }).whenComplete(() {
            isLoading(false);
            Future.delayed(const Duration(milliseconds: 300));
            update();
            //print(regis);
          }).catchError((onError) {
            var e = onError as DioError;
            dialogUtils.showDialogCustomIcon(
              description: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                    '${e.response!.data['message']?['th'] ?? 'เกิดข้อผิดพลาด ไม่สามารถดำเนินการต่อได้'}',
                    style: const TextStyle(
                      fontSize: 14.5,
                    )),
              ),
              actions: [
                ButtonWidgets.cancelButtonOutline(
                  label: 'label.close',
                ),
              ],
              actionWithContent: true,
            );
          }),
        );
  }

  Future<void> login() async {
    //print('Login to page');
    await EasyLoading.show(
      status: 'กรุณารอสักครู่...',
      maskType: EasyLoadingMaskType.clear,
    );
    await Future.delayed(const Duration(milliseconds: 300));
  }
}
