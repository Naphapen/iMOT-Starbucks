// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
// import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:imot/Api_Repository_Service/controllers/jobs_controller.dart';
import 'package:imot/common/Other/app_config.dart';
import 'package:imot/common/Other/easy_loading_config.dart';
import 'package:imot/common/Other/general_function.dart';

import 'package:imot/common/firebase/notification_controller.dart';
import 'package:imot/common/cache/box_cache.dart';
import 'package:imot/common/locale/locale_string.dart';
import 'package:imot/common/themes/app_theme.dart';
import 'dart:developer' as developer;

import 'package:imot/app.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:ui';

import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_background_service_ios/flutter_background_service_ios.dart';
import 'package:imot/Api_Repository_Service/services/backgrounds/job_service.dart';

void initServices() async {
  // print('starting services ...');
}

void main() async {
  await GetStorage.init();
  await dotenv.load(fileName: 'assets/config/.env.uat');
  WidgetsBinding binding = WidgetsFlutterBinding.ensureInitialized();

  initializeService('.env.uat');
  final prefs = await SharedPreferences.getInstance();
  prefs.reload();

  var appConfig = AppConfig(
    appEnvironment: AppEnvironment.UAT,
    appName: dotenv.get('APP_NAME'),
    description: dotenv.get('DESCRIPTION'),
    baseUrl: dotenv.get('BASE_URL_API'),
    themeData: AppTheme.light,
    child: const MyApp(),
    showPerformanceOverlay: false,
    variables: {},
  );

  runZonedGuarded(
    () {
      GLFunc.instance.lockScreenPortrait().then((_) async {
        ScreenUtil.ensureScreenSize();

        var appUUid = BoxCacheUtil.appUuId();
        if (appUUid == null) {
          PackageInfo packageInfo = await PackageInfo.fromPlatform();

          var imei = packageInfo.buildSignature;

          BoxCacheUtil.setAppUuid(imei);
        }
        initServices();
        runApp(appConfig.child);
      });
    },
    (dynamic error, dynamic stack) {
      developer.log("Something went wrong!", error: error, stackTrace: stack);
    },
  );

  if (Platform.isAndroid) {
    binding.renderView.automaticSystemUiAdjustment = false;
  } else {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: [SystemUiOverlay.bottom, SystemUiOverlay.top]);
  }

  if (GetPlatform.isMobile) {
    if (await GLFunc.isClientOnline()) {
      await NotificationController.initializeLocalNotifications(debug: false);
      await NotificationController.initializeRemoteNotifications(debug: false);
    } else {}
  } else if (GetPlatform.isDesktop) {}

  LocaleService().initLocale();

  BoxCacheUtil.box.write('env', 'uat');

  EasyLoadingConfig.configLoading();

  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(['assets/fonts'], license);
  });

  if (GetPlatform.isMobile) {
    FlutterImageCompress.showNativeLog = true;
  }
}

const notificationId = 888;
const notificationChannelId = 'Background_Service';

Future<void> initializeService([String env = 'dev']) async {
  WidgetsFlutterBinding.ensureInitialized();

  final service = FlutterBackgroundService();

  await AwesomeNotifications().initialize(
    'resource://drawable/res_app_icon',
    [
      NotificationChannel(
        channelKey: notificationChannelId,
        channelName: 'Background Service',
        channelDescription: 'Executing process in background',
        defaultColor: Colors.white,
        importance: NotificationImportance.Low,
        ledColor: Colors.red,
        channelShowBadge: false,
      ),
    ],
    debug: false,
  );

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: false,
      notificationChannelId: notificationChannelId,
      initialNotificationTitle: 'Background Service',
      initialNotificationContent: 'Initializing',
      foregroundServiceNotificationId: notificationId,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
  Future.delayed(const Duration(seconds: 3)).then((_) {
    service.startService();
  });
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  SharedPreferences preferences = await SharedPreferences.getInstance();
  await preferences.reload();
  final log = preferences.getStringList('log') ?? <String>[];
  log.add(DateTime.now().toIso8601String());
  await preferences.setStringList('log', log);

  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  await GetStorage.init();
  await dotenv.load(fileName: 'assets/config/.env.uat');

  // await autoUpdateLocation(service);
  await autoUpdateData(service);
}

// Future<void> autoUpdateLocation(ServiceInstance service) async {
//   print('binding service: AUTOUPDATELOCATION');

//   Timer.periodic(const Duration(minutes: 1), (timer) async {
//     if (service is AndroidServiceInstance) {
//       if (await service.isForegroundService()) {
//         await Future.delayed(const Duration(seconds: 1));

//         var isAllow =
//             await GLFunc.instance.requestPermission(Permission.location);

//         if (isAllow) {
//           await BackgroundJobServices()
//               .jobSendLocation(service, notificationChannelId);
//         } else {
//           print('Please Allow permission location');
//         }
//       } else {
//         var isAllow =
//             await GLFunc.instance.requestPermission(Permission.location);

//         if (isAllow) {
//           await BackgroundJobServices()
//               .jobSendLocation(service, notificationChannelId);
//         } else {
//           print('Please Allow permission location');
//         }
//       }
//     } else if (service is IOSServiceInstance) {
//       var isAllow =
//           await GLFunc.instance.requestPermission(Permission.location);

//       if (isAllow) {
//         await BackgroundJobServices()
//             .jobSendLocation(service, notificationChannelId);
//       } else {
//         print('Please Allow permission location');
//       }
//     }

//     print('FLUTTER BACKGROUND SERVICE AUTOUPDATELOCATION: ${DateTime.now()}');
//   });
// }

Future<void> autoUpdateData(ServiceInstance service) async {
  Timer.periodic(const Duration(minutes: 1), (timer) async {
    var currentDt = DateTime.now();

    await JobsController().getCountTask();

    if (service is AndroidServiceInstance) {
      print(
          'FLUTTER BACKGROUND SERVICE AUTOUPDATEDATA: ${DateTime.now()} Next--> ${currentDt.add(const Duration(seconds: 30))}');
      if (await service.isForegroundService()) {
        service.setForegroundNotificationInfo(
          title: "iMOT Service update data",
          content:
              "Updated D at $currentDt Next--> ${currentDt.add(const Duration(seconds: 30))}",
        );

        await BackgroundJobServices().jobScheduledsX();
      } else {
        await BackgroundJobServices()
            .jobScheduledsX()
            .then((_) {})
            .catchError((onError) {});
      }
    } else if (service is IOSServiceInstance) {
      await BackgroundJobServices()
          .jobScheduledsX()
          .then((_) {})
          .catchError((onError) {});
    }
  });
}
