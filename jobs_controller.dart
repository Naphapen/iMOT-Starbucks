// ignore_for_file: empty_catches, deprecated_member_use, unused_local_variable

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart' as dio;
import 'package:drift/drift.dart' as drift;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:imot/Api_Repository_Service/controllers/job_detail_controller.dart';
import 'package:imot/Api_Repository_Service/repositories/option_repository.dart';
import 'package:imot/Api_Repository_Service/services/backgrounds/isolate_util.dart';
import 'package:imot/common/Other/app_colors.dart';
import 'package:imot/common/Other/dialog_utils.dart';
import 'package:imot/common/Other/general_function.dart';
import 'package:imot/common/cache/box_cache.dart';
import 'package:imot/common/db/isar_utils.dart';
import 'package:imot/Api_Repository_Service/dio/dio_exceptions.dart';
import 'package:imot/common/firebase/firebase_notifications.dart';
import 'package:imot/common/models/shared/user_profile.dart';
import 'package:imot/Api_Repository_Service/services/auth_service.dart';
import 'package:imot/Api_Repository_Service/services/battery_service.dart';
import 'package:imot/Api_Repository_Service/services/job_service.dart';
import 'package:imot/common/models/view/job_catch.dart';
import 'package:imot/database/database.dart';
import 'package:imot/common/models/shared/response_model.dart';
import 'package:imot/common/models/shared/summary_job.dart';
import 'package:imot/common/models/view/job_detail.dart';
import 'package:imot/common/models/view/job_header.dart';
import 'package:imot/common/models/view/vehicle_view_model.dart';
import 'package:imot/app.dart';
import 'package:imot/Api_Repository_Service/repositories/job_repository.dart';
import 'package:imot/Api_Repository_Service/services/location_service.dart';
import 'package:imot/common/shared/app_enum.dart';
import 'package:imot/common/widgets/buttons/button_component.dart';
import 'package:imot/common/widgets/qr/license_plate_scan.dart';
import 'package:imot/pages/now_page/scan_and_signature/confirm_liceseplate.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_info2/system_info2.dart';

class JobsController extends FullLifeCycleController {
  JobsController get to => Get.find();
  Worker? worker;
  final RxBool _isOnSite = false.obs;
  var scaffoldKey = GlobalKey<ScaffoldState>();

  final ImagePicker imagePicker = ImagePicker();
  Rx<VehicleViewModel?>? vehicleInfo;

  RxList<Map<String, dynamic>> jobWatingAcceptList = RxList([]);
  var jobHistory = [];
  RxBool isLoading = true.obs;
  RxBool isLoadingPending = false.obs;
  RxBool isVehicleLoading = true.obs;
  RxBool isTaskCount = false.obs;

  final ReceivePort receivePort = ReceivePort();

  Rx<JobHeader>? jobSelected;
  BatteryService batteryService = BatteryService();
  SendPort? mainToIsolateStream;
  AppDatabase get db => AppDatabase.provider;

  int get totalJobPending => jobWatingAcceptList.length;
  LocationService get locationService => LocationService();
  JobService get jobService => JobService();
  bool get isOnsite => _isOnSite(BoxCacheUtil.isOnSite);

  UserProfile? get auth => BoxCacheUtil.getAuthUser;

  // ConnectivityService connectivityService = Get.put(ConnectivityService());

  bool isDialogOpen = Get.isDialogOpen ?? false;

  AuthService loginService = Get.put(AuthService());
  @override
  void onInit() {
    WidgetsBinding.instance.addObserver(this);
    jobWatingAcceptList.clear();
    db.watchJob(jobNo: 'jobNo').listen((event) {
      //print('event.change:$event');
    });

    initPage();
    super.onInit();
    setPort();
  }

  Future<int> getCountTask() async {
    // isTaskCount(true);
    var i = await (db.select(db.jobSchedulerEntries)
          ..where((tbl) => tbl.syncFlag.equals("N")))
        .get();
    // isTaskCount(false);
    // update();

    return i.length;
  }

