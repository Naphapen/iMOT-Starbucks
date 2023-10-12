import 'dart:async';

import 'package:device_apps/device_apps.dart';
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
// import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:imot/Api_Repository_Service/controllers/battery_controller.dart';
// import 'package:imot/Api_Repository_Service/controllers/socket_controller.dart';
import 'package:imot/Api_Repository_Service/services/connectivity_service.dart';
import 'package:imot/common/Other/app_colors.dart';
import 'package:imot/common/Other/general_function.dart';
import 'package:imot/common/models/shared/user_profile.dart';
import 'package:imot/common/routers/app_pages.dart';
import 'package:imot/Api_Repository_Service/services/auth_service.dart';
import 'package:imot/common/cache/box_cache.dart';
import 'package:imot/common/shared/app_enum.dart';
import 'package:imot/Api_Repository_Service/controllers/jobs_controller.dart';
import 'package:imot/Api_Repository_Service/repositories/login_repository.dart';
import 'package:imot/database/database.dart';
import 'package:imot/pages/now_page/main_page/home_page.dart';
import 'package:imot/pages/now_page/main_page/login_page.dart';
import 'package:imot/pages/now_page/main_page/update_page.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:upgrader/upgrader.dart';
import 'package:url_launcher/url_launcher.dart';

class AuthController extends GetxController {
  AuthService authService = Get.put(AuthService());

  toMain() => Get.toNamed(AppRoutes.MAIN);

  RxBool isLogged = false.obs;
  RxBool isLoading = true.obs;
  RxBool isShowPassword = false.obs;
  RxBool isWaitLoad = false.obs;
  final RxBool _rememberMe = false.obs;

  final TextEditingController? username = TextEditingController();
  final TextEditingController? password = TextEditingController();

  LoginRepository? loginRepository;

  UserProfile? get user => BoxCacheUtil.getAuthUser;

  ////// LOADING PERCENT ////////

  final streamConlr = StreamController<double>.broadcast();

  void addPercent(double i) => streamConlr.add(i);

  Stream<double> get getPercent => streamConlr.stream.asBroadcastStream();

  AppDatabase get db => AppDatabase.provider;

  @override
  void onInit() async {
    super.onInit();

    await taskInit();
    Get.put<BatteryController>(BatteryController(), permanent: true);
    Get.put<ConnectivityService>(ConnectivityService(), permanent: true);
    // Get.put(SocketController(), permanent: true);
  }

  @override
  void onReady() {
    setLastLogin();
    super.onReady();
  }

  percentCount({required String title, required String complete}) {
    return StreamBuilder(
      stream: getPercent,
      initialData: 0,
      builder: (context, snapshot) {
        var i = snapshot.data;
        if (i != 100) {
          return Column(
            children: [
              Text(
                title,
                style: GoogleFonts.prompt(
                  color: Colors.white,
                ),
              ),
              const SizedBox(
                height: 10,
              ),
              CircularPercentIndicator(
                radius: 30,
                lineWidth: 5,
                percent: i!.toDouble() / 100,
                center: Text(
                  '${i.toInt()} %',
                  style: GoogleFonts.prompt(
                    color: Colors.white,
                  ),
                ),
                progressColor: Colors.white,
              ),
            ],
          );
        }
        return Text(
          complete,
          style: GoogleFonts.prompt(
            color: Colors.white,
          ),
        );
      },
    );
  }

  Future<void> taskInit() async {
    isWaitLoad(true);
    List<Future<void>> task = [
      checkPermisionSplash(),
      checkMe(),
    ];

    double percentMath = 0;
    double percentUi = 0;

    for (var i = 0; i < task.length; i++) {
      await task[i];
      percentMath = (((i + 1) * 100) / task.length);
      for (var i = 0; i < percentMath.toInt(); i++) {
        await Future.delayed(const Duration(milliseconds: 5));
        if (percentUi < percentMath) {
          percentUi = percentUi + 1;
          addPercent(percentUi);
        }
      }
    }

    isWaitLoad(false);
    checkVersion();
    if (isLogged.isTrue) {
      Get.offAll(HomePage());
      // unInstaillOldApp();
    } else {
      Get.offAll(LoginPage());
      // unInstaillOldApp();
    }
  }

