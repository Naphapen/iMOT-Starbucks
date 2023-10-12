// ignore_for_file: unused_local_variable

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:imot/bindings/app_binding.dart';
import 'package:imot/common/Other/easy_loading_config.dart';
import 'package:imot/common/Other/general_function.dart';
import 'package:imot/pages/now_page/loading_page.dart';
import 'package:imot/common/locale/locale_string.dart';
import 'package:imot/common/routers/app_pages.dart';
import 'package:imot/common/shared/app_scroll_behavior.dart';
import 'package:imot/common/themes/app_theme.dart';

import 'package:upgrader/upgrader.dart';

bool appActive = true;

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness:
          !kIsWeb && GetPlatform.isAndroid ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));

    return ScreenUtilInit(
      designSize: const Size(393, 851),
      useInheritedMediaQuery: true,
      splitScreenMode: true,
      minTextAdapt: true,
      builder: (_, child) {
        if (Get.context?.isTablet == true) {
          GLFunc.instance.unlockScreenPortrait();
        }

        ScreenUtil().setSp(28);

        // final appcast = Appcast();
        var appcastURL =
            '${dotenv.get('BASE_URL_API')}/v2/systems/check/versios/update';

        final cfg = AppcastConfiguration(
          url: appcastURL,
          supportedOS: ['android'],
        );

        return Listener(
          onPointerDown: (_) async {
            FocusScopeNode currentFocus = FocusScope.of(context);
            FocusManager.instance.primaryFocus?.unfocus();

            if (!currentFocus.hasPrimaryFocus &&
                currentFocus.focusedChild != null) {
              currentFocus.unfocus();
            }

            if (EasyLoading.isShow &&
                EasyLoading.instance.dismissOnTap == true) {
              await EasyLoading.dismiss();
            }
          },
          child: GetMaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'iMOT',
            scrollBehavior: const AppScrollBehavior(),
            darkTheme: AppTheme.dark,
            themeMode: ThemeMode.light,
            enableLog: true,
            defaultTransition: Transition.fade,
            opaqueRoute: Get.isOpaqueRouteDefault,
            popGesture: Get.isPopGestureEnable,
            transitionDuration: Get.defaultTransitionDuration,
            defaultGlobalState: true,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              DefaultCupertinoLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: AppTheme.buildTheme(Brightness.light),
            getPages: AppPages.routes,
            initialBinding: AppBinding(),
            // home: const RootInitPage(),
            home: LoadingPage(),
            builder: EasyLoadingConfig.init(),

            translations: LocaleService(),
            supportedLocales: LocaleService.locales,
          ),
        );
      },
    );
  }
}
