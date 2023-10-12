// ignore_for_file: depend_on_referenced_packages, deprecated_member_use, unused_local_variable

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:imot/Api_Repository_Service/controllers/job_detail_controller.dart';
import 'package:imot/common/Other/app_colors.dart';
import 'package:imot/common/Other/date_utils.dart';
import 'package:imot/common/Other/dialog_utils.dart';
import 'package:imot/common/Other/general_function.dart';
import 'package:imot/common/cache/box_cache.dart';
import 'package:imot/common/models/form/barcode_package_scan.dart';
import 'package:imot/common/models/form/job_update_location.dart';
import 'package:imot/common/models/form/package_scan.dart';
import 'package:imot/common/models/form/receive_mapping_data.dart';
import 'package:imot/common/models/shared/user_profile.dart';
import 'package:imot/common/models/view/activity_step.dart';
import 'package:imot/common/models/view/job_detail.dart';
import 'package:imot/common/models/view/job_location.dart';
import 'package:imot/Api_Repository_Service/services/backgrounds/job_service.dart';
import 'package:imot/Api_Repository_Service/services/battery_service.dart';
import 'package:imot/Api_Repository_Service/services/job_service.dart';
import 'package:imot/Api_Repository_Service/services/location_service.dart';
import 'package:imot/common/models/view/job_package_scan.dart';
import 'package:imot/common/models/view/packageScanModel.dart';
import 'package:imot/common/shared/app_enum.dart';
import 'package:imot/common/widgets/buttons/button_component.dart';
import 'package:imot/common/widgets/maps/gmap_util.dart';
import 'package:imot/Api_Repository_Service/controllers/audio_payer_controller.dart';
import 'package:imot/database/database.dart';
import 'package:imot/Api_Repository_Service/repositories/job_repository.dart';
import 'package:drift/drift.dart' as d;
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:collection/collection.dart';

class JobLocationController extends GetxController {
  RxBool isLoading = false.obs;
  RxBool isStepToggle = false.obs;
  RxBool isToggleFile = false.obs;
  RxBool isLoadingMap = false.obs;
  RxBool isLoadingGPS = false.obs;
  RxInt step = 0.obs;
  final RxList<JobLocation> listOfData = <JobLocation>[].obs;
  final BatteryService batteryService = BatteryService();

  RxList<ActivityStep> widgetStatus = <ActivityStep>[].obs;
  AudioPlayerController aSound = Get.put(AudioPlayerController());

  TextEditingController consigneeName = TextEditingController();

  JobLocation? activeLocation;
  RxBool isScanManifest = false.obs;
  List<Marker> mapMarkers = [];

  final manifestPackageScan = <String, List<Map<String, dynamic>>>{}.obs;
  ReceiveMappingData receiveMapData = ReceiveMappingData(
    images: [],
    packages: [],
  );

  final RxList<JobPackageScan> _listOfScanPackage = RxList();
  List<JobPackageScan> get listOfScanPackage => _listOfScanPackage;

  int get packageScanLength => listOfScanPackage.length;

  int get manifestPkgScanLength =>
      listOfScanPackage.where((x) => x.syncFlag == 'P').length;

  LocationService get locationService => LocationService();
  AppDatabase get db => AppDatabase.provider;
  JobService get jobService => JobService();
  UserProfile? get auth => BoxCacheUtil.getAuthUser;

  final Completer<GoogleMapController> gMapController = Completer();

  RxBool isDisabled = false.obs;

  Position? getCurrent;

  //////////////// SCAN PACKAGE ///////////////

  TextEditingController totalScan = TextEditingController();
  TextEditingController totalNotLabel = TextEditingController();

  List<PackageScanModel> scanPackageAll = [];
  List<String> listOfManifest = [];

  int sumNotLabel = 0;

  RxBool isScanPackage = false.obs;

  // @override
  // void onInit() {
  //   super.onInit();
  //   //print('object ============== test');
  // }

  final streamConlr = StreamController<double>.broadcast();

  void addPercent(double i) => streamConlr.add(i);

  Stream<double> get getPercent => streamConlr.stream.asBroadcastStream();

  percentCount({required String title, required String complete}) {
    return StreamBuilder(
      stream: getPercent,
      initialData: 0,
      builder: (context, snapshot) {
        var i = snapshot.data;
        if (i != 1) {
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
              CircularProgressIndicator(
                value: i!.toDouble(),
              ),
              const SizedBox(
                height: 16,
              ),
              Text(
                '${(i * 100).toInt()} %',
                style: const TextStyle(
                  color: Colors.white,
                ),
              )
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

  Future<String> getSumScanPackage({required JobLocation jobLocation}) async {
    var count = await ((db.jobPackageScanEntries.select())
          ..where(
            (t) => t.syncFlag.equals("P") & t.locationId.equals(jobLocation.id),
          ))
        .get();
    return count.length.toString();
  }

  Future<void> saveQrPackageScan({required JobLocation jobLocation}) async {
    await db.clearTable(db.jobPackageScanEntries);

    var user = BoxCacheUtil.getAuthUser;

    for (var i = 0; i < scanPackageAll.length; i++) {
      var e = scanPackageAll;
      var itemPk = JobPackageScanEntriesCompanion(
        code: d.Value(e[i].qrCode),
        jobNo: d.Value(jobLocation.jobNo!),
        ref1: d.Value(e[i].manifestNo),
        locationId: d.Value(jobLocation.id),
        createDt: d.Value(DateTime.now().toIso8601String()),
        createBy: d.Value(user?.userName),
        rawData: e[i].isManifest == true
            ? const d.Value("MANIFEST")
            : const d.Value(null),
        syncFlag: d.Value(e[i].type),
        message: e[i].isManifest == true
            ? const d.Value("SCAN MANIFEST")
            : const d.Value("SACN IN PACKAGE"),
      );

      await db.insertTable(db.jobPackageScanEntries, itemPk);
      addPercent(((i.toDouble() * 100) / scanPackageAll.length) / 100);
    }

    sumNotLabel = int.parse(totalNotLabel.text);
    addPercent(0);
  }

  Future<void> checkAndfindSetMarker(JobLocation data) async {
    isLoadingMap(true);

    double? lat = double.tryParse(data.geoLatitude ?? '');
    double? long = double.tryParse(data.geoLongitude ?? '');
    if (lat == null || long == null) {
      return;
    } else {
      await setMarker(data, 'pin-final.png');
    }
    return;
  }

  Future<void> setMarker(JobLocation data, [String? icon]) async {
    double? lat = double.tryParse(data.geoLatitude ?? '');
    double? long = double.tryParse(data.geoLongitude ?? '');
    if (lat == null && long == null) return;
    final pin1 = await GmapUtils()
        .getBytesFromAsset('assets/images/${icon ?? 'truck.png'}', 160);
    final markerPin = await GmapUtils().fromBytes(pin1);

    mapMarkers.addAll([
      Marker(
        flat: true,
        icon: markerPin,
        markerId: MarkerId("${data.id}"),
        position: LatLng(lat!, long!),
        infoWindow: InfoWindow(
          title: '${data.jobNo} - ${data.contactPerson}',
          snippet: data.address,
        ),
      ),
    ]);

    var gmap = await gMapController.future;
    await GmapUtils().setMoveCamera(gmap, LatLng(lat, long), 17);
  }

  Future<void> onLoad({
    double? jobDetailId,
    double? locationId,
    double? recordId,
    String? jobNo,
  }) async {
    try {
      await Future.delayed(const Duration(milliseconds: 500));

      listOfData.bindStream(getLocationsByDetail(
        jobDetailId: jobDetailId,
        locationId: locationId,
        jobNo: jobNo,
      ));
    } catch (e) {
      // //print('x');
    } finally {}
  }

  Stream<List<JobLocation>> getLocationsByDetail({
    double? jobDetailId,
    double? locationId,
    String? jobNo,
  }) {
    return db.watchJobLocationJoinDt(
      detailId: jobDetailId,
      locationId: locationId,
      jobNo: jobNo,
    );
  }

  Widget? buildTextDate(s, int stepInput) {
    if (s != null) step = RxInt(stepInput);

    var x = s != null
        ? Text('${dateUtils.formattedDateStr(s, 'dd/MM/yyyy HH:mm:ss')}')
        : null;
    if (x != null) {}
    return x;
  }

  Future<void> onConfirmCheckLocation({
    required Function() onTab,
    String? description,
    required int reqStepValue,
  }) async {
    if (!await Permission.location.serviceStatus.isEnabled) {
      GLFunc.showSnackbar(
        message: 'กรุณาเปิดใช้บริการตำแหน่งพิกัด',
        showIsEasyLoading: true,
        type: SnackType.INFO,
      );

      return;
    }

    final JobDetailController controlpermis = JobDetailController();
    var camera = await Permission.camera.status;
    var location = await Permission.location.status;
    // var storage = await Permission.storage.status;
    if (!camera.isGranted || !location.isGranted) {
      await controlpermis.checkPermision();
      return;
    }

    // bool? isPermission = await GLFunc.instance
    //     .requestPermission(Permission.location, openSetting: true);
    // if (isPermission == false) {
    //   GLFunc.showSnackbar(
    //     message:
    //         '$description ไม่สำเร็จ กรุณาอนุญาติการเข้าถึงตำแหน่งอุปรณ์นี้',
    //     showIsEasyLoading: true,
    //     type: SnackType.ERROR,
    //   );
    //   return;
    // }

    double lat = double.tryParse(activeLocation!.geoLatitude ?? '') ?? 0;
    double long = double.tryParse(activeLocation!.geoLongitude ?? '') ?? 0;

    List<int> stepAllow = [0, 3];
    double rounded = 0;

    if (stepAllow.contains(reqStepValue)) {
      Get.defaultDialog(
        backgroundColor: Colors.transparent,
        title: "",
        barrierDismissible: false,
        content: const CircularProgressIndicator(
          color: Colors.blue,
        ),
      );
      getCurrent = await locationService.getLocation();
      // ค้นหาระยะทาง (รัศมี) จากจุดที่อยู่ และจุดปลายทาง โดยวิธีออฟไลน์
      rounded = Geolocator.distanceBetween(
        getCurrent!.latitude,
        getCurrent!.longitude,
        lat,
        long,
      );
      Get.back();
    }

    var resConfirm = await DialogUtils().dialogCustom(
        title: Text(
          rounded > 500
              ? 'desc.radius'.trParams({
                  'meter': (500).toString(),
                })
              : 'ยืนยันบันทึกเวลา',
          style: TextStyle(
            fontSize: 16.5.sm,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SizedBox(
          width: Get.size.width * .8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.warning,
                size: 80,
                color: Colors.orange.shade300,
              ),
              if (rounded > 500) ...[
                Text(
                  'ระยะห่างของตำแหน่งคุณกับจุดหมายเกินกว่าที่กำหนดยืนยันบันทึกเวลาถึงใช่หรือไม่?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16.5.sm,
                  ),
                ),
                Text(
                    'โดยประมาณ ${rounded > 1000 ? '${(rounded / 1000).toPrecision(2)}\rกิโลเมตร' : '${rounded.toPrecision(2)}\rเมตร'}')
              ],
              if (description != null && rounded <= 500) Text(description),
            ],
          ),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: ButtonWidgets.cancelButtonOutline(),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: ButtonWidgets.comfirmButton(
                  confirm: Text(
                    'label.yes'.tr,
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTab: () {
                    Get.back(result: true);
                  },
                  backgroundColor: AppColors.green300,
                ),
              )
            ],
          )
        ]);

    if (resConfirm == true) {
      await GLFunc.instance.showLoading('กำลังบันทึกข้อมูล...');
      await onTab();
      GLFunc.instance.hideLoading();
    } else {
      GLFunc.instance.hideLoading();
    }
  }