  Future<void> checkPermisionSplash() async {
    var camera = await Permission.camera.status;
    var location = await Permission.location.status;
    var storage = await Permission.storage.status;

    if (!camera.isGranted) {
      await Permission.camera.request();
    }
    if (!location.isGranted) {
      await Permission.location.request();
    }
    if (!storage.isGranted) {
      await Permission.storage.request();
    }
  }

  Future<void> setLastLogin() async {
    Future.delayed(const Duration(seconds: 1)).then((value) {
      try {
        Map<String, dynamic>? lastUserKeyword =
            BoxCacheUtil.box.read('REMEMBER');
        if (!BoxCacheUtil.authenticated) {
          username!.text = lastUserKeyword?['user'] ?? '';
        } else {
          username?.clear();
          password?.clear();
        }
      } catch (e) {
        //  //print(e);
      }
    });
  }

  Future<void> signIn() async {
    try {
      await authService.signInWithUserAndPassword(
          username!.text, password!.text);
      isLogged(true);
      BoxCacheUtil.setAuthentication(true);
      password?.clear();
      Get.off(HomePage());
    } on DioError catch (e) {
      GLFunc.showSnackbar(
        message: '${e.response?.data!['message']['th']}',
        showIsEasyLoading: true,
        type: SnackType.ERROR,
      );
      password?.clear();
    } finally {
      update();
    }
  }

  Future<void> checkMe() async {
    try {
      var checkMe = await authService.me();

      BoxCacheUtil.setAuthentication(true);

      BoxCacheUtil.setAuthUser(checkMe!.toMap());

      BoxCacheUtil.setUserToken(checkMe.token?.toMap());
    } catch (e) {
      BoxCacheUtil.setAuthentication(false);
      isLoading(false);
    } finally {
      isLogged(BoxCacheUtil.authenticated);
      update();
    }
  }

  // void initialization() async {
  //   await Future.delayed(const Duration(seconds: 3));
  //   //print('go! [FlutterNativeSplash ]');
  //   FlutterNativeSplash.remove();
  // }

  bool get rememberMe => _rememberMe.value;

  void setRememberMe() => _rememberMe(!rememberMe);

  Future<String?> get fcmToken => FirebaseMessaging.instance.getToken();
  String? get mobileId => BoxCacheUtil.appUuId();

  Future<void> signout() async {
    try {
      isLoading(true);
      GLFunc.instance.showLoading('กำลังออกจากระบบ');

      await authService.signOut();
      isLogged(false);
      GLFunc.showSnackbar(
        message: 'ออกจากระบบสำเร็จ',
        showIsEasyLoading: true,
        type: SnackType.SUCCESS,
      );
      Get.delete<JobsController>();
    } finally {
      isLoading(false);
      GLFunc.instance.hideLoading();
      update();
    }
  }

  Future<void> disableAccount() async {
    try {
      GLFunc.instance.showLoading('กำลังดำเนินการร้องขอโปรดรอสักครู่...');
      signout();
    } finally {
      isLoading(false);
      GLFunc.instance.hideLoading();
      update();
    }
  }