  Future<void> sendCatchError(String? action) async {
    int mb = 1024 * 1024;

    final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();

    late AndroidDeviceInfo androidInfo;
    late IosDeviceInfo iosInfo;

    if (Platform.isAndroid) {
      androidInfo = await deviceInfoPlugin.androidInfo;
    } else if (Platform.isIOS) {
      iosInfo = await deviceInfoPlugin.iosInfo;
    }

    var getScheduler = await db.select(db.jobSchedulerEntries).get();

    int memoryFree = Platform.isAndroid
        ? (SysInfo.getFreePhysicalMemory() + SysInfo.getFreeVirtualMemory()) ~/
            mb
        : 0;
    int memoryUsed = Platform.isAndroid
        ? SysInfo.getTotalPhysicalMemory() ~/ mb - memoryFree
        : 0;

    JobCatchSend data = JobCatchSend(
      employeeNo: '${auth?.employeeId}',
      action: action,
      brand: Platform.isAndroid == true ? androidInfo.brand : 'Apple',
      modelPhone:
          Platform.isAndroid == true ? androidInfo.model : iosInfo.model,
      androidVersion: Platform.isAndroid == true
          ? androidInfo.version.release
          : iosInfo.systemVersion,
      memoryDevice: Platform.isAndroid
          ? "${SysInfo.getTotalPhysicalMemory() ~/ mb}"
          : 'iOS',
      memoryUsed: Platform.isAndroid ? memoryUsed.toString() : 'iOS',
      memoryFree: Platform.isAndroid ? memoryFree.toString() : 'iOS',
      createDt: DateTime.now().toIso8601String(),
      createBy: auth?.userThName,
      jobScheduler: getScheduler.map((e) => e.toJson()).toList(),
    );

    await JobRepository().putCatchError(action!, data.toJson().toString());
  }

  Future<void> setPort() async {
    mainToIsolateStream = await IsoLateUtil().initIsolate();
    // //print('x');
  }

  removeJobPending(String j) {
    isLoadingPending(true);
    jobWatingAcceptList.removeWhere((e) => e['jobNo'] == j);
    isLoadingPending(false);
    update();
  }

  void trigerReload() {
    isLoadingPending(true);

    Future.delayed(const Duration(milliseconds: 400)).then((_) {
      loadPending();
      isLoadingPending(false);
    });
  }

  Future<List<Map<String, dynamic>>?> loadPending() async {
    try {
      Future.delayed(const Duration(seconds: 3));
      var res = await JobRepository().getJobAssign();

      return res;
    } on dio.DioError catch (er) {
      bool isTimeout =
          er.error is SocketException || er.error is TimeoutException;
      if (isTimeout && !Get.isDialogOpen!) {
        GLFunc.showSnackbar(
          message: (er.response?.statusCode ?? 0) >= 500
              ? 'ไม่สามารถเชื่อมต่อ getway ปลายทางได้หรือหมดเวลาในการเชือมต่อกรุณาลองใหม่อีกครั้ง'
              : er.message,
          type: SnackType.ERROR,
          showIsEasyLoading: true,
        );
      } else {
        if (!Get.isDialogOpen!) {
          GLFunc.showSnackbar(
            message: (er.response?.statusCode ?? 0) >= 500
                ? 'ไม่สามารถเชื่อมต่อ getway ปลายทางได้กรุณาลองใหม่อีกครั้ง'
                : er.message,
            type: SnackType.ERROR,
            showIsEasyLoading: true,
          );
        }
      }

      rethrow;
    } finally {}
  }

  void switchMode(bool isOnsite) {
    isLoading(true);
    BoxCacheUtil.setSwitchMode(isOnsite);
    _isOnSite(isOnsite);
    isLoading(false);
    update();
  }

  Future<void> initPage() async {
    var isLogin = BoxCacheUtil.authenticated;
    isLoading(true);
    await Future.delayed(const Duration(milliseconds: 500));
    try {
      if (isLogin) {
        if (GetPlatform.isMobile) {
          await vehicleScan().then((_) {
            fetchPage();
            //  getException();
          });

          vehicleInfo = Rx(BoxCacheUtil.getVehicle);
        }
      }
      isLoading(false);
    } finally {
      GLFunc.instance.hideLoading();

      update();
    }
  }

