import 'dart:async';
import 'dart:io';

import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:get/get.dart';

class BatteryController extends GetxController {
  final Battery _battery = Battery();
  int batterPercen = 0;
  RxBool isBatterLow = false.obs;
  late BatteryState batteryState;
  StreamSubscription<BatteryState>? batteryStateSubscription;

  @override
  void onInit() {
    if (Platform.isAndroid || Platform.isIOS) {
      batteryStateSubscription =
          _battery.onBatteryStateChanged.listen((BatteryState state) {
        batteryState = state;
        batterUpdate();
      });
    }

    super.onInit();
  }

  void batterUpdate() async {
    try {
      final getPercenBat = await _battery.batteryLevel;
      batterPercen = getPercenBat;
      if (batterPercen >= 90) {
        if (batteryState == BatteryState.charging) {}
      } else if (batterPercen <= 20 && batteryState != BatteryState.charging) {
        //print('[----> Total Battery $batterPercen ]');
        AwesomeNotifications().createNotification(
          content: NotificationContent(
            id: 1,
            channelKey: 'Noty_Other',
            title: 'แจ้งเตือนระบบ',
            body: 'แบตเตอร์ของคุณเหลือน้อย โปรดทำการชาร์จ',
            autoDismissible: true,
          ),
        );
      }
      update();
    } catch (e) {
      rethrow;
    }
  }
}