  Future<void> checkVersion() async {
    var res = await (db.select(db.jobSchedulerEntries)
          ..where((e) => e.syncFlag.isNotIn(['Y'])))
        .get();
    var res2 = await (db.select(db.jobHeaderEntries)
          ..where((e) => e.jobLastStatusCode.equals('START')))
        .get();

    final appcast = Appcast();
    var url = '${dotenv.get('BASE_URL_API')}/v2/systems/check/versios/update';
    var openTestfight =
        Uri.parse('https://apps.apple.com/th/app/testflight/id899247664');
    await appcast.parseAppcastItemsFromUri(url);
    final bestItem = appcast.bestItem();
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    var version = packageInfo.version;
    var newVersion = bestItem?.maximumSystemVersion ?? version;
    if (newVersion != version && res.isEmpty && res2.isEmpty) {
      if (GetPlatform.isAndroid) {
        return Get.defaultDialog(
          barrierDismissible: false,
          title: 'อัปเดตแอป?',
          content: Column(
            children: [
              ListTile(
                title: Text('ใหม่ iMOT $newVersion '),
                subtitle: Text('เดิม iMOT $version'),
              ),
              ListTile(
                title: const Text('รายละเอียดการอัปเดต'),
                subtitle: Text(appcast.bestItem()?.itemDescription ?? ' - '),
              ),
            ],
          ),
          actions: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                shape: const StadiumBorder(),
                side: const BorderSide(width: 2, color: Colors.green),
                backgroundColor: Colors.green.shade100,
              ),
              onPressed: () {
                Get.back();
                Get.to(
                  const UpdatePage(),
                );
              },
              child: const Text('อัปเดต'),
            ),
            const SizedBox(
              width: 20,
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                shape: const StadiumBorder(),
                side: const BorderSide(width: 1, color: Colors.black),
              ),
              onPressed: () {
                Get.back();
              },
              child: const Text(
                'ภายหลัง',
                style: TextStyle(color: Colors.black),
              ),
            ),
          ],
        );
      } else if (GetPlatform.isIOS) {
        return Get.defaultDialog(
          barrierDismissible: false,
          title: 'อัปเดตแอประบบ iOS ?',
          content: const Text(
            'มี Version ที่ใหม่กว่า\nกรุณาอัปเดตผ่าน Testflight',
            textAlign: TextAlign.center,
          ),
          actions: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                shape: const StadiumBorder(),
                side: const BorderSide(width: 2, color: Colors.green),
                backgroundColor: Colors.green.shade100,
              ),
              onPressed: () {
                launchUrl(openTestfight);
                Get.back();
              },
              child: const Text('อัปเดต'),
            ),
            const SizedBox(
              width: 20,
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                shape: const StadiumBorder(),
                side: const BorderSide(width: 1, color: Colors.black),
              ),
              onPressed: () {
                Get.back();
              },
              child: const Text(
                'ภายหลัง',
                style: TextStyle(color: Colors.black),
              ),
            ),
          ],
        );
      }
    }
    return;
  }

  void unInstaillOldApp() async {
    var res = await (db.select(db.jobHeaderEntries)
          ..where((e) => e.jobLastStatusCode.equals('START')))
        .get();
    print(res);

    bool isInstalled =
        await DeviceApps.isAppInstalled('com.interexpress.imot.test');
    if (GetPlatform.isAndroid && isInstalled && res.isEmpty) {
      var app = await DeviceApps.getApp('com.interexpress.imot.test', true);
      // var rr = app is ApplicationWithIcon;
      // var sss = DeviceApps.getInstalledApplications();

      // Get.to(() => GetAppUntall(
      //       app: app,
      //     ));
      Get.defaultDialog(
        content: CircleAvatar(
          radius: 40,
          backgroundColor: AppColors.blueColor01,
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Image.memory((app as ApplicationWithIcon).icon),
          ),
        ),
        title: 'ถอนการติดตั้ง ',
        onWillPop: () async => false,
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: ElevatedButton(
                  onPressed: () {
                    Get.back();
                  },
                  child: const Text(
                    'ปิด',
                    style: TextStyle(
                      color: Colors.blue,
                      fontSize: 14.5,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.redColor01,
                    padding: const EdgeInsets.all(2),
                  ),
                  onPressed: () async {
                    // ignore: unnecessary_null_comparison
                    if (app == null) return;
                    await DeviceApps.uninstallApp(app.packageName)
                        .then((value) async {
                      if (value) {
                        Timer.periodic(const Duration(seconds: 5),
                            (time) async {
                          var isUnstall =
                              await DeviceApps.isAppInstalled(app.packageName);
                          if (!isUnstall) {
                            time.cancel();
                            GLFunc.showSnackbar(
                              message: 'ถอนการติดตั้งสำเร็จแล้ว',
                              showIsEasyLoading: true,
                              type: SnackType.SUCCESS,
                            );
                            Future.delayed(const Duration(seconds: 1))
                                .then((value) => Get.back(closeOverlays: true));
                          }
                        });
                      }
                    });
                  },
                  icon: const Icon(Icons.delete, color: Colors.white),
                  label: Text(
                    app.appName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                    ),
                  ),
                ),
              ),
            ],
          )
        ],
      );
    }
  }
}