  bool get isVehicle => vehicleInfo != null;

  Future<void> dialogShowNotify() async {
    if (GetPlatform.isMobile) {
      AwesomeNotifications().isNotificationAllowed().then((isAllowed) {
        if (!isAllowed) {
          Get.defaultDialog(
            title: 'รับการแจ้งเตือน',
            middleText: 'คำขอแอพของเราต้องการส่งการแจ้งเตือนของคุณ',
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey,
                ),
                onPressed: () {
                  Get.back();
                },
                child: const Text('ปิด'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade400,
                ),
                onPressed: () {
                  AwesomeNotifications()
                      .requestPermissionToSendNotifications()
                      .then((value) => Get.back());
                },
                child: const Text('อนุญาติ'),
              ),
            ],
          );
        }
      });
    }
  }

  Stream<List<DashboardEntry?>> getDashboardStream() =>
      db.watchSummaryDashboard();

  Future<void> getJobAll() async {
    try {
      isLoading(true);
      ResponseModel? res;
      if (await GLFunc.isClientOnline()) {
        res = await JobRepository().getJobsV2();

        var items =
            List<Map<String, dynamic>>.from(res?.results?['items'] ?? []);

        if (items.isNotEmpty) {
          await IsarUtils.updateJobs(
            itemsJob: items,
          );
        }
      }
    } on DioExceptions catch (e) {
      //print('errro $e');
      GLFunc.showSnackbar(
        message: 'iMOT เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง [${e.message}]',
        type: SnackType.ERROR,
        showIsEasyLoading: true,
      );
    } finally {
      isLoading(false);
      update();
    }
  }

  Future<void> fetchPage() async {
    try {
      await Future.wait([
        summary(),
        getJobAll(),
        getException(),
      ]);
    } on dio.DioError catch (e) {
      //print("Error $e");

      showDialogError(messageToError(e));
    }
  }

  Future<void> summary() async {
    DashboardEntry? dashboard = await db.summaryDashboard();
    Map<String, dynamic>? result;
    try {
      result = await JobRepository().getJobSummary() ?? {};
    } catch (e) {}

    if (dashboard == null) {
      var mapSum = SummaryJob.fromMap(result!);

      db.insertOne(
        db.dashboardEntries,
        DashboardEntriesCompanion.insert(
          jobNo: drift.Value(mapSum.jobNo),
          totalAccept: mapSum.totalAccept ?? 0,
          totalPickup: mapSum.summary?.totalPickup ?? 0,
          totalDelvery: mapSum.summary?.totalDelvery ?? 0,
          total: mapSum.summary?.total ?? 0,
          totalReturn: mapSum.summary?.totalReturn ?? 0,
          userId: auth!.id!,
          createDt: DateTime.now().toIso8601String(),
        ),
      );
    } else {
      var mapSum = SummaryJob.fromMap(result!);

      dashboard = dashboard.copyWith(
        jobNo: drift.Value(mapSum.jobNo),
        totalAccept: mapSum.totalAccept,
        totalPickup: mapSum.summary?.totalPickup ?? 0,
        totalDelvery: mapSum.summary?.totalDelvery ?? 0,
        total: mapSum.summary?.total ?? 0,
        totalReturn: mapSum.summary?.totalReturn ?? 0,
      );

      db.updateTable(db.dashboardEntries, dashboard);
    }
  }

  String messageToError(dio.DioError e) {
    var message = e.error is SocketException || e.error is TimeoutException
        ? 'ไม่สามารถเชื่อมต่อ getway ปลายทางได้\rกรุณาลองใหม่อีกครั้ง'
        : 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง';

    return e.response?.data?['message']['th'] ?? message;
  }

  Future<void> getJobAssign() async {
    try {
      if (await GLFunc.isClientOnline()) {
        isLoadingPending(true);
        //print('getJobAssign runinig');
        jobWatingAcceptList.clear();

        final result = await JobRepository().getJobAssign();

        jobWatingAcceptList.addAll(result ?? []);
      }
    } on dio.DioError catch (e) {
      //print(e);
      GLFunc.showSnackbar(
        message: messageToError(e),
        type: SnackType.ERROR,
      );
    } finally {
      isLoadingPending(false);
      update();
    }
  }

  Future jobsHistory() async {
    final authLogin = BoxCacheUtil.getAuthUser;
    try {
      if (await GLFunc.isClientOnline()) {
        isLoadingPending(true);
        var res = await JobRepository().getHistory(authLogin?.employeeId ?? '');
        jobHistory = res!.toList();
        return jobHistory;
      }
    } on dio.DioError {
      // print(e);
      GLFunc.showSnackbar(
        message: 'เกิดข้อผิดพลาด',
        type: SnackType.ERROR,
      );
    } finally {
      isLoadingPending(false);
      update();
    }
  }

  Future<void> updateMe() async {
    try {
      GLFunc.instance.showLoading('กำลังตรวจสอบข้อมูล');
      var resUser = await loginService.me();

      if (resUser?.vehicleSupplierFlag == 'Y') {
        var mapData = resUser?.vehicleWithMobile!.toMap();
        if (mapData != null) {
          BoxCacheUtil.setVehicle(mapData);
          BoxCacheUtil.box.write('vehicle_key', '${mapData['id']}');
        }
        if (resUser?.vehicleWithMobile?.vehicleId == null &&
            resUser?.vehicleWithMobile?.licensePlate == null) {
          GLFunc.showSnackbar(
            message: '[Me] ไม่พบข้อมูลทะเบียนรถของคุณ กรุณาลองใหม่อีกครั้ง',
            type: SnackType.ERROR,
          );
          return;
        }
        Get.back();
        GLFunc.showSnackbar(
          message: 'สำเร็จแล้ว ขอให้สนุกกับการทำงานอีกครั้ง',
          type: SnackType.SUCCESS,
        );
      }

      // //print('x');
    } on dio.DioError catch (e) {
      GLFunc.showSnackbar(
        message: messageToError(e),
        type: SnackType.ERROR,
      );
    } finally {
      GLFunc.instance.hideLoading();
    }
  }

  Future<void> vehicleScan() async {
    Future.delayed(const Duration(milliseconds: 200)).then((_) async {
      try {
        isVehicleLoading(true);

        final result = BoxCacheUtil.getVehicle;
        if (result?.licensePlate == null) {
          throw ("No license plate");
        }

        vehicleInfo = Rx((result!));
        isVehicleLoading(false);
        update();
      } catch (e) {
        isVehicleLoading(false);

        update();

        if (Get.isDialogOpen!) {
          Get.back();
        }
        DialogUtils().dialogCustom(
          onWillPop: auth!.vehicleSupplierFlag != 'Y',
          content: SizedBox(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: auth!.vehicleSupplierFlag == 'Y'
                  ? [
                      Icon(Icons.info, size: 80, color: Colors.blue.shade400),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          'บัญชีของคุณเป็นรถร่วมบริการตรวจสอบไม่พบข้อมูลทะเบียนรถ กดโหลดข้อมูลอีกครั้ง\rหากยังไม่ได้ติดต่อผู้ดูแล',
                          style: TextStyle(
                            fontSize: 16.5.sm,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.green300,
                          fixedSize: Size.fromWidth(Get.size.width),
                        ),
                        icon: const Icon(Icons.sync, color: Colors.white),
                        onPressed: () {
                          // //print('ssss');
                          updateMe();
                        },
                        label: Text(
                          'โหลดข้อมูลอีกครั้ง'.tr,
                          style: const TextStyle(
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ]
                  : [
                      Icon(Icons.info, size: 80, color: Colors.blue.shade400),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20).r,
                        child: Text(
                          'ไม่พบข้อมูลรถ กดปุ่ม SCAN QR เพื่อดำเนินการต่อ',
                          style: TextStyle(
                            fontSize: 16.5.sm,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0).r,
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 1),
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.green300,
                                  ),
                                  icon: const Icon(Icons.qr_code,
                                      color: Colors.white),
                                  onPressed: () {
                                    Get.back();
                                    missingLicensePlate();
                                  },
                                  label: Text(
                                    'SCAN QR'.tr,
                                    style: const TextStyle(
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          ],
                        ),
                      )
                    ],
            ),
          ),
        );
      }
    });
  }

  void checkPermission() async {
    final JobDetailController controlpermis = JobDetailController();
    var camera = await Permission.camera.status;
    var location = await Permission.location.status;
    // var storage = await Permission.storage.status;
    if (!camera.isGranted || !location.isGranted) {
      await controlpermis.checkPermision();
      return;
    }
  }

  Future<void> missingLicensePlate() async {
    if (GetPlatform.isDesktop) {
      Get.to(
        () => ConfirmLicesePlate(
          licensePlate: '',
          licenseProvince: '',
        ),
        transition: Transition.rightToLeftWithFade,
      )!
          .then(
            (v) async {
              //print('confirm vehicle');
              if (v != null && v is VehicleViewModel) {
                BoxCacheUtil.setVehicle(v);
                vehicleInfo = Rx(v);
                GLFunc.showSnackbar(
                  type: SnackType.SUCCESS,
                  message: 'ยืนยันการใช้งานรถสำเร็จ',
                );
              } else if (v == 're-scan') {
                missingLicensePlate();
              }
            },
          )
          .catchError((onError) async {})
          .whenComplete(() => isVehicleLoading(false));
      return;
    }

    await Get.to(() => const LicensePlateScan())!.then((value) async {
      // //print('qr code callback: $value');
      if (value != null) {
        final listResult = (value).toString().split('|').toList();
        isVehicleLoading(true);

        String? prov = listResult.length == 2 ? listResult[1] : null;

        Get.to(
          () => ConfirmLicesePlate(
            licensePlate: listResult[0],
            licenseProvince: prov,
          ),
          transition: Transition.rightToLeftWithFade,
        )!
            .then(
              (v) async {
                //print('confirm vehicle');
                if (v != null && v is VehicleViewModel) {
                  BoxCacheUtil.setVehicle(v);
                  vehicleInfo = Rx(v);
                  GLFunc.showSnackbar(
                    type: SnackType.SUCCESS,
                    message: 'ยืนยันการใช้งานรถสำเร็จ',
                  );
                } else if (v == 're-scan') {
                  missingLicensePlate();
                }
              },
            )
            .catchError((onError) async {})
            .whenComplete(() => isVehicleLoading(false));
      }
    });
  }

  Future<void> updateSummryRandom() async {}

  RxBool isLoadingDetailPage = false.obs;
  RxBool showButtonDetail = true.obs;
  List<Map<String, dynamic>> listOfDetail = [];
  // final RxList<Map<String, dynamic>> _listOfDetailWebSocket = RxList([]);

  Stream<List<Map<String, dynamic>>?> listOfDetailWebSocket() {
    return Stream.fromIterable([]);
  }

  JobHeader? jobActive;
  Rx<JobDetail>? assignmentActive;
  List<JobDetail> listOfDetails = [];

  int get countAssignment => listOfDetails.length;

  Future<void> getJobInfo(String jobNo,
      [JobStatus jobStatus = JobStatus.ASSIGN]) async {
    isLoadingDetailPage(true);

    try {
      if (listOfDetails.where((e) => e.jobNo == jobNo).isEmpty) {
        var res =
            await JobRepository().fetchDataJobDetail(jobNo, jobStatus.name);
        var mapData = Map<String, dynamic>.from(res?.results!['item']);
        jobActive = JobHeader.fromMap(mapData);

        if (mapData.containsKey('details')) {
          final details = List<Map<String, dynamic>>.from(mapData['details']);
          listOfDetails.addAll(details.map((e) => JobDetail.fromMap(e)));
        }
      }
    } on dio.DioError {
      // //print(onError);
    } finally {
      isLoadingDetailPage(false);
      update();
    }
  }

  Future<void> removeByJob(jobNo) async {
    IsarUtils.iMOTContext.jobHeaderEntries
        .deleteWhere((t) => t.jobNo.equals(jobNo));

    IsarUtils.iMOTContext.jobDetailEntries
        .deleteWhere((t) => t.jobNo.equals(jobNo));

    IsarUtils.iMOTContext.jobLocationEntries
        .deleteWhere((t) => t.jobNo.equals(jobNo));
  }

  Future<List<JobDetail>?> getJobInfoDetail(
    String jobNo, [
    JobStatus jobStatus = JobStatus.ASSIGN,
  ]) async {
    try {
      // //print('load item detail');
      isLoadingDetailPage(true);
      List<JobDetail> localItems = [];

      var exitsDetails =
          await db.getJobDetail(jobNo: jobNo, statuss: [jobStatus.name]);

      // //print(exitsDetails?.length);
      exitsDetails ??= [];
      localItems = exitsDetails;
      if ((exitsDetails).isEmpty) {
        try {
          var res = await JobRepository().fetchDataJobDetail(
            jobNo,
            jobStatus.name,
          );
          var mapData = Map<String, dynamic>.from(res?.results!['item']);

          jobActive = JobHeader.fromMap(mapData);
          jobActive!.details = List.from(mapData['details'])
              .map((e) => JobDetail.fromMap(e))
              .toList();

          if (mapData.containsKey('details')) {
            listOfDetails.addAll(jobActive!.details!);
            localItems.addAll(jobActive!.details!);

            return localItems;
          }

          if (res?.code == 'NONE_JOB') {
            removeByJob(jobNo);
          }
        } on dio.DioError {
          //  //print('map error $onError');
          rethrow;
        }

        isLoadingDetailPage(false);
      } else {
        isLoadingDetailPage(false);
      }

      return localItems;
    } on dio.DioError catch (onError) {
      //print(onError);
      showDialogError(onError.response!.data['message']['th']);
      rethrow;
    } finally {}
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

  Stream<T> flattenStreamsOfFutures<T>(Stream<Future<T>> source) async* {
    await for (var future in source) {
      yield await future;
    }
  }

  RxList<JobDetailEntry> listDetailsStream = RxList();
  void jobAcceptShowDialog(v) {
    DialogUtils().dialogCustom(
      title: Text('title.notify'.tr),
      //barrierDismissible: true,
      onWillPop: false,
      contentPadding: const EdgeInsets.all(3),
      content: SizedBox(
        width: Get.size.width * .8,
        child: Column(
          children: [
            Text(
              '$v',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 15.5.sm,
              ),
              textAlign: TextAlign.center,
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.dashboard, color: Colors.white),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue.shade500,
                        backgroundColor: Colors.blue.shade300,
                        visualDensity: const VisualDensity(horizontal: -4),
                      ),
                      onPressed: () {
                        Get.back();
                      },
                      label: Text(
                        'หน้าหลัก'.tr,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green.shade500,
                        backgroundColor: Colors.green.shade300,
                        visualDensity: const VisualDensity(horizontal: -3),
                      ),
                      onPressed: () {},
                      icon: const Icon(Icons.list, color: Colors.white),
                      label: Text(
                        'รายการงานที่รับแล้ว'.tr,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Future<void> getJobsStaus(String? jobNo, String status) async {
    final auth = BoxCacheUtil.getAuthUser;
    // final vehicle = BoxCacheUtil.getVehicle;
    //GLFunc.instance.jDecode<Map<String, dynamic>>(await Prefs.getVehicle);

    listOfDetail.clear();
    listOfDetails.clear();
    var resJobHeader = await IsarUtils.iMOTContext
            .getJobHeaders(userId: auth!.id!, statusCodes: [status]) ??
        [];

    var res = resJobHeader.firstWhereOrNull((element) => true);

    jobSelected = Rx(res!);
    String assignmentStatus = status;
    switch (status) {
      case 'ACTIVE':
        assignmentStatus = 'ACCEPT';
        break;
      case 'START':
        assignmentStatus = 'START';
        break;
      default:
    }

    var getJobDetails = await db.getJobDetail(jobNo: jobNo, userId: auth.id!);

    getJobDetails?.sort((a, b) => a.joinFlag == 'Y' ? 1 : 2);

    for (var d in getJobDetails ?? []) {
      var locations = await db.getJobLocations(jobNo: d.jobNo!);

      var locationByJobDetailId =
          locations?.where((e) => e.jobDetailId == d.id).toList();

      //

      var checkFinishAll = locationByJobDetailId?.any((e) =>
          !GetUtils.isNullOrBlank(e.jobArrivedDt)! &&
          !GetUtils.isNullOrBlank(e.jobLoadingDt)! &&
          !GetUtils.isNullOrBlank(e.jobLeavedDt)! &&
          !GetUtils.isNullOrBlank(e.jobFinishedDt)!);

      d.copyWith(
        finishFlag: drift.Value(checkFinishAll ?? false ? 'Y' : 'N'),
      );

      listOfDetails.add(d);
      // //print('load job form cache');
    }

    // //print('load job form cache');
  }

  RxBool isLoadingJobAccept = true.obs;
  List<JobHeader>? jobsAccept = [];

  // @override
  void onDetached() {
    // //print('onDetached');
  }

  // @override
  void onInactive() {
    // //print('onInactive');
    appActive = false;
  }

  // @override
  void onPaused() {
    // //print('onPaused');
    appActive = false;
  }

  // @override
  void onResumed() async {
    //('onResumed');

    isLoadingPending(true);
    await Future.delayed(const Duration(milliseconds: 200));
    isLoadingPending(false);

    appActive = true;

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    var getTrigger = prefs.getString('event.triger');
    // //print('getTrigger: $getTrigger');
    if (!GetUtils.isNullOrBlank(getTrigger)!) {
      var trigger = GLFunc.instance.deserializeObject<Map<String, dynamic>>(
          prefs.getString('event.triger')!);

      var triggerNoti = GLFunc.instance.deserializeObject<Map<String, dynamic>>(
          prefs.getString('event.triger.noti')!);
      var notiContent = NotificationContent(
        id: triggerNoti?['id'] ?? DateTime.now().millisecond,
        channelKey: triggerNoti?['channelKey'] ?? 'Notify_Other',
        criticalAlert: true,
        wakeUpScreen: false,
      ).fromMap(triggerNoti!);

      if (!Get.isDialogOpen! && GetPlatform.isMobile) {
        await FirebaseNotifications()
            .mapEventDialog(
          trigger,
          notificationContent: notiContent,
          isAppOpen: true,
        )
            .then((value) {
          // //print('xRemove');
        });
      }
      if (prefs.containsKey('event.triger')) {
        await prefs.remove('event.triger');
      }
    }
  }

  Future<void> getException() async {
    List<Map<String, dynamic>> item = [];
    // await db.connection;

    var exceptionEntry = await db.select(db.exceptionEntries).get();

    try {
      var res = await OptionRepository().getExcaptionAll();
      item.addAll(res);
    } catch (e) {
    } finally {
      if (exceptionEntry.isEmpty) {
        for (var i in item) {
          await db.insertTable(
              db.exceptionEntries,
              ExceptionEntriesCompanion.insert(
                exceptionId: drift.Value(i['exception']['Id']),
                reasonId: drift.Value(i['reasonId']),
                reasonDesc: drift.Value(i['reasonDesc']),
                statusId: drift.Value(i['statusId']),
                statusCode: drift.Value(i['statusCode']),
                exceptionCode: drift.Value(i['exception']['code']),
                exceptionENDesc: drift.Value(i['desc']['en']),
                exceptionTHDesc: drift.Value(i['desc']['th']),
                reasonRequired: drift.Value(i['reasonRequired']),
                requireImageFlag: drift.Value(i['requireImageFlag']),
                requireTimeStampFlag: drift.Value(i['requireTimeStampFlag']),
                bookingFlag: drift.Value(i['bookingFlag']),
                assignmentFlag: drift.Value(i['assignmentFlag']),
                jobFlag: drift.Value(i['jobFlag']),
              ));
          //  count++;
        }
      }

      update();
    }
    // await db.close();
  }
}
