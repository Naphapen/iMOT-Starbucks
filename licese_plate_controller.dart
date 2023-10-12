import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:imot/common/Other/app_colors.dart';
import 'package:imot/common/Other/date_utils.dart';
import 'package:imot/common/Other/dialog_utils.dart';
import 'package:imot/common/Other/general_function.dart';
import 'package:imot/common/cache/box_cache.dart';
import 'package:imot/common/models/shared/user_profile.dart';
import 'package:imot/common/models/view/vehicle_view_model.dart';
import 'package:imot/Api_Repository_Service/services/battery_service.dart';
import 'package:imot/Api_Repository_Service/services/location_service.dart';
import 'package:imot/common/shared/app_enum.dart';
import 'package:imot/common/widgets/buttons/button_component.dart';
import 'package:imot/Api_Repository_Service/repositories/iems_repository.dart';
import 'package:imot/Api_Repository_Service/repositories/job_repository.dart';

class LicensePlateController extends GetxController {
  RxBool isLoadVehilce = false.obs;
  VehicleViewModel? vehicleInfoNonActive;
  BatteryService batteryService = BatteryService();
  LocationService get locationService => LocationService();

  UserProfile? get auth => BoxCacheUtil.getAuthUser;

  Future<void> onGetVehicle(String licensePlate) async {
    try {
      isLoadVehilce(true);

      var res = await IemsRepository().fetchVehicle(licensePlate);
      vehicleInfoNonActive = res;
    } catch (e) {
      //print(e);
    } finally {
      isLoadVehilce(false);
    }
  }

  Future<bool> checkJobPendingEmployee(String? licensePlate) async {
    if (auth?.vehicleSupplierFlag != 'Y') {
      try {
        var result =
            await JobRepository().getJobActiveLicensePlate(licensePlate);
        var listData = List<Map<String, dynamic>>.from(result?.results ?? []);
        if (result?.code == '0001') {
          dialogUtils.dialogCustom(
            overideWidget: true,
            content: SizedBox(
              height: Get.size.height * .5,
              width: Get.size.width * .8,
              child: Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Text(
                    'ไม่สามารถเปลี่ยนทะเบียน $licensePlate ได้ เนื่องจากคุณมีงานที่กำลังทำดำเนินการอยู่หรือรับการแล้ว ',
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView.builder(
                      itemCount: listData.length,
                      shrinkWrap: true,
                      itemBuilder: (_, i) {
                        var status = listData[i]['jobLastStatusCode'];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          visualDensity:
                              const VisualDensity(horizontal: -4, vertical: -4),
                          dense: true,
                          title: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                listData[i]['jobNo'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Chip(
                                backgroundColor: status == 'START'
                                    ? AppColors.greenColor01
                                    : null,
                                padding: EdgeInsets.zero,
                                visualDensity: const VisualDensity(
                                  horizontal: -4,
                                  vertical: -4,
                                ),
                                label: Text(
                                  status == 'START' ? 'กำลังทำงาน' : 'รับงาน',
                                  style: TextStyle(
                                    fontSize: 10.sp,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                              '${listData[i]['licensePlate']}-${listData[i]['licenseProvince']}'),
                          trailing: Text(
                            dateUtils.convertDateFormat(
                                listData[i]['jobDt'], 'dd/MM/yyyy HH:mm'),
                            style: TextStyle(
                              fontSize: 12.sp,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              SizedBox(
                width: Get.size.width,
                child: ButtonWidgets.closeButtonOutline(onTab: () {
                  Get.back(closeOverlays: true);

                  GLFunc.showSnackbar(
                    message: 'เปลี่นแปลงทะเบียนไม่สำเร็จ',
                    showIsEasyLoading: true,
                    type: SnackType.ERROR,
                  );
                }),
              ),
            ],
          );
          return false;
        }

        return true;
      } catch (e) {
        return false;
      }
    }

    return true;
  }
}