  String messageToError(DioError e) {
    var message = e.error is SocketException || e.error is TimeoutException
        ? 'ไม่สามารถเชื่อมต่อ getway ปลายทางได้\rกรุณาลองใหม่อีกครั้ง'
        : 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง';

    return e.response?.data?['message']['th'] ?? message;
  }

  void showDialogError(String v) {
    dialogUtils.showDialogCustomIcon(
      actionWithContent: true,
      description: Text(
        v,
        style: TextStyle(
          color: Colors.black87,
          fontSize: 15.sm,
        ),
        textAlign: TextAlign.center,
      ),
      actions: [
        SizedBox(
          width: Get.size.width,
          child: ButtonWidgets.closeButtonOutline(
            closeOverlays: true,
          ),
        ),
      ],
    );
  }

  Future<List<JobLocationEntry>?> getCountSS(
      String jobNo, String? lat, String? long) async {
    if (lat == null && long == null) return null;

    var qDetails = (db.select(db.jobLocationEntries).join([
      d.innerJoin(
        db.jobDetailEntries,
        db.jobDetailEntries.id.equalsExp(db.jobLocationEntries.jobDetailId),
        useColumns: false,
      )
    ])
      ..where(db.jobDetailEntries.jobNo.equals(jobNo) &
          db.jobDetailEntries.assignmentStatus.isIn(['START', 'FINISH']) &
          db.jobDetailEntries.assignmentStartDt.isNotNull() &
          db.jobDetailEntries.assignmentTypeCode
              .equals(activeLocation!.jobDetail!.assignmentTypeCode!)));

    List<JobLocationEntry> list = [];
    list = await qDetails.map((e) {
      var lo = e.readTable(db.jobLocationEntries);

      return lo;
    }).get();

    var delPoint = list
        .where((e) => e.geoLatitude == lat && e.geoLongitude == long)
        .toList();

    List<JobLocationEntry> list2 = [];

    if (activeLocation?.deliveryFlag == 'Y') {
      for (var e in delPoint) {
        list2.addAll(list.where((x) => x.jobDetailId == e.jobDetailId));
      }
      list2 = list2.where((x) => x.pickupFlag == 'Y').toList();
    }

    return list2;
  }

  Stream<List<ActivityStep>> initWidgetStatusStreamList() {
    if (listOfData.isNotEmpty) {
      activeLocation = listOfData.first;
    }
    return (db.jobLocationEntries.select()
          ..where((x) =>
              x.id.equals(activeLocation!.id) &
              x.jobNo.equals(activeLocation!.jobNo!))
          ..limit(1))
        .watch()
        .map((rows) {
      List<ActivityStep> oo = [];
      for (var x in rows) {
        oo.add(
          ActivityStep(
            icon: const Icon(Icons.download),
            text: 'ถึง',
            subTitle: buildTextDate(x.jobArrivedDt, 0),
            onTab: () async {
              await onConfirmCheckLocation(
                reqStepValue: 0,
                onTab: () async {
                  await onTabStep(0);
                  GLFunc.showSnackbar(
                    message: 'บันทึกเวลาแล้ว',
                    showIsEasyLoading: true,
                    type: SnackType.SUCCESS,
                  );
                },
                description: 'บันทึกเวลาถึง ใช่หรือไม่?',
              );
            },
          ),
        );

        var dataBind = [
          ActivityStep(
            icon: const Icon(Icons.upload),
            text: x.deliveryFlag == 'Y' ? 'ลง' : 'ขึ้น',
            onTab: () async {
              await onConfirmCheckLocation(
                reqStepValue: 1,
                onTab: () async {
                  await onTabStep(1);
                  GLFunc.showSnackbar(
                    message: 'บันทึกเวลาแล้ว',
                    showIsEasyLoading: true,
                    type: SnackType.SUCCESS,
                  );
                },
                description:
                    'บันทึกเวลา ${x.deliveryFlag == 'Y' ? 'ลง' : 'ขึ้น'} ใช่หรือไม่?',
              );
            },
            subTitle: buildTextDate(x.jobLoadingDt, 1),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [],
            ),
          ),
          ActivityStep(
              icon: const Icon(Icons.check),
              text: 'เสร็จ',
              subTitle: buildTextDate(x.jobFinishedDt, 2),
              onTab: () async {
                bool? isOk = true;
                var getJobTime =
                    await db.getJobHeadersSingle(jobNo: activeLocation!.jobNo!);

                if (getJobTime!.jobFingerScanFlag == "Y" &&
                    getJobTime.vehicleDeptTypeCode == "LH") {
                  try {
                    GLFunc.instance.showLoading('กำลังตรวจสอบการสแกนเวลา');

                    var getJobCheck = await JobRepository()
                        .getCheckFingerScan(getJobTime.jobNo);
                    var empScan = List.from(getJobCheck?.results ?? []);
                    bool isNotScan = empScan.any((x) => x['scanFlag'] == 'N');
                    if (empScan.isNotEmpty && isNotScan) {
                      isOk =
                          await dialogFingerScan(getJobTime.jobNo, !isNotScan);
                      await onTabStep(
                        2,
                        skipFingerScanFlag: isOk == true ? 'Y' : 'N',
                      );
                      // //print("---> $isOk");
                      return;
                    }
                  } finally {}
                }

                await onConfirmCheckLocation(
                  reqStepValue: 2,
                  onTab: () async {
                    await onTabStep(
                      2,
                      skipFingerScanFlag: isOk == true ? 'Y' : 'N',
                    );
                    GLFunc.showSnackbar(
                      message: 'บันทึกเวลาแล้ว',
                      showIsEasyLoading: true,
                      type: SnackType.SUCCESS,
                    );
                  },
                  description: 'บันทึกเวลาออก ใช่หรือไม่?',
                );
              },
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [],
              )),
          ActivityStep(
            icon: const Icon(Icons.exit_to_app),
            text: 'ออก',
            subTitle: buildTextDate(x.jobLeavedDt, 3),
            onTab: () async {
              await onConfirmCheckLocation(
                reqStepValue: 3,
                onTab: () async {
                  await onTabStep(3);
                  GLFunc.showSnackbar(
                    message: 'บันทึกเวลาแล้ว',
                    showIsEasyLoading: true,
                    type: SnackType.SUCCESS,
                  );
                },
                description: 'บันทึกเวลาออก ใช่หรือไม่?',
              );

              GLFunc.showSnackbar(
                message: 'ระบบจะแจ้งให้ทราบภายหลัง',
                showIsEasyLoading: true,
                duration: const Duration(seconds: 3),
              );
            },
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [],
            ),
          ),
        ];

        oo.addAll(dataBind);
      }

      return oo;
    });
  }

  Future<void> onTabStep(
    int initStep, {
    LatLng? putLocation,
    Map<String, dynamic>? exception,
    bool onClosePage = false,
    String skipFingerScanFlag = 'N',
  }) async {
    Position? geoLocation;

    if (getCurrent?.latitude == null) {
      getCurrent = await locationService.getLocation();
    }

    geoLocation = getCurrent;

    var fcmToken = BoxCacheUtil.getFCMToken;
    var vehicle = BoxCacheUtil.getVehicle;

    String? createDt;
    Map<String, dynamic> mapColumnToUpdate = {};

    isStepToggle(true);
    var getLocations = await AppDatabase.provider
        .getJobLocations(jobNo: activeLocation!.jobNo!);

    var getLocationByRow =
        getLocations?.firstWhereOrNull((e) => e.id == activeLocation!.id);

    var locationModel = getLocationByRow;

    DateTime? currentDt = DateTime.now();

    switch (initStep) {
      case 0:
        var newData = locationModel?.copyWith(
          jobArrivedDt: currentDt.toIso8601String(),
          jobArrivedLatitude: geoLocation?.latitude.toString(),
          jobArrivedLongitude: geoLocation?.longitude.toString(),
        );

        mapColumnToUpdate.addAll({
          'jobArrivedDt': currentDt.toIso8601String(),
          'jobArrivedLatitude': geoLocation?.latitude.toString(),
          'jobArrivedLongitude': geoLocation?.longitude.toString(),
        });

        createDt = newData?.jobArrivedDt.toString();
        getLocationByRow = newData!;

        break;
      case 1:
        var newData = locationModel?.copyWith(
          jobLoadingDt: currentDt.toIso8601String(),
          jobLoadingLatitude: geoLocation?.latitude.toString(),
          jobLoadingLongitude: geoLocation?.longitude.toString(),
        );
        mapColumnToUpdate.addAll({
          'jobLoadingDt': currentDt.toIso8601String(),
          'jobLoadingLatitude': geoLocation?.latitude.toString(),
          'jobLoadingLongitude': geoLocation?.longitude.toString(),
        });

        createDt = newData?.jobLoadingDt.toString();
        getLocationByRow = newData!;

        break;
      case 2:
        var newData = locationModel?.copyWith(
          jobFinishedDt: currentDt.toIso8601String(),
          jobFinishedLatitude: geoLocation?.latitude.toString(),
          jobFinishedLongitude: geoLocation?.longitude.toString(),
        );
        mapColumnToUpdate.addAll({
          'jobFinishedDt': currentDt.toIso8601String(),
          'jobFinishedLatitude': geoLocation?.latitude.toString(),
          'jobFinishedLongitude': geoLocation?.longitude.toString(),
        });
        getLocationByRow = newData!;

        if (!GetUtils.isNullOrBlank(totalNotLabel.text)!) {
          getLocationByRow.actManualPackage =
              int.tryParse(totalNotLabel.text) ?? 0;

          getLocationByRow.actScanPackage = int.tryParse(totalScan.text) ?? 0;
          getLocationByRow.actPackage = (getLocationByRow.actScanPackage ?? 0) +
              (getLocationByRow.actManualPackage ?? 0);
        }
        createDt = newData.jobFinishedDt.toString();
        BackgroundJobServices().jobScheduledsX();
        break;
      case 3:
        var newData = locationModel?.copyWith(
          jobLeavedDt: currentDt.toIso8601String(),
          jobLeavedLatitude: geoLocation?.latitude.toString(),
          jobLeavedLongitude: geoLocation?.longitude.toString(),
        );

        mapColumnToUpdate.addAll({
          'jobLeavedDt': currentDt.toIso8601String(),
          'jobLeavedLatitude': geoLocation?.latitude.toString(),
          'jobLeavedLongitude': geoLocation?.longitude.toString(),
        });

        getLocationByRow = newData!;
        createDt = newData.jobLeavedDt.toString();
        BackgroundJobServices().jobScheduledsX();
        break;
      case -1:
        var newData = locationModel?.copyWith(
          lastExceptionCode: exception?['exceptionCode'],
          lastExceptionId: exception?['id'],
          lastExceptionRemark: exception?['exceptionTHDesc'],
        );

        mapColumnToUpdate.addAll({
          'lastExceptionCode': exception?['exceptionCode'],
          'lastExceptionId': exception?['id'],
          'lastExceptionRemark': exception?['exceptionTHDesc'],
        });

        getLocationByRow = newData!;
        createDt = DateTime.now().toIso8601String();

        break;
      default:
    }
    if (initStep != -1) {
      if (widgetStatus.isNotEmpty) {
        widgetStatus[initStep].subTitle =
            Text(dateUtils.formattedDate(currentDt, 'dd/MM/yyyy HH:mm'));
      }
    }

    var dataToUpdate = JobLocationEntry.fromJson(getLocationByRow!.toMap());

    var mapData = JobUpdateLocation(
      id: activeLocation!.id,
      jobDetailId: activeLocation!.jobDetailId!,
      geoLatitude: geoLocation?.latitude.toString(),
      geoLongitude: geoLocation?.longitude.toString(),
      actManualPackage: int.tryParse(totalNotLabel.text),
      batteryPercent: await batteryService.getBattery(),
      createdDt: createDt,
      actPackage: int.tryParse(totalScan.text),
      type: initStep != -1
          ? toBeginningOfSentenceCase(
              ['Arrived', 'Loading', 'Finished', 'Leaved'][initStep])
          : 'FAILED',
      fcmToken: fcmToken,
      exceptionId: getLocationByRow.lastExceptionId,
      exceptionCode: getLocationByRow.lastExceptionCode,
      exceptionRemark: getLocationByRow.lastExceptionRemark,
      deliveryFlag: getLocationByRow.deliveryFlag,
      vSubContractFlag: vehicle?.vehicleSupplierFlag,
      licensePlate: vehicle?.licensePlate,
      licenseProvince: vehicle?.licenseProvince,
      skipFingerScanFlag: skipFingerScanFlag,
    );

    var jobEntry = JobSchedulerEntriesCompanion.insert(
      url: mapData.type!,
      activityType: d.Value(mapData.type?.toUpperCase()),
      request: d.Value(mapData.toJson()),
      syncFlag: const d.Value('N'),
      createBy: d.Value(auth!.userName),
      createDt: d.Value(DateTime.now().toIso8601String()),
      counter: const d.Value(0),
    );

    // try {
    // if (await GLFunc.isClientOnline() ) {
    //   await Future.delayed(const Duration(milliseconds: 200));
    //   await JobRepository().updateLocation(mapData).then((value) {
    //     jobEntry = jobEntry.copyWith(
    //       syncFlag: const d.Value('Y'),
    //       statusCode: const d.Value('200'),
    //       response:
    //           value != null ? d.Value(json.encode(value.toJson())) : null,
    //     );
    //   });
    // }
    // } catch (e) {
    //   jobEntry = jobEntry.copyWith(
    //     syncFlag: const d.Value('E'),
    //     statusCode: const d.Value('500'),
    //     response: d.Value(e.toString()),
    //   );
    // } finally {
    //   if (jobEntry.syncFlag.value != 'Y') {
    //     await db.jobSchedulerEntries.insertOne(jobEntry);
    //   }
    // }

    if (jobEntry.syncFlag.value != 'Y') {
      await db.jobSchedulerEntries.insertOne(jobEntry);
    }

    List<JobDetailEntry> bindDetailToUpdate = [];

    var findDetaill = await (db.jobDetailEntries.select()
          ..where((x) =>
              x.jobNo.equals(getLocationByRow!.jobNo!) &
              x.assignmentStatus.isIn(['START', 'FINISH']) &
              x.assignmentStartDt.isNotNull()))
        .get();

    bindDetailToUpdate = findDetaill
        .where((x) => x.id == getLocationByRow!.jobDetailId)
        .toList();

    var locationByDetailAll = await (db.jobLocationEntries.select()
          ..where((x) => x.jobNo.equals(getLocationByRow!.jobNo!)))
        .get();

    List<JobDetailEntry> listDetailToEq = [];

    if (!GetUtils.isNullOrBlank(getLocationByRow.geoLatitude)! &&
        !GetUtils.isNullOrBlank(getLocationByRow.geoLongitude)!) {
      var mapIds = findDetaill.map((e) => e.id!.toDouble()).toList();

      var locationByDetail = locationByDetailAll
          .where((x) => mapIds.contains(x.jobDetailId))
          .toList();

      List<JobLocationEntry> locationDelivery = [];

      var detailToUpdate = findDetaill
          .where((x) => x.id != getLocationByRow!.jobDetailId)
          .toList();

      for (var detail in (detailToUpdate)) {
        //เช็คงานรับ ที่จุดส่งเดียวกันและ จุดรับเสร็จแล้ว
        List<JobLocationEntry> listOfByPickupSuccess = [];
        if (detail.assignmentTypeCode == 'RECEIVE') {
          var locationPickup = locationByDetail
              .where((e) =>
                  e.jobDetailId == detail.id &&
                  e.pickupFlag == 'Y' &&
                  e.jobArrivedDt != null &&
                  e.jobLoadingDt != null &&
                  e.jobFinishedDt != null &&
                  e.jobLeavedDt != null)
              .toList();
          if (locationPickup.isNotEmpty) {
            listOfByPickupSuccess = locationByDetail
                .where((x) =>
                    x.jobDetailId == detail.id &&
                    x.deliveryFlag == 'Y' &&
                    x.jobArrivedDt == null &&
                    x.jobLoadingDt == null &&
                    x.jobFinishedDt == null &&
                    x.jobLeavedDt == null &&
                    x.geoLatitude == getLocationByRow?.geoLatitude &&
                    x.geoLongitude == getLocationByRow?.geoLongitude)
                .toList();
          }
        } else {
          listOfByPickupSuccess = locationByDetail
              .where((x) =>
                  x.jobDetailId == detail.id &&
                  x.pickupFlag == 'Y' &&
                  x.jobArrivedDt == null &&
                  x.jobLoadingDt == null &&
                  x.jobFinishedDt == null &&
                  x.jobLeavedDt == null &&
                  x.geoLatitude == getLocationByRow?.geoLatitude &&
                  x.geoLongitude == getLocationByRow?.geoLongitude)
              .toList();
        }

        // var listOfByPickupSuccess = locationByDetail
        //     .where((x) =>
        //         x.jobDetailId == detail.id &&
        //             x.pickupFlag == 'Y' &&
        //             x.jobArrivedDt == null &&
        //             x.jobLoadingDt == null &&
        //             x.jobFinishedDt == null &&
        //             x.jobLeavedDt == null ||
        //         x.lastExceptionCode == null)
        //     .toList();

        // if (getLocationByRow.deliveryFlag == 'Y') {
        //   listOfByPickupSuccess = listOfByPickupSuccess
        //       .where((x) =>
        //           x.pickupFlag == 'Y' &&
        //               x.jobDetailId == detail.id &&
        //               x.jobArrivedDt != null &&
        //               x.jobLoadingDt != null &&
        //               x.jobFinishedDt != null &&
        //               x.jobLeavedDt != null ||
        //           x.lastExceptionCode != null)
        //       .toList();
        // }

        // List<JobLocationEntry> listDeliveryToUpdate = [];
        if (listOfByPickupSuccess.isNotEmpty) {
          // listDeliveryToUpdate = locationByDetail
          //     .where((x) =>
          //         x.pickupFlag == 'Y' &&
          //         x.geoLongitude == getLocationByRow!.geoLongitude &&
          //         x.geoLatitude == getLocationByRow.geoLatitude!)
          //     .toList();

          // if (getLocationByRow.deliveryFlag == 'Y') {
          //   switch (initStep) {
          //     case 0:
          //       listDeliveryToUpdate = locationByDetail
          //           .where((x) => (x.deliveryFlag == 'Y' &&
          //               x.geoLongitude == getLocationByRow!.geoLongitude &&
          //               x.geoLatitude == getLocationByRow.geoLatitude! &&
          //               x.jobArrivedDt == null &&
          //               x.jobLoadingDt == null &&
          //               x.jobFinishedDt == null &&
          //               x.jobLeavedDt == null))
          //           .toList();
          //       //print(listDeliveryToUpdate);
          //       break;
          //     case 1:
          //       listDeliveryToUpdate = locationByDetail
          //           .where((x) =>
          //               x.deliveryFlag == 'Y' &&
          //               x.geoLongitude == getLocationByRow!.geoLongitude &&
          //               x.geoLatitude == getLocationByRow.geoLatitude! &&
          //               x.jobLoadingDt == null &&
          //               x.jobFinishedDt == null &&
          //               x.jobLeavedDt == null &&
          //               x.jobArrivedDt != null)
          //           .toList();
          //       //print(listDeliveryToUpdate);
          //       break;
          //     case 2:
          //       listDeliveryToUpdate = locationByDetail
          //           .where((x) =>
          //               x.deliveryFlag == 'Y' &&
          //               x.geoLongitude == getLocationByRow!.geoLongitude &&
          //               x.geoLatitude == getLocationByRow.geoLatitude! &&
          //               x.jobFinishedDt == null &&
          //               x.jobLeavedDt == null &&
          //               x.jobLoadingDt != null &&
          //               x.jobArrivedDt != null)
          //           .toList();
          //       //print(listDeliveryToUpdate);
          //       break;
          //     case 3:
          //       listDeliveryToUpdate = locationByDetail
          //           .where((x) =>
          //               x.deliveryFlag == 'Y' &&
          //               x.geoLongitude == getLocationByRow!.geoLongitude &&
          //               x.geoLatitude == getLocationByRow.geoLatitude! &&
          //               x.jobLeavedDt == null &&
          //               x.jobFinishedDt != null &&
          //               x.jobLoadingDt != null &&
          //               x.jobArrivedDt != null)
          //           .toList();
          //       //print(listDeliveryToUpdate);
          //       break;
          //     default:
          //   }
          // }

          // if (listDeliveryToUpdate.first.pickupFlag == "Y") {
          //   var pickupOnlyUpdate = listDeliveryToUpdate
          //       .where((e) => e.jobDetailId == mapData.jobDetailId)
          //       .toList();
          //   listDeliveryToUpdate = pickupOnlyUpdate;
          // }

          for (var l in listOfByPickupSuccess) {
            l = l.copyWith(
              jobArrivedDt: d.Value(getLocationByRow.jobArrivedDt),
              jobArrivedLatitude: d.Value(getLocationByRow.jobArrivedLatitude),
              jobArrivedLongitude:
                  d.Value(getLocationByRow.jobArrivedLongitude),
              // ============================>
              jobLoadingDt: d.Value(getLocationByRow.jobLoadingDt),
              jobLoadingLatitude: d.Value(getLocationByRow.jobLoadingLatitude),
              jobLoadingLongitude:
                  d.Value(getLocationByRow.jobLoadingLongitude),
              // ============================>
              jobFinishedDt: d.Value(getLocationByRow.jobFinishedDt),
              jobFinishedLatitude:
                  d.Value(getLocationByRow.jobFinishedLatitude),
              jobFinishedLongitude:
                  d.Value(getLocationByRow.jobFinishedLongitude),
              // ============================>
              jobLeavedDt: d.Value(getLocationByRow.jobLeavedDt),
              jobLeavedLatitude: d.Value(getLocationByRow.jobLeavedLatitude),
              jobLeavedLongitude: d.Value(getLocationByRow.jobLeavedLongitude),
              // lastExceptionCode: d.Value(getLocationByRow.lastExceptionCode),
              // lastExceptionId: d.Value(getLocationByRow.lastExceptionId),
              // lastExceptionRemark:
              //     d.Value(getLocationByRow.lastExceptionRemark),
            );

            locationDelivery.add(l);
          }
        }

        if (initStep == 3 &&
            activeLocation?.deliveryFlag == 'Y' &&
            locationByDetail.where((x) => x.jobDetailId == detail.id).length ==
                1) {
          var mapToClass = JobDetail.fromMap(detail.toJson());
          mapToClass = mapToClass.copyWith(
            finishFlag: 'Y',
            assignmentStatus: 'FINISH',
          );
          listDetailToEq.add(JobDetailEntry.fromJson(mapToClass.toMap()));
        } else if (activeLocation?.deliveryFlag == 'Y' &&
            activeLocation?.jobDetail?.assignmentTypeCode == 'RECEIVE') {
          var mapToClass = JobDetail.fromMap(detail.toJson());
          mapToClass = mapToClass.copyWith(
            finishFlag: 'Y',
            assignmentStatus: 'FINISH',
          );
          listDetailToEq.add(JobDetailEntry.fromJson(mapToClass.toMap()));
        }
      }

      if (activeLocation?.deliveryFlag == 'Y' &&
          activeLocation?.jobDetail?.assignmentTypeCode == 'RECEIVE') {
        for (var xDetail in bindDetailToUpdate) {
          var mapToClass = JobDetail.fromMap(xDetail.toJson());
          mapToClass = mapToClass.copyWith(
            finishFlag: 'Y',
            assignmentStatus: 'FINISH',
          );
          listDetailToEq.add(JobDetailEntry.fromJson(mapToClass.toMap()));
        }
      } else {}

      locationDelivery.add(dataToUpdate);

      if (locationDelivery.isNotEmpty) {
        await db.bulkUpdate(db.jobLocationEntries, locationDelivery);
      }
    } else {}

    await db.updateTable(db.jobLocationEntries, dataToUpdate);

    if (activeLocation?.deliveryFlag == 'Y') {
      locationByDetailAll = await (db.jobLocationEntries.select()
            ..where((x) => x.jobNo.equals(getLocationByRow!.jobNo!)))
          .get();

      for (var jDetail in findDetaill) {
        var locationByDetail = locationByDetailAll
            .where((x) => x.jobDetailId == jDetail.id)
            .toList();

        int counterPickup =
            locationByDetail.where((x) => x.deliveryFlag == 'Y').length;
        int counterPickupSuccess = locationByDetail
            .where((x) =>
                x.deliveryFlag == 'Y' &&
                    x.jobArrivedDt != null &&
                    x.jobLoadingDt != null &&
                    x.jobLeavedDt != null &&
                    x.jobFinishedDt != null ||
                x.lastExceptionCode != null)
            .length;

        if (activeLocation?.jobDetail?.assignmentTypeCode == 'RECEIVE') {
          counterPickupSuccess = locationByDetail
              .where((x) =>
                  x.deliveryFlag == 'Y' && x.jobArrivedDt != null ||
                  x.lastExceptionCode != null)
              .length;
        }

        if (counterPickupSuccess > 0 && counterPickupSuccess == counterPickup) {
          var mapToClass = JobDetail.fromMap(jDetail.toJson());
          mapToClass = mapToClass.copyWith(
            finishFlag: 'Y',
            assignmentStatus: 'FINISH',
          );

          var countDel =
              locationByDetail.where((x) => x.deliveryFlag == 'Y').length;
          var countDelSuccess = locationByDetail
              .where((x) =>
                  x.deliveryFlag == 'Y' &&
                      x.jobArrivedDt != null &&
                      x.jobLoadingDt != null &&
                      x.jobFinishedDt != null &&
                      x.jobLeavedDt != null ||
                  x.lastExceptionCode != null &&
                      x.jobFinishedLatitude != null &&
                      x.jobArrivedLongitude != null)
              .length;

          if (countDel == countDelSuccess) {
            listDetailToEq.add(JobDetailEntry.fromJson(mapToClass.toMap()));
          }
        }
      }
    }

    bindDetailToUpdate = listDetailToEq;

    step = RxInt(initStep);
    await db.bulkUpdate(db.jobDetailEntries, bindDetailToUpdate);
    if (initStep == 3) {
      await Future.delayed(const Duration(milliseconds: 100)).then((_) {
        Get.back(canPop: false);
      });
    }

    isStepToggle(false);

    GLFunc.instance.hideLoading();
    update();
  }

  Future<void> removeFile(i, [bool isSignature = false]) async {
    isToggleFile(true);
    if (!isSignature) {
      var getImeage = receiveMapData.images[i];
      receiveMapData.images.removeAt(i);

      ((db.fileDocumentEntries))
          .deleteWhere((t) => t.path.equals(getImeage.path));

      try {
        getImeage.deleteSync();
      } finally {}
    } else {
      receiveMapData = receiveMapData.copyWith(signature: null);
    }
    isToggleFile(false);
  }

  Future<void> uploadSignature(JobLocation data) async {
    var user = BoxCacheUtil.getAuthUser;

    if (receiveMapData.signature == null) return;

    if (receiveMapData.signature != null) {
      var jobLocations = await db.getJobLocations(
        jobNo: data.jobNo!,
        id: data.id,
      );

      var firstById = jobLocations?.first;

      String name =
          'SIGNATURE-${data.deliveryFlag == 'Y' ? 'DELIVERY' : 'PICKUP'}-JOB-${data.jobNo}.jpg';
      firstById = firstById?.copyWith(
        signatueName: consigneeName.text,
      );

      var res = await GLFunc.instance.saveFileOnDisk(
        receiveMapData.signature!,
        name,
        'signatures',
      );

      var getFiles = (await db.getFileDocuments(
              refNo: data.jobNo!, docType: 'SIGNATURE', locationId: data.id))
          .where((e) => e.syncFlag == 'Y')
          .toList();

      getFiles.sort((a, b) => b.createDt.compareTo(a.createDt));

      var fileDoc = FileDocumentEntriesCompanion.insert(
        name: name,
        path: res,
        rawFile: File(res).readAsBytesSync(),
        referance: data.jobNo!,
        documentType: 'SIGNATURE',
        createDt: DateTime.now().toIso8601String(),
        syncDate: DateTime.now().toIso8601String(),
        syncFlag: const d.Value('N'),
        jobLocationId: d.Value(data.id),
        userId: d.Value(user!.id!),
      );

      var resId = await db.fileDocumentEntries.insertOne(fileDoc);

      var logData = GLFunc.instance.jEncode({
        'signatueName': firstById?.signatueName,
        'locationId': data.id,
        'jobNo': data.jobNo,
        'fileDocuemnt': {
          'id': resId,
          'path': fileDoc.path.value,
          'documentType': fileDoc.documentType.value,
        }
      });

      firstById = firstById?.copyWith(
        signatureFileId: resId.toDouble(),
      );

      fileDoc = fileDoc.copyWith(
        id: d.Value(resId),
      );

      var jobEntry = JobSchedulerEntriesCompanion.insert(
        url: '',
        activityType: const d.Value('FINISHED.SIGN'),
        request: d.Value(logData),
        syncFlag: const d.Value('N'),
        createBy: d.Value(user.userName),
        createDt: d.Value(DateTime.now().toIso8601String()),
        counter: const d.Value(0),
      );

      await db.jobSchedulerEntries.insertOne(jobEntry);

      db.updateTable(
          db.jobLocationEntries, JobLocationEntry.fromJson(firstById!.toMap()));

      db.batchActionEntries(
        action: SqlAction.INSERRT_CF_UPDATE,
        table: db.fileDocumentEntries,
        entitys: [fileDoc],
      );
    }
  }

  Future<void> uploadImages(JobLocation data) async {
    var user = BoxCacheUtil.getAuthUser;
    if (receiveMapData.images.isNotEmpty) {
      // List<int> fileIds = [];

      var itemAll = receiveMapData.images;

      if (itemAll.isNotEmpty) {
        List<FileDocumentEntriesCompanion> fileDocs = [];
        await db.fileDocumentEntries.deleteWhere(
          (x) =>
              x.referance.equals(data.jobNo!) &
              x.name.equals('RECEIVE') &
              x.jobLocationId.equals(data.id),
        );
        for (var i = 0; i < itemAll.length; i++) {
          var bFile = itemAll[i];

          String name = '${data.jobNo!}-${(i + 1)}.jpg';

          var savePath = await GLFunc.instance.saveFileOnDisk(
            bFile.readAsBytesSync(),
            name,
            'receives/${data.deliveryFlag == 'Y' ? 'DELIVERY' : 'PICKUP'}/${data.jobNo!}',
          );

          var fileDoc = FileDocumentEntriesCompanion.insert(
            name: name,
            path: savePath,
            rawFile: File(savePath).readAsBytesSync(),
            referance: data.jobNo!,
            documentType: 'RECEIVE',
            createDt: DateTime.now().toIso8601String(),
            syncDate: DateTime.now().toIso8601String(),
            syncFlag: const d.Value('N'),
            jobLocationId: d.Value(data.id),
            userId: d.Value(user!.id!),
          );

          fileDocs.add(fileDoc);
        }

        try {
          if (await GLFunc.isClientOnline() && 1 == 2) {
            var images = receiveMapData.images.map((e) => e.path).toList();
            var resUploadImage =
                await JobRepository().uploadPackageScanImageByLocationId(
              data.id,
              images,
            );

            for (var e in fileDocs) {
              e = e.copyWith(
                syncDate: d.Value(DateTime.now().toIso8601String()),
                syncFlag: const d.Value('Y'),
              );
            }
          }

          //print('upload uploadPackageScanImageByLocationId success');
        } catch (err) {
          for (var e in fileDocs) {
            e = e.copyWith(
              syncDate: d.Value(DateTime.now().toIso8601String()),
              syncFlag: const d.Value('E'),
            );
          }
        } finally {
          if (fileDocs.isNotEmpty) {
            var jobEntry = JobSchedulerEntriesCompanion.insert(
              url: '',
              activityType: const d.Value('FINISHED.IMAGES'),
              request: d.Value(GLFunc.instance.jEncode({
                'id': data.id,
                'paths': fileDocs.map((e) => e.path.value).toList(),
              })),
              syncFlag: const d.Value('N'),
              createBy: d.Value(user!.userName),
              createDt: d.Value(DateTime.now().toIso8601String()),
              counter: const d.Value(0),
            );
            await db.jobSchedulerEntries.insertOne(jobEntry);
          }

          db.batchActionEntries(
            action: SqlAction.INSERRT_CF_UPDATE,
            table: db.fileDocumentEntries,
            entitys: fileDocs,
          );
        }
      }
    }
  }

  Future<void> getPackageScan() async {
    var fileByJob = await db.getFileDocuments(
      refNo: activeLocation!.jobNo!,
    );

    var getImgSignature = fileByJob.firstWhereOrNull(
      (e) =>
          e.documentType == 'SIGNATURE' &&
          e.jobLocationId == activeLocation?.id,
    );

    var fileOfSystem = fileByJob
        .where((e) =>
            e.documentType == 'RECEIVE' &&
            e.jobLocationId == activeLocation?.id)
        .map((e) => File(e.path))
        .toList();

    var getPackageScan = await db.jobPackageScan(
      jobNo: activeLocation!.jobNo,
      locationId: activeLocation!.id,
    );
    getPackageScan = getPackageScan?.where((e) => e.syncFlag == 'P').toList();

    if (activeLocation!.pickupFlag == 'N' ||
        activeLocation!.pickupFlag == 'Y') {
      var locations = await db.getJobLocations(
        jobNo: activeLocation!.jobNo!,
        id: activeLocation!.pickupFlag == 'N' ? null : activeLocation!.id,
      );

      var listPickup = locations?.where((e) => e.pickupFlag == 'Y').toList();

      var actPackage = listPickup?.map((e) => (e.actPackage ?? 0)).sum;

      var mapManual =
          listPickup?.map((e) => (e.actManualPackage)).toList() ?? [];
      int? sumNotLabel;
      if (mapManual.any((e) => e != null)) {
        sumNotLabel = mapManual.map((e) => (e ?? 0)).sum;
      }

      receiveMapData = receiveMapData.copyWith(
        totalPackageScan: actPackage,
        jobNo: activeLocation!.jobNo,
        totalPckageNotLabel: sumNotLabel,
      );
    } else {
      getPackageScan ??= [];
      if (getPackageScan.isNotEmpty) {
        var firstScan = PackageScanForm.fromJson(getPackageScan.first.rawData!);
        receiveMapData = receiveMapData.copyWith(
          totalPackageScan: firstScan.actPackage,
          jobNo: firstScan.jobNo,
          totalPckageNotLabel: firstScan.actManualPackage,
        );
      }
    }

    receiveMapData = receiveMapData.copyWith(
      signature: null,
      signaturePoint: [],
      images: fileOfSystem.isNotEmpty ? fileOfSystem : receiveMapData.images,
      packages: listOfScanPackage,
    );
  }

  void watchPackageScanLocation() {
    _listOfScanPackage.bindStream(db.watchJobPackageScan(
      jobNo: activeLocation?.jobNo,
      locationId: activeLocation?.id,
    ));
  }

  // void removeQrCode(int i, [String? code, int flag = 0]) async {
  //   if (isScanManifest.isTrue && flag == 1) {
  //     var getpack = await (db.jobPackageScanEntries.select()
  //           ..where((x) => x.id.equals(i)))
  //         .getSingleOrNull();
  //     if (getpack != null) {
  //       getpack = getpack.copyWith(
  //         syncFlag: const d.Value('M'),
  //         message: const d.Value('Manifest scan data'),
  //         locationId: d.Value(activeLocation!.id),
  //         rawData: const d.Value('MANIFEST'),
  //       );
  //       db.updateTable(db.jobPackageScanEntries, getpack);
  //     }
  //   } else {
  //     await db.jobPackageScanEntries.deleteWhere((x) => x.id.equals(i));
  //     if (listOfScanPackage.isEmpty) {
  //       manifestPackageScan.clear();
  //     }

  //     update();
  //   }
  // }

  // void addQRCode(
  //   String v, {
  //   bool save = false,
  //   bool isScan = true,
  //   bool isManifest = false,
  //   String? referance,
  // }) async {
  //   var auth = BoxCacheUtil.getAuthUser;

  //   if (isManifest) {
  //     var mapDataManifest = JobPackageScanEntriesCompanion.insert(
  //       code: v,
  //       jobNo: activeLocation!.jobNo!,
  //       createDt: DateTime.now().toIso8601String(),
  //       createBy: d.Value(auth!.userEnName),
  //       message: const d.Value('Manifest scan data'),
  //       locationId: d.Value(activeLocation!.id),
  //       syncFlag: const d.Value('M'),
  //       ref1: d.Value(referance),
  //       rawData: const d.Value('MANIFEST'),
  //     );

  //     await db.jobPackageScanEntries.insertOnConflictUpdate(mapDataManifest);

  //     return;
  //   }
  //   var listBarCode = v.split(" ");
  //   if (listBarCode.length != 5) {
  //     EasyLoading.showError('ขออภัย รูปแบบ QR Code / Barcode ไม่ถูกต้อง');
  //     return;
  //   }

  //   var getLastQR = await ((db.jobPackageScanEntries.select())
  //         ..where((t) => t.code.contains(v)))
  //       .getSingleOrNull();

  //   if (getLastQR != null && !save) {
  //     if (getLastQR.syncFlag == 'P') {
  //       aSound.paySound(SOUND.dup);
  //       GLFunc.showSnackbar(
  //         message: 'คุณได้สแกนรหัสนี้: $v แล้ว',
  //         showIsEasyLoading: true,
  //         type: SnackType.WARNING,
  //       );
  //       return;
  //     }

  //     getLastQR = getLastQR.copyWith(
  //       jobNo: activeLocation!.jobNo!,
  //       createDt: DateTime.now().toIso8601String(),
  //       createBy: d.Value(auth!.userEnName),
  //       message: const d.Value('SACN IN PACKAGE'),
  //       locationId: d.Value(activeLocation!.id),
  //       syncFlag: const d.Value('P'),
  //     );
  //     db.jobPackageScanEntries.insertOnConflictUpdate(getLastQR);
  //     return;
  //   }

  //   if (getLastQR == null && isScan) {
  //     if (!save) {
  //       var listSounds = [
  //         SOUND.ok1,
  //         SOUND.ok2,
  //         SOUND.ok3,
  //         SOUND.ok4,
  //         SOUND.ok5,
  //         SOUND.ok6,
  //         SOUND.ok7,
  //         SOUND.ok8,
  //         SOUND.ok9,
  //         SOUND.ok10,
  //       ];
  //       int idx = Random().nextInt(listSounds.length);
  //       SOUND soundRan = listSounds[idx];
  //       aSound.paySound(soundRan);
  //     }
  //     await db.jobPackageScanEntries.insertOne(
  //       JobPackageScanEntriesCompanion.insert(
  //         code: v,
  //         jobNo: activeLocation!.jobNo!,
  //         createDt: DateTime.now().toIso8601String(),
  //         createBy: d.Value(auth!.userEnName),
  //         message: const d.Value('SACN IN PACKAGE'),
  //         locationId: d.Value(activeLocation!.id),
  //         syncFlag: const d.Value('P'),
  //       ),
  //     );

  //     if (save) saveQR(v);
  //     update();
  //   }
  // }

  Future<void> putScanPackage({required JobLocation jobLocation}) async {
    // GLFunc.instance.showLoading('กำลังบันทึกรายการ');

    int actPackage = 0;
    int actScanPackage = 0;
    int actManualPackage = 0;

    var user = BoxCacheUtil.getAuthUser;
    var vehicle = BoxCacheUtil.getVehicle;
    var getCurrent = await locationService.getLocation();

    var getQrAll = await ((db.jobPackageScanEntries.select())
          ..where((t) =>
              t.jobNo.equals(jobLocation.jobNo!) &
              t.locationId.equals(jobLocation.id) &
              t.syncFlag.equals("P")))
        .get();

    var getLocation = await ((db.jobLocationEntries.select())
          ..where((t) => t.id.equals(jobLocation.id)))
        .getSingleOrNull();

    List<BarcodePackageScan> allBarcode = [];

    for (var x in getQrAll) {
      var barcode = BarcodePackageScan(
        barcode: x.code,
        referanceNo: x.ref1,
        scanFlag: x.syncFlag,
        message: x.message,
      );

      allBarcode.add(barcode);
    }

    PackageScanForm mapPackageScan = PackageScanForm(
      id: jobLocation.id,
      jobId: jobLocation.jobId,
      jobNo: jobLocation.jobNo,
      jobDetailId: jobLocation.jobDetailId,
      actPackage: getQrAll.length + (int.tryParse(totalNotLabel.text) ?? 0),
      actManualPackage: int.tryParse(totalNotLabel.text) ?? 0,
      vehicleId: vehicle!.id,
      geoLatitude: getCurrent?.latitude.toString(),
      geoLongitude: getCurrent?.longitude.toString(),
      barcodes: allBarcode,
    );

    actPackage = mapPackageScan.actPackage ?? 0;
    actScanPackage = getQrAll.length;
    actManualPackage = mapPackageScan.actManualPackage ?? 0;

    getLocation = getLocation?.copyWith(
      actPackage: d.Value(actPackage),
      actScanPackage: d.Value(actScanPackage),
      actManualPackage: d.Value(actManualPackage),
    );

    db.updateTable(db.jobLocationEntries, getLocation!);

    var loadPackageScheduler = JobSchedulerEntriesCompanion.insert(
      url: '',
      activityType: const d.Value('LOADING.PACKAGE'),
      request: d.Value(mapPackageScan.toJson()),
      syncFlag: const d.Value('N'),
      createBy: d.Value(user!.userName),
      createDt: d.Value(DateTime.now().toIso8601String()),
      counter: const d.Value(0),
    );

    try {
      if (await GLFunc.isClientOnline()) {
        var resPackageScan = await JobRepository().putPackageScans(
          mapPackageScan.toMap(),
        );

        loadPackageScheduler = loadPackageScheduler.copyWith(
          url: const d.Value('SUCCESS'),
          statusCode: const d.Value('200'),
          response: d.Value(resPackageScan?.toJson().toString()),
          counter: d.Value((loadPackageScheduler.counter.value ?? 0) + 1),
          syncFlag: const d.Value('Y'),
        );

        await db.jobSchedulerEntries
            .insertOnConflictUpdate(loadPackageScheduler);
      }
    } on DioError catch (e) {
      loadPackageScheduler = loadPackageScheduler.copyWith(
        response: d.Value(e.response?.data),
        counter: d.Value((loadPackageScheduler.counter.value ?? 0) + 1),
        syncFlag: const d.Value('N'),
      );
      await db.jobSchedulerEntries.insertOnConflictUpdate(loadPackageScheduler);

      GLFunc.showSnackbar(
        message: e.response!.data!['message']['th']! ?? 'บันทึกข้อมูลไม่สำเร็จ',
        type: SnackType.ERROR,
        showIsEasyLoading: true,
      );

      rethrow;
    } finally {
      // _listOfScanPackage.clear();
      db.clearTable(db.jobPackageScanEntries);
      listOfManifest.clear();
      scanPackageAll.clear();
    }
  }

  // Future<void> saveQR(String? v, [bool saveAsList = false]) async {
  //   var user = BoxCacheUtil.getAuthUser;
  //   var vehicle = BoxCacheUtil.getVehicle;

  //   Position? getCurrent;

  //   getCurrent = await locationService.getLocation();

  //   List<int> listIds = [];

  //   if (saveAsList) {
  //     GLFunc.instance.showLoading('กำลังบันทึกรายการ');

  //     var getQrAll = await ((db.jobPackageScanEntries.select())
  //           ..where((t) =>
  //               t.jobNo.equals(activeLocation!.jobNo!) &
  //               t.locationId.equals(activeLocation!.id) &
  //               t.syncFlag.isIn(['P', 'C'])))
  //         .get();

  //     var getLocation = await ((db.jobLocationEntries.select())
  //           ..where((t) => t.id.equals(activeLocation!.id)))
  //         .getSingleOrNull();

  //     await (db.jobPackageScanEntries.deleteWhere((x) =>
  //         x.jobNo.equals(activeLocation!.jobNo!) & x.locationId.isNull()));

  //     int actPackage = 0;
  //     int actScanPackage = 0;
  //     int actManualPackage = 0;

  //     for (var q in getQrAll) {
  //       var mapPackageScan = PackageScanForm(
  //         id: activeLocation!.id,
  //         jobId: activeLocation!.jobId!,
  //         jobNo: activeLocation!.jobNo!,
  //         jobDetailId: activeLocation!.jobDetailId!,
  //         actPackage: getQrAll.length,
  //         actManualPackage: int.tryParse(totalNotLabel.text) ?? 0,
  //         vehicleId: vehicle!.id!,
  //         geoLatitude: getCurrent?.latitude.toString() ?? "0",
  //         geoLongitude: getCurrent?.longitude.toString() ?? "0",
  //         barcodes: [],
  //       );

  //       listIds.add(q.id);

  //       actPackage = mapPackageScan.actPackage ?? 0;
  //       actScanPackage = mapPackageScan.actPackage ?? 0;
  //       actManualPackage = mapPackageScan.actManualPackage ?? 0;

  //       q = q.copyWith(
  //         message: const d.Value('Confirm save to database local'),
  //         syncFlag: const d.Value('C'),
  //         rawData: d.Value(mapPackageScan.toJson()),
  //       );
  //     }
  //     await db.bulkUpdate(db.jobPackageScanEntries, getQrAll);

  //     if (getQrAll.isEmpty) {
  //       actManualPackage = int.parse(totalNotLabel.text);
  //     }

  //     getLocation = getLocation?.copyWith(
  //       actPackage: d.Value(actPackage),
  //       actScanPackage: d.Value(actScanPackage),
  //       actManualPackage: d.Value(actManualPackage),
  //     );

  //     db.updateTable(db.jobLocationEntries, getLocation!);
  //   } else {
  //     if (v != null) {
  //       var getLastQR = await ((db.jobPackageScanEntries.select())
  //             ..where((t) => t.code.equals(v)))
  //           .getSingleOrNull();

  //       if (getLastQR == null) {
  //         var mapPackageScan = PackageScanForm(
  //           id: activeLocation!.id,
  //           jobId: activeLocation!.jobId!,
  //           jobNo: activeLocation!.jobNo!,
  //           jobDetailId: activeLocation!.jobDetailId!,
  //           actPackage: activeLocation?.actPackage ?? 0,
  //           actManualPackage: int.tryParse(totalNotLabel.text) ?? 0,
  //           vehicleId: vehicle!.id!,
  //           geoLatitude: getCurrent?.latitude.toString() ?? "0",
  //           geoLongitude: getCurrent?.longitude.toString() ?? "0",
  //           barcodes: [],
  //         );

  //         var pkgs = JobPackageScanEntriesCompanion.insert(
  //           code: v,
  //           jobNo: activeLocation!.jobNo!,
  //           createDt: DateTime.now().toIso8601String(),
  //           createBy: d.Value((user?.userThName ?? user?.userEnName)!),
  //           message: const d.Value('Save via local'),
  //           rawData: d.Value(mapPackageScan.toJson()),
  //           seq: const d.Value(0),
  //           locationId: d.Value(activeLocation!.id),
  //         );

  //         listIds.add(await db.jobPackageScanEntries.insertOne(pkgs));
  //       } else {
  //         listIds.add(getLastQR.id);
  //       }
  //     }
  //   }

  //   var listByIds = await ((db.jobPackageScanEntries.select())
  //         ..where((t) => t.id.isIn(listIds) & t.syncFlag.isIn(['P', 'C'])))
  //       .get();

  //   GLFunc.instance.showLoading();
  //   JobPackageScanEntry? header;
  //   PackageScanForm? packageScanForm;

  //   if (listByIds.isNotEmpty) {
  //     header = listByIds.first;

  //     if (header.rawData != null && header.rawData == 'MANIFEST') {
  //       packageScanForm = PackageScanForm(
  //         id: activeLocation!.id,
  //         jobId: activeLocation!.jobId!,
  //         jobNo: activeLocation!.jobNo!,
  //         jobDetailId: activeLocation!.jobDetailId!,
  //         actPackage: activeLocation?.actPackage ?? 0,
  //         actManualPackage: int.tryParse(totalNotLabel.text) ?? 0,
  //         vehicleId: vehicle!.id!,
  //         geoLatitude: getCurrent?.latitude.toString() ?? "0",
  //         geoLongitude: getCurrent?.longitude.toString() ?? "0",
  //         barcodes: [],
  //       );
  //     } else if (packageScanForm != null) {
  //       packageScanForm = PackageScanForm.fromJson(header.rawData!);
  //       for (var e in listByIds) {
  //         packageScanForm.barcodes?.add(
  //           BarcodePackageScan(
  //             barcode: e.code,
  //             scanFlag: 'Y',
  //             referanceNo: e.ref1,
  //           ),
  //         );
  //       }
  //     }
  //   }

  //   packageScanForm ??= PackageScanForm();

  //   packageScanForm = packageScanForm.copyWith(
  //     jobDetailId: activeLocation!.jobDetailId!,
  //     jobId: activeLocation!.jobId,
  //     jobNo: activeLocation!.jobNo!,
  //     actPackage: packageScanForm.barcodes?.length,
  //     actManualPackage: int.tryParse(totalNotLabel.text) ?? 0,
  //     vehicleId: vehicle!.id!,
  //     geoLatitude: getCurrent?.latitude.toString() ?? "0",
  //     geoLongitude: getCurrent?.longitude.toString() ?? "0",
  //     id: activeLocation!.id,
  //   );

  //   var jobEntry = JobSchedulerEntriesCompanion.insert(
  //     url: '',
  //     activityType: const d.Value('LOADING.PACKAGE'),
  //     request: d.Value(packageScanForm.toJson()),
  //     syncFlag: const d.Value('N'),
  //     createBy: d.Value(user!.userName),
  //     createDt: d.Value(DateTime.now().toIso8601String()),
  //     counter: const d.Value(0),
  //   );

  //   try {
  //     if (await GLFunc.isClientOnline()) {
  //       var resPackageScan = await JobRepository().putPackageScans(
  //         packageScanForm.toMap(),
  //       );

  //       jobEntry = jobEntry.copyWith(
  //         statusCode: const d.Value('200'),
  //         response: d.Value(resPackageScan!.toJson().toString()),
  //         counter: d.Value((jobEntry.counter.value ?? 0) + 1),
  //         syncFlag: const d.Value('Y'),
  //       );
  //       GLFunc.showSnackbar(
  //         message: resPackageScan.message?.th ?? 'บันทึกข้อมูลสำเร็จ',
  //         type: SnackType.ERROR,
  //         showIsEasyLoading: true,
  //       );
  //     } else {
  //       GLFunc.showSnackbar(
  //         showIsEasyLoading: true,
  //         message: 'บันทึกสำเร็จ',
  //         type: SnackType.SUCCESS,
  //       );
  //     }
  //   } on DioError catch (e) {
  //     if ((packageScanForm.barcodes?.length ?? 0) > 0) {
  //       jobEntry = jobEntry.copyWith(
  //         response: d.Value(e.response?.data),
  //         counter: d.Value((jobEntry.counter.value ?? 0) + 1),
  //         syncFlag: const d.Value('E'),
  //       );
  //       await db.jobSchedulerEntries.insertOne(jobEntry);
  //     }
  //     GLFunc.showSnackbar(
  //       message: e.response!.data!['message']['th']! ?? 'บันทึกข้อมูลไม่สำเร็จ',
  //       type: SnackType.ERROR,
  //       showIsEasyLoading: true,
  //     );

  //     rethrow;
  //   } finally {
  //     if ((packageScanForm.barcodes?.length ?? 0) > 0 &&
  //         jobEntry.syncFlag.value != 'Y') {
  //       await db.jobSchedulerEntries.insertOne(jobEntry);
  //       if ((packageScanForm.barcodes?.length ?? 0) > 0) {
  //         var getPkgByLocation = await (db.jobSchedulerEntries.select()
  //               ..where((x) => x.url.equals('SCAN_${activeLocation!.id}')))
  //             .getSingleOrNull();

  //         if (getPkgByLocation != null) {
  //           getPkgByLocation = getPkgByLocation.copyWith(
  //             request: d.Value(packageScanForm.toJson()),
  //             syncFlag: const d.Value('N'),
  //           );

  //           db.updateTable(db.jobSchedulerEntries, getPkgByLocation);
  //         } else {
  //           var jobEntry = JobSchedulerEntriesCompanion.insert(
  //             url: 'SCAN_${activeLocation!.id}',
  //             activityType: const d.Value('LOADING.PACKAGE'),
  //             request: d.Value(packageScanForm.toJson()),
  //             syncFlag: const d.Value('N'),
  //             createBy: d.Value(user.userName),
  //             createDt: d.Value(DateTime.now().toIso8601String()),
  //             counter: const d.Value(0),
  //           );

  //           await db.jobSchedulerEntries.insertOne(jobEntry);
  //         }
  //       }

  //       _listOfScanPackage.clear();
  //       GLFunc.instance.hideLoading();
  //     }
  //   }
  // }

  Future<bool?> dialogFingerScan(String? jobNo,
      [bool fingerScanComplate = false]) async {
    var getName = await JobRepository().getCheckFingerScan(jobNo);
    var data = getName?.results ?? "";
    return dialogUtils.dialogCustom(
      onWillPop: false,
      title: const Text('ยืนยันข้อมูลการลงเวลาปฎิบัติงาน'),
      content: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            "assets/images/face-scan.png",
            scale: 5,
          ),
          Text(
            'ไม่พบข้อมูลการลงเวลาปฏิบัติงาน หรือมีการลงเวลาเกินกว่าชั่วโมงที่กำหนดกรุณาทำการแสกนนิ้ว/หน้า เพื่อลงเวลาปฏิบัติงานก่อนกดเสร็จงาน',
            style: TextStyle(fontSize: 18.sm),
            textAlign: TextAlign.center,
          ),
          ...List.generate(
            data.length,
            (idx) => Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(data[idx]['employeeThName']),
                Chip(
                  backgroundColor: data[idx]['scanFlag'] == 'N'
                      ? Colors.grey.shade200
                      : Colors.green,
                  label: Text(
                      data[idx]['scanFlag'] == 'N' ? "ยังไม่สแกน" : "สแกน"),
                )
              ],
            ),
          ),
          Text(
            'หากกดยืนยัน ไม่ทำการแสกนในเวลาที่กำหนด จะไม่มีการคิดค่าจ้างในใบงานนี้',
            style: TextStyle(fontSize: 14.sm, color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: ButtonWidgets.cancelButtonOutline(
                label: 'กำลังไปสแกน',
                onTab: () {
                  Get.back(result: false);
                  if (!fingerScanComplate) {
                    dialogUtils.dialogCustom(
                      onWillPop: false,
                      content: Text(
                        'กรุณารอลงเวลา 1 นาที\nค่อยกดปุ่ม เสร็จงาน',
                        style: TextStyle(fontSize: 24.sm),
                        textAlign: TextAlign.center,
                      ),
                      actions: [
                        ButtonWidgets.closeButtonOutline(onTab: () async {
                          Get.back();
                        }),
                      ],
                    );
                  }
                },
              ),
            ),
            Expanded(
              child: ButtonWidgets.okButtonOutline(
                  label: 'ยืนยันการลงเวลา',
                  onTab: () async {
                    Get.back(result: true);
                  }),
            ),
          ],
        ),
      ],
    );
  }

  Future<bool?> dialogCheckOutWorkTime(String? getJobTime,
      [bool fingerScanFlag = false]) {
    return dialogUtils.dialogCustom(
      title: const Text(
        "แจ้งเตือนสแกนเวลา",
      ),
      content: Column(
        children: [
          Image.asset(
            "assets/images/face-scan.png",
            scale: 5,
          ),
          Text(
            "มีการเปิดงาน\nในช่วงเวลา 18:00 - 07:00",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 19.5.sm),
          ),
        ],
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: ButtonWidgets.cancelButtonOutline(
                label: 'สแกนเวลา',
                onTab: () async {
                  Get.back();
                },
              ),
            ),
            if (getJobTime ==
                'Y') // checkOutWorkTimeFlag?.vehicleSupplierFlag = Y รถร่วมปุ่มถึงจะขึ้น
              Expanded(
                child: ButtonWidgets.okButtonOutline(
                    label: 'เริ่มงานทันที',
                    onTab: () async {
                      Get.back(result: true);
                    }),
              ),
          ],
        )
      ],
    );
  }

  Future<bool?> dialogStartJob() {
    return dialogUtils.dialogCustom(
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          Icon(
            Icons.local_shipping,
            size: 60,
            color: Colors.grey.shade600,
          ),
          Padding(
            padding: const EdgeInsets.all(8.0).r,
            child: Text(
              'ยืนยันการเริ่มงานใช่หรือไม่?',
              style: TextStyle(
                fontSize: 18.5.sm,
              ),
            ),
          )
        ],
      ),
      actionWithContent: true,
      actions: [
        Row(
          children: [
            Expanded(
              child: ButtonWidgets.cancelButtonOutline(
                  //  onTab: () {},
                  ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: ButtonWidgets.okButtonOutline(
                label: 'label.confirm',
                onTab: () async {
                  Get.back(
                    closeOverlays: false,
                    result: true,
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
