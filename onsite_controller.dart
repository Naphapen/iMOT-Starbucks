import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:imot/Api_Repository_Service/controllers/job_detail_controller.dart';
import 'package:imot/Api_Repository_Service/controllers/jobs_controller.dart';
import 'package:imot/Api_Repository_Service/repositories/job_repository.dart';
import 'package:imot/Api_Repository_Service/repositories/onsite_repository.dart';
import 'package:imot/Api_Repository_Service/services/backgrounds/job_service.dart';
import 'package:imot/common/Other/dialog_utils.dart';
import 'package:imot/common/Other/general_function.dart';
import 'package:imot/common/cache/box_cache.dart';
import 'package:imot/common/models/form/job_activity.dart';
import 'package:imot/common/models/form/job_update_location.dart';
import 'package:imot/common/models/form/onsite/pod_onsite_model.dart';
import 'package:imot/common/models/form/onsite/qr_sop_onsite.dart';
import 'package:imot/common/models/form/onsite/sop_detail_model.dart';
import 'package:imot/common/models/form/onsite/sop_image_model.dart';
import 'package:imot/common/models/form/onsite/sop_on_model.dart';
import 'package:imot/common/models/form/onsite/start_follow_sop_model.dart';
import 'package:imot/common/models/form/onsite/start_job_onsite.dart';
import 'package:imot/common/models/form/onsite/time_frist_sop.dart';
import 'package:imot/common/models/form/onsite/transaction_img_model.dart';
import 'package:imot/common/models/form/onsite/transaction_model.dart';
import 'package:imot/common/models/form/onsite/update_all_pod_onsite.dart';
import 'package:imot/common/models/form/onsite/upload_mile_job_model.dart';
import 'package:imot/common/models/shared/response_model.dart';
import 'package:imot/common/models/shared/user_profile.dart';
import 'package:imot/common/models/view/job_header.dart';
import 'package:imot/common/shared/app_enum.dart';
import 'package:imot/common/shared/app_extension.dart';
import 'package:imot/common/widgets/buttons/button_component.dart';
import 'package:imot/database/database.dart';
import 'package:imot/pages/now_page/main_page/home_page.dart';
import 'package:imot/pages/now_page/onsite/mile_save_job.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:drift/drift.dart' as d;
import 'package:collection/collection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class OnsiteController extends FullLifeCycleController {
  UserProfile? get auth => BoxCacheUtil.getAuthUser;
  AppDatabase get db => AppDatabase.provider;
  final player = AudioPlayer();
  final jobDetailContr = Get.put(JobDetailController());
  final jobContr = Get.put(JobsController());

  RxBool isLoading = false.obs;
  RxBool isBatchLoading = false.obs;
  RxBool isRefreshImg = false.obs;
  RxBool isRefeshSopPod = false.obs;
  RxBool isStartSop = false.obs;
  RxBool isRefreshImgMile = false.obs;

  // ข้อมูลหลังจากการเริ่มงาน โดยการดึงจาก SQLITE มาเก็บไว้ในตัวแปร ลดการดึงข้อมูลจาก SQLITE โดยไม่จำเป็น
  List<OnsiteEntry> listOfBatch = [];
  List<OnsiteDetailEntry> listOfDetailSop = [];
  // List listOfDetailSop = [];
  List<OnsiteQREntry> listOfQrSop = [];

  // ตัวแปร เก็บข้อมูลใน TEMP ก่อนเอาเข้า SQLITE ลดการ LOCK ของ SQLITE ถ้ามีการ INSERT OR UPDATE แบบต่อเนื่องในปริมาณมาก
  List listOfQrLocal = [];
  List listOfBranchQrLocal = [];
  List listOfImageDhlLocal = [];

  // จำนวนข้อมูลยอด SOP DEL
  Map<String, dynamic> dashBoardPod = {};

  // ตัวแปรเก็บเวลาของการ SOPON (เก็บข้อมูลเวลา ถึง ขึ้น) โดยจับจากการถ่ายรูป Barcode DHL
  TimeFristSop arrivedTimeSopOn = TimeFristSop();

  // ตัวแปรเก็บหมายเหตุของ BATCH
  TextEditingController remarkOnsite = TextEditingController();

  // ข้อมูล Job Header ใช้สำหรับตอนเริ่มงาน และปิดงาน
  JobHeader jobHeader = JobHeader();

  //ตัวแปร เก็บรูปไมล์รถ
  dynamic imageMile;

  final TextEditingController currentMileGPS = TextEditingController();
  final TextEditingController startMile = TextEditingController();
  final TextEditingController endMileVehicle = TextEditingController();
  final TextEditingController startMileAir = TextEditingController();
  final TextEditingController endMileAir = TextEditingController();
  String dt = DateFormat('yyyy/MM/dd HH:mm:ss')
      .format(DateTime.now().toLocal())
      .toString();

  List<JobSchedulerEntriesCompanion> listDhlImgScheduler = [];
  List<String> listqr = [];
  List<Map<String, dynamic>> newItem = [];
  List<Map<String, dynamic>> newlistTxt = [];
  var itemPOD;

  DateTime dtNow = DateTime.now();
  RxBool loadingListQr = false.obs;

  void soundPlay(String sound) {
    player.setAsset('assets/sound/$sound');
    player.play();
  }

  // ชุดฟังชั่น และตัวแปร เก็บข้อมูลแบบ REALTIME ไว้ใช้ตอนกดเริ่มงาน เพื่อโชวว์ PRGRESS
  final startBatchStream = StreamController<String>.broadcast();

  void addBranchStartSop(String i) => startBatchStream.add(i);

  Stream<String> get getBranchStartSop =>
      startBatchStream.stream.asBroadcastStream();

  // ฟังชั่นเมื่อเริ่มงาน ให้ทำการ refresh OBX และลบข้อมูลในตัวแปร TEMP
  void onRefreshStartBatch() {
    isLoading(true);
    listOfBranchQrLocal.clear();
    listOfImageDhlLocal.clear();
    listOfQrLocal.clear();
    arrivedTimeSopOn = TimeFristSop();
    remarkOnsite.clear();
    isLoading(false);
  }

  // ฟังชั่นเมื่อปิดงานงาน ให้ทำการ refresh OBX และลบข้อมูลในตัวแปร TEMP
  void onRefreshStartFinish() {
    isLoading(true);
    currentMileGPS.clear();
    startMile.clear();
    endMileVehicle.clear();
    startMileAir.clear();
    endMileAir.clear();
    imageMile = null;
    jobHeader = JobHeader();
    isLoading(false);
  }

  Future<void> scanQrAddList(
      dynamic additem, dynamic data, String jobNo) async {
    loadingListQr(true);

    if (listqr.isNotEmpty) {
      for (var e in listqr) {
        if (additem == e) {
          GLFunc.showSnackbar(
            showIsEasyLoading: true,
            message: 'ท่านทำรายการซ้ำ $additem',
            type: SnackType.ERROR,
          );
          return;
        }
      }
    }

    newItem.removeWhere((v) => v['qrcode'] == additem);
    newItem.add({"qrcode": additem, "status": 'POD'});

    listqr.add(additem);
    writeQrPOD(jsonEncode(newItem), additem, jobNo);
    readGetListPOD(additem, jobNo);
    loadingListQr(false);
  }

  writeQrPOD(String text, dynamic additem, String jobNo) async {
    var cuttxt = additem.split("-");
    // final Directory directory = await getApplicationDocumentsDirectory();
    //  Directory directory = await getTemporaryDirectory();
    Directory? directory = await getExternalStorageDirectory();
    final File file = File(
        '${directory!.path}/POD_${cuttxt[1]}_${jobNo}_${auth!.employeeNo}.txt');
    await file.writeAsString(text);
    // print(t);
  }

  Future readGetListPOD(dynamic additem, String jobNo) async {
    var cuttxt = additem.split("-");
    try {
      // final Directory directory = await getApplicationDocumentsDirectory();
      Directory? directory = await getExternalStorageDirectory();
      final File file = File(
          '${directory!.path}/POD_${cuttxt[1]}_${jobNo}_${auth!.employeeNo}.txt');

      var t = await file.readAsString();

      List jdecode = await jsonDecode(t);
      newItem.clear();
      for (var e in jdecode) {
        newItem.add({"qrcode": e['qrcode'], "status": e['status']});
        loadingListQr(false);
      }

      // print(newItem);
    } catch (e) {
      print("Couldn't read file");
    }
    //return text;
  }

  // ฟังชั่น เมื่อลบข้อมูลใน sqlite ทั้งหมด  จะตรวจจากว่ามี qr card หรือไม่ ถ้าไม่มี จะทำการดึงใหม่ ถ้ามี ไม่ดึง
  Future<void> getRefreshQrCodeBatch() async {
    if (listOfBatch.length > 1) {
      await db.resetDb();
      DefaultCacheManager().emptyCache();
    }
    final auth = BoxCacheUtil.getAuthUser;

    // ดึงข้อมูล qr card ใน sqlite
    var getOr = await (db.select(db.onsiteQREntries)).get();

    // ตรวจสอบข้อมูล qr card ใน sqlite
    if (listOfBatch.isNotEmpty &&
        listOfBatch.first.status != "SOP-ON" &&
        getOr.isEmpty) {
      isBatchLoading(true);

      // ดึงข้อมูล card จาก api iems
      var res =
          await OnsiteRepository().getQrCodeByBatch(listOfBatch.first.batchNo);

      if (res['Results'].isEmpty) {
        isBatchLoading(false);
        GLFunc.showSnackbar(
          showIsEasyLoading: true,
          message: 'ไม่พบข้อมูลงาน',
          type: SnackType.WARNING,
        );
        Get.back();
        return;
      }

      List<OnsiteQREntry> listOnsiteQr = [];

      for (var e in res['Results']) {
        SopOnModel sopOnModel = SopOnModel.fromMap(e);

        // ดึงข้อมูล Onsite Detail ตาม สาขาของ qr card ที่ดึงมา
        var getDetailOnsite = await (db.select(db.onsiteDetailEntries)
              ..where((tbl) => tbl.branchCode
                  .equals(sopOnModel.cardOnsiteBarcode!.split('-')[1])))
            .getSingleOrNull();

        // ดึงข้อมูล qr card ใน sqlite
        var getQrcode = await (db.select(db.onsiteQREntries)
              ..where(
                  (tbl) => tbl.qrcode.equals(sopOnModel.cardOnsiteBarcode!)))
            .getSingleOrNull();

        // ใส่ค่าเข้าไปในตัวแปร qr card
        if (getQrcode == null) {
          getQrcode = OnsiteQREntry(
            onsiteDetaildEntryId: getDetailOnsite?.id ?? 0,
            qrcode: sopOnModel.cardOnsiteBarcode,
            batchNo: getDetailOnsite?.batchNo,
            status: sopOnModel.statusCode,
            statusDt: sopOnModel.statusDt,
            createdDt: sopOnModel.createdDt!,
            createdBy: auth!.userEnName!,
            modifiedDt: sopOnModel.modifiedDt,
            modifiedBy: auth.userEnName,
          );
        } else {
          // ถ้ามีข้อมูล card อยู่ ซึ่งเป็น SOP แต่ใน api เป็น POD จะปรับเป็น POD
          if (getQrcode.status == "SOP-ON" && sopOnModel.statusCode == "POD") {
            getQrcode = getQrcode.copyWith(
              status: d.Value(sopOnModel.statusCode),
              statusDt: d.Value(sopOnModel.statusDt),
            );
          }
        }
        listOnsiteQr.add(getQrcode);
      }

      // insert ข้อมูล qr card ลงไปใน sqlite
      await db.batchActionEntries(
        action: SqlAction.INSERRT_CF_UPDATE,
        table: db.onsiteQREntries,
        entitys: listOnsiteQr,
      );

      // ดึงข้อมูล qr card ทั้งหมด (หลังจาก insert เข้าไปแล้ว)
      var getAllOnsiteQr = await (db.select(db.onsiteQREntries)).get();

      List<Map<String, dynamic>> branchList = [];

      // แยกสาขาของ qr card ทั้งหมด
      for (var e in getAllOnsiteQr) {
        var item = branchList
            .where((x) => x['idDetail'] == e.onsiteDetaildEntryId)
            .firstOrNull;

        if (item == null) {
          var branch = {
            'idDetail': e.onsiteDetaildEntryId,
            'totalScan': 1,
            'totalPod': e.status == "POD" ? 1 : 0,
          };

          branchList.add(branch);
        } else {
          var index = branchList
              .indexWhere((x) => x['idDetail'] == e.onsiteDetaildEntryId);

          var newItem = {
            'idDetail': item['idDetail'],
            'totalScan': item['totalScan'] + 1,
            'totalPod':
                e.status == "POD" ? item['totalPod'] + 1 : item['totalPod'],
          };
          branchList.removeAt(index);
          branchList.insert(index, newItem);
        }
      }

      // อัพเเดต จำนวน total scan และ total pod ใน Onsite Detail
      for (var xx in branchList) {
        var getOnsiteDetail = await (db.select(db.onsiteDetailEntries)
              ..where((tbl) => tbl.id.equals(xx['idDetail'])))
            .getSingleOrNull();

        if (getOnsiteDetail != null) {
          getOnsiteDetail = getOnsiteDetail.copyWith(
            totalScan: d.Value(xx['totalScan']),
            totalPOD: d.Value(xx['totalPod']),
          );

          await db.update(db.onsiteDetailEntries).replace(getOnsiteDetail);
        }
      }

      // ดึงข้อมูล จำนวน sop และ pod มาใหม่ เพื่อ display
      await getSumSopDetail(listOfBatch.first.batchNo!);
      isBatchLoading(false);
    }
  }

  // ฟังชั่น ลบข้อมูลใน sqlite หลังจากการปิดงาน
  Future<void> onClearDbWhenFinish(String jobNo) async {
    await db.delete(db.onsiteEntries).go();
    await db.delete(db.onsiteDetailEntries).go();
    await db.delete(db.onsiteQREntries).go();
    await (db.delete(db.jobHeaderEntries)
          ..where((tbl) => tbl.jobNo.equals(jobNo)))
        .go();
    await (db.delete(db.jobDetailEntries)
          ..where((tbl) => tbl.jobNo.equals(jobNo)))
        .go();
    await (db.delete(db.jobLocationEntries)
          ..where((tbl) => tbl.jobNo.equals(jobNo)))
        .go();
  }

  // ฟังชั่น start Job ( Only job header)
  Future<void> updateStartJob() async {
    final auth = BoxCacheUtil.getAuthUser;
    final vehicle = BoxCacheUtil.getVehicle;
    var position = await jobDetailContr.locationService.getLocation();
    var battery = await jobDetailContr.batteryService.getBattery();
    var fcmToken = BoxCacheUtil.getFCMToken;

    var mapDataOnsite = JobActivityForm(
      refId: jobHeader.id.toString(),
      assignmentNo: null,
      batteryPercent: battery,
      bookingNo: null,
      licensePlate: '${vehicle?.licensePlate}',
      licenseProvince: '${vehicle?.licenseProvince}',
      supplierFlag: '${vehicle?.vehicleSupplierFlag}',
      startMileGps: double.tryParse(currentMileGPS.text) ?? 0,
      startMileVehicle: double.tryParse(startMile.text) ?? 0,
      startMileAir: double.tryParse(startMileAir.text) ?? 0,
      endMileGps: null,
      endMileVehicle: null,
      endMileAir: null,
      driverNo: auth!.employeeId,
      fcmToken: fcmToken,
      remark: null,
      routeCode: auth.vehicleWithMobile?.routeCode,
      jobNo: jobHeader.jobNo,
      mobileActivityId: MobileActivity.Start.id,
      mobileActivityCode: MobileActivity.Start.name,
      geoLatitude: '${position?.latitude}',
      geoLongitude: '${position?.longitude}',
      createdBy: auth.employeeId,
      createdDt: DateTime.now().toIso8601String(),
      mobileId: BoxCacheUtil.appUuId(),
    );

    JobHeaderEntry? getHeader;

    var findJobHeader = await db.getJobHeadersSingle(
      statusCodes: ['START'],
      userId: auth.id!,
    );

    if (findJobHeader != null && findJobHeader.jobNo == jobHeader.jobNo) {
      getHeader = findJobHeader;
    } else {
      getHeader = await db.getJobHeadersSingle(jobNo: jobHeader.jobNo);
    }

    var getlastDh = await db.summaryDashboard();
    String syncFlag = 'N';

    if (findJobHeader != null) {
      List<String> statusList = ['FINISH', 'CANCEL', 'REJECT', 'C-REJ'];
      var res = await JobRepository().fetchDataJobDetail(jobHeader.jobNo!);

      if (statusList.contains(res?.results?['item']?['jobLastStatusCode'])) {
        db.deleteJobLocal(findJobHeader.jobNo!);
      }
    }

    getHeader = getHeader!.copyWith(
      startMileGps: d.Value(mapDataOnsite.startMileGps),
      startMileVehicle: d.Value(mapDataOnsite.startMileVehicle),
    );

    if (getHeader.jobLastStatusCode != 'START') {
      var totalAccept = (getlastDh!.totalAccept) - 1;

      var countDashboard = await db.getSummaryDashboardByJobLocation(
        jobNo: getHeader.jobNo!,
      );

      getlastDh = getlastDh.copyWith(
        totalAccept: totalAccept,
        jobNo: d.Value(jobHeader.jobNo),
        totalDelvery: countDashboard?.totalDelvery ?? 0,
        totalPickup: 1,
        total: countDashboard?.total ?? 0,
        totalReturn: 0,
      );
    }

    mapDataOnsite.createdDt = DateTime.now().toIso8601String();

    StartJobOnsite dataJsonOnsite = StartJobOnsite();

    dataJsonOnsite = dataJsonOnsite.copyWith(
      jobNo: mapDataOnsite.jobNo,
      employeeNo: mapDataOnsite.driverNo,
      createdDt: mapDataOnsite.createdDt,
      geoLatitude: mapDataOnsite.geoLatitude,
      geoLongitude: mapDataOnsite.geoLongitude,
      routeAssignId: mapDataOnsite.routeAssignId ?? 0,
      loggedInFullname: auth.userName,
      supplierFlag: mapDataOnsite.supplierFlag,
      startMileGps: mapDataOnsite.startMileGps,
      startMileVehicle: mapDataOnsite.startMileVehicle,
      startMileAir: mapDataOnsite.startMileAir ?? 0,
      batteryPercent: mapDataOnsite.batteryPercent,
      routeCode: mapDataOnsite.routeCode,
      driverNo: mapDataOnsite.driverNo,
      fcmToken: mapDataOnsite.fcmToken,
      licensePlate: mapDataOnsite.licensePlate,
      licenseProvince: mapDataOnsite.licenseProvince,
      endMileGps: mapDataOnsite.endMileGps,
      endMileVehicle: mapDataOnsite.endMileVehicle,
      deviceId: mapDataOnsite.mobileId,
      skipFingerScanFlag: mapDataOnsite.skipFingerScanFlag,
      remark: mapDataOnsite.remark,
    );

    TransactionModel dataStartApi = TransactionModel();

    dataStartApi = dataStartApi.copyWith(
      jobNo: mapDataOnsite.jobNo,
      jobID: getHeader.id,
      detailID: 0,
      locationID: 0,
      actionType: "ON-START-JOB",
      priorityLevel: 3,
      jsonString: dataJsonOnsite.toJson().toString(),
    );

    ResponseModel? resStartJob;

    // ยิงขึ้น API ทันที เนืองจากขั้นตอนนี้ ต้อง Realtime เพื่อเอา respone
    try {
      syncFlag = 'Y';

      resStartJob = await JobRepository().insertTransaction(dataStartApi);

      if (resStartJob.code != "0000") {
        return GLFunc.showSnackbar(
          message: resStartJob.message!.th!,
          type: SnackType.WARNING,
        );
      } else {
        GLFunc.showSnackbar(
          message: resStartJob.message!.th!,
          type: SnackType.SUCCESS,
        );
      }
    } catch (e) {
      syncFlag = 'N';

      GLFunc.showSnackbar(
        message: 'เกิดข้อผิดพลาด กรุณาลองใหม่',
        type: SnackType.ERROR,
      );
    }

    getHeader = getHeader.copyWith(
      startWorkTime: d.Value(DateTime.now().toIso8601String()),
      jobLastStatusCode: d.Value(toBeginningOfSentenceCase("START")),
    );

    var jobEntry = JobSchedulerEntriesCompanion.insert(
      url: syncFlag == "Y" ? 'SUCCESS' : '',
      activityType: const d.Value("ON-START-JOB"),
      request: d.Value(dataStartApi.toJson()),
      syncFlag: d.Value(syncFlag),
      createBy: d.Value(auth.userName),
      createDt: d.Value(DateTime.now().toIso8601String()),
      counter: const d.Value(0),
      response: syncFlag == "Y"
          ? d.Value(resStartJob?.toJson().toString())
          : const d.Value(null),
      statusCode: syncFlag == "Y" ? const d.Value('200') : const d.Value(null),
    );

    if (syncFlag == "Y") {
      db.updateTable(db.jobHeaderEntries, getHeader);

      db.updateTable(db.dashboardEntries, getlastDh!);
    }

    if (auth.vehicleSupplierFlag != "Y") {
      // อัพโหลดรูปไมล์รถตอนเริ่มงาน
      await uploadMileOnsite(jobHeader.jobNo!, "MILE-START");
    }

    await db.jobSchedulerEntries.insertOne(jobEntry);
  }

  // ฟังชั่น start Job header
  Future<void> startHeaderJob(String jobNo) async {
    var camera = await Permission.camera.status;
    var location = await Permission.location.status;

    if (!camera.isGranted) {
      await Permission.camera.request();
    }

    if (!location.isGranted) {
      await Permission.location.request();
    }

    final auth = BoxCacheUtil.getAuthUser;
    final vehicle = BoxCacheUtil.getVehicle;

    await getJobHeader(jobNo);

    String systemLicense = '${jobHeader.licensePlate}'.trim();

    String localLicense = '${vehicle?.licensePlate}'.trim();

    if (systemLicense != localLicense) {
      GLFunc.showSnackbar(
        message:
            'ขออภัยใบสั่งสั่งงานเลขที่ ${jobHeader.jobNo} ถูกรับงานด้วยหมายรถทะเบียน ${jobHeader.licensePlate} ${vehicle?.licenseProvince ?? ''} ไม่สามารถเริ่มงานได้',
        showIsEasyLoading: true,
        type: SnackType.INFO,
        duration: const Duration(seconds: 5),
      );
      return;
    }

    GLFunc.instance.showLoading();

    ResponseModel checkJob = ResponseModel();

    // ยิง api เช็คว่า job นี้ สามารถเริ่มงานได้หรือไม่
    try {
      var res = await JobRepository().checkJob(jobNo, "START");
      checkJob = res;
    } catch (e) {
      GLFunc.showSnackbar(
        showIsEasyLoading: true,
        message: 'เกิดข้อผิดพลาด กรูณาลองใหม่',
        type: SnackType.ERROR,
      );
      return;
    }

    if (checkJob.code != "OK") {
      GLFunc.showSnackbar(
        showIsEasyLoading: true,
        message: checkJob.message!.th!,
      );
      return;
    }

    double currentMileGPS = 0;
    bool? takeMile = false;

    // ดึงข้อมูล current mile ปัจจุบัน จาก mappoint
    try {
      var res = await JobRepository().getMileVehilce();

      if (res != null && (res.results ?? []).isNotEmpty) {
        currentMileGPS = res.results!.first.milage;
      }
    } catch (e) {}

    // แยกรถบริษัท กับ รถร่วม
    if (auth!.vehicleSupplierFlag != "Y") {
      GLFunc.instance.hideLoading();

      // ไปหน้า ถ่ายรูปเลขไมล์ และ บันทึกไมล์รถ
      takeMile = await Get.to(
        () => MileSaveJob(
          title: ListTile(
            visualDensity: const VisualDensity(
              horizontal: 1,
              vertical: -4,
            ),
            contentPadding: EdgeInsets.zero,
            title: Text(
              'ยืนยันการเริ่มปฏิบัติงาน',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18.sm,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              'เลขที่ใบสั่งงาน: ${jobNo.toString()}',
              style: TextStyle(
                fontWeight: FontWeight.normal,
                fontSize: 14.sm,
                color: Colors.white,
              ),
            ),
          ),
          jobNo: jobNo,
          mileGps: currentMileGPS,
          event: JobStatus.START,
        ),
      );

      // เมื่อถ่ายรูปและบันทึกเลขไมล์สำเร็จ ให้ดำเนินการยิงข้อมูลขึ้น API (Realtime)
      if (takeMile ?? false == true) {
        GLFunc.instance.showLoading();
        await updateStartJob();
        onRefreshStartFinish();
        GLFunc.instance.hideLoading();

        Get.offAll(HomePage());
      }
    } else {
      GLFunc.instance.showLoading();
      await updateStartJob();
      onRefreshStartFinish();
      GLFunc.instance.hideLoading();

      Get.offAll(HomePage());
    }
  }

  // ฟังชั่น finish job ( Send API Realtime)
  Future<void> updateFinishJob({double? mileGps}) async {
    var auth = BoxCacheUtil.getAuthUser;
    var position = await jobDetailContr.locationService.getLocation();
    var battery = await jobDetailContr.batteryService.getBattery();
    var fcmToken = BoxCacheUtil.getFCMToken;
    var vehicle = BoxCacheUtil.getVehicle;

    JobActivityForm mapData = JobActivityForm(
      refId: jobHeader.id.toString(),
      assignmentNo: null,
      batteryPercent: battery,
      bookingNo: null,
      licensePlate: '${vehicle?.licensePlate}',
      licenseProvince: '${vehicle?.licenseProvince}',
      supplierFlag: '${vehicle?.vehicleSupplierFlag}',
      startMileGps: jobHeader.startMileGps ?? 0,
      startMileVehicle: jobHeader.startMileVehicle ?? 0,
      startMileAir: jobHeader.startMileAir ?? 0,
      endMileGps: mileGps,
      endMileVehicle: double.tryParse(endMileVehicle.text) ?? 0,
      endMileAir: jobHeader.endMileAir ?? 0,
      driverNo: auth?.employeeId,
      employeeId: auth!.employeeId,
      fcmToken: fcmToken,
      remark: null,
      routeCode: auth.vehicleWithMobile!.routeCode,
      jobNo: jobHeader.jobNo,
      mobileActivityId: MobileActivity.Finish.id,
      mobileActivityCode: MobileActivity.Finish.name,
      geoLatitude: position?.latitude.toString(),
      geoLongitude: position?.longitude.toString(),
      createdBy: auth.userThName ?? auth.userEnName,
      createdDt: DateTime.now().toIso8601String(),
      mobileId: BoxCacheUtil.appUuId(),
    );

    TransactionModel transactionFinish = TransactionModel(
      jobNo: mapData.jobNo,
      jobID: double.tryParse(mapData.refId!) ?? 0,
      detailID: 0,
      locationID: 0,
      actionType: "ON-FINISH-JOB",
      priorityLevel: 3,
      jsonString: mapData.toJson().toString(),
    );

    String syncFlag = "Y";

    var jobFinishEntry = JobSchedulerEntriesCompanion.insert(
      url: '',
      activityType: const d.Value("ON-FINISH-JOB"),
      request: d.Value(transactionFinish.toJson()),
      syncFlag: d.Value(syncFlag),
      createBy: d.Value(auth.userName),
      createDt: d.Value(DateTime.now().toIso8601String()),
      counter: const d.Value(0),
    );

    // ยิงขึ้นไปอัพเดต API Realtime
    try {
      var res = await JobRepository().insertTransaction(transactionFinish);

      if (res.code != "0000") {
        return GLFunc.showSnackbar(
          message: res.message!.th!,
          type: SnackType.ERROR,
        );
      }

      jobFinishEntry = jobFinishEntry.copyWith(
        response: d.Value(res.toJson().toString()),
        url: const d.Value('SUCCESS'),
        statusCode: const d.Value("200"),
        counter: const d.Value(1),
      );
    } catch (e) {
      jobFinishEntry = jobFinishEntry.copyWith(
        syncFlag: const d.Value("N"),
        counter: const d.Value(1),
      );
    }

    await db.insertTable(db.jobSchedulerEntries, jobFinishEntry);

    // ดึงข้อมูล sqlite Dashboard
    var getlastDh = await db.summaryDashboard();

    // ปรับข้อมูล Dashboard ก่อนบันทึกขึ้นไปใหม่
    getlastDh = getlastDh?.copyWith(
      jobNo: const d.Value(null),
      totalDelvery: 0,
      totalPickup: 0,
      total: 0,
      totalReturn: 0,
    );

    await db.update(db.dashboardEntries).replace(getlastDh!);

    if (auth.vehicleSupplierFlag != "Y") {
      await uploadMileOnsite(jobHeader.jobNo!, "MILE-FINISH");
    }

    await onClearDbWhenFinish(mapData.jobNo!);
  }

  // ฟังชั่น อัพโหลดรูปไมล์ และ ข้อมูลขึ้น API
  Future<void> uploadMileOnsite(String jobNo, String actionImg) async {
    var auth = BoxCacheUtil.getAuthUser;

    var getOnsiteHeader = await (db.select(db.onsiteEntries)
          ..where((tbl) => tbl.jobNo.equals(jobNo)))
        .getSingleOrNull();

    String fileName =
        '$actionImg-$jobNo-${DateFormat("yyyyMMddHms").format(DateTime.now())}.jpg';
//imageMile
    ImgList imgList = ImgList(
      fileName: fileName,
      data: base64Encode(imageMile), //'${img}'
    );
    Map ojb = {};
    var img = jsonDecode(imgList.toJson());
    ojb.addAll({"img1": img});
    // ข้อมูลที่จะขึ้นไป Transaction IMG

    TransactionImgModel transactionImg = TransactionImgModel(
        jobNo: jobHeader.jobNo!,
        jobID: jobHeader.id!.toInt(),
        detailID: 0,
        locationID: 0,
        shipmentNo: '',
        batchNo: getOnsiteHeader?.batchNo ?? "",
        // actionType: actionImg,
        imgList: ojb,
        actionType: "ON-IMG-MILE",
        actionDT: dtNow.toIso8601String(),
        statusCode: "SUCCESS",
        statusDt: dtNow.toIso8601String(),
        customerItmsCode: "0105541008688",
        customerVipFlag: "Y",
        shipmentPrefix: "Starbuck",
        referenceCode: "000",
        fileName: "",
        jsonByteArray: "");

    Map ojbMlie = {};
    ImgList imgListMile = ImgList(
      fileName: fileName,
      data: "", //'${img}'
    );

    var imgMlie = jsonDecode(imgListMile.toJson());
    ojbMlie.addAll({"img1": imgMlie});
    UploadMileJobModel uploadMileJobModel = UploadMileJobModel(
        currentMile: actionImg == "MILE-FINISH"
            ? double.tryParse(endMileVehicle.text) ?? 0
            : double.tryParse(startMile.text) ?? 0,
        action: actionImg == "MILE-FINISH" ? "END" : "START",
        jobNo: jobHeader.jobNo!,
        jobID: jobHeader.id!.toInt(),
        locationID: 0,
        detailID: 0,
        batchNo: getOnsiteHeader?.batchNo ?? "",
        driverFullname: auth!.userEnName,
        imgList: ojbMlie,
        actionType: "ON-IMG-MILE",
        actionDT: dtNow.toIso8601String(),
        statusCode: "SUCCESS",
        statusDt: dtNow.toIso8601String(),
        customerItmsCode: "0105541008688",
        customerVipFlag: "Y",
        shipmentPrefix: "Starbuck",
        referenceCode: "000",
        fileName: "",
        jsonByteArray: "");

    // ข้อมูลที่จะขึ่้นไป Transaction Header
    TransactionModel transactionMile = TransactionModel(
      jobNo: jobHeader.jobNo!,
      jobID: jobHeader.id!,
      detailID: 0,
      locationID: 0,
      shipmentNo: '',
      batchNo: getOnsiteHeader?.batchNo ?? "",
      actionType: actionImg,
      actionDT: dtNow.toIso8601String(),
      priorityLevel: 0,
      jsonString: uploadMileJobModel.toJson(),
    );

    var imageMileScheduler = JobSchedulerEntriesCompanion.insert(
      url: '',
      activityType: const d.Value('ON-IMG-MILE'),
      request: d.Value(transactionImg.toJson()),
      syncFlag: const d.Value('N'),
      createBy: d.Value(auth.userName),
      createDt: d.Value(DateTime.now().toIso8601String()),
      counter: const d.Value(0),
    );

    var imageMileHeader = JobSchedulerEntriesCompanion.insert(
      url: '',
      activityType: const d.Value('ON-IMG-MILE-HEADER'),
      request: d.Value(transactionMile.toJson()),
      syncFlag: const d.Value('N'),
      createBy: d.Value(auth.userName),
      createDt: d.Value(DateTime.now().toIso8601String()),
      counter: const d.Value(0),
    );

    await db.insertOne(db.jobSchedulerEntries, imageMileScheduler);
    await db.insertOne(db.jobSchedulerEntries, imageMileHeader);
  }

  // ฟังชั่น ค้นหา JobHeader ไว้ใช้สำหรับ START JOB และ FINISH JOB
  Future<void> getJobHeader(String jobNo) async {
    var res = await (db.select(db.jobHeaderEntries)
          ..where((tbl) => tbl.jobNo.equals(jobNo)))
        .getSingleOrNull();

    if (res != null) {
      jobHeader = JobHeader.fromJson(res.toJsonString());
    }
  }

  // ฟังชั่น ดึงข้อมูล สาขาทั้งหมดที่ทำการ SOP ON ไปไว้ในตัวแปร
  Future<void> getDetailAllSop(String batchNo) async {
    // await onRefresh();

    isLoading(true);

    if (await GLFunc.isClientOnline()) {
      var res = await OnsiteRepository().getBatchCheckLocal(batchNo);

      if (res != null) {
        var newMap = res.map((e) => e['BranchList']);
      }

// if (res != null) {
//    for (var n in res.toList()) {
//             onsiteDetail = OnsiteDetailEntry(

//               totalScan: n[c]['estPackage'],
//               //  id: dRow.id?.toInt(),
//               //dRow.id?.toInt(),

//             );

//             await iMOTContext.insertOne(
//               iMOTContext.onsiteDetailEntries,
//               onsiteDetail,
//             );

//             await iMOTContext.batchActionEntries(
//               action: SqlAction.INSERRT_CF_UPDATE,
//               table: iMOTContext.onsiteDetailEntries,
//               entitys: [onsiteDetail],
//             );
//             c++;
//             print(n['BranchOnsiteCode']);
//           }
// }
    }

    listOfDetailSop = await (db.select(db.onsiteDetailEntries)
          ..where(
              (tbl) => tbl.batchNo.equals(batchNo) & tbl.totalScan.isNotNull()))
        .get();

    isLoading(false);
    // listOfDetailSop = await (db.select(db.onsiteDetailEntries)
    //       ..where(
    //           (tbl) => tbl.batchNo.equals(batchNo) & tbl.totalScan.isNotNull()))
    //     .get();
  }

  // ฟังชั่น Finish Job
  Future<void> finishJobOnsite(OnsiteEntry data) async {
    var auth = BoxCacheUtil.getAuthUser;

    ResponseModel checkJob = ResponseModel();

    try {
      var res = await JobRepository().checkJob(data.jobNo!, "FINISH");
      checkJob = res;
    } catch (e) {
      GLFunc.showSnackbar(
        showIsEasyLoading: true,
        message: 'เกิดข้อผิดพลาด กรูณาลองใหม่',
        type: SnackType.ERROR,
      );
      return;
    }

    if (checkJob.code != "OK") {
      GLFunc.showSnackbar(
        showIsEasyLoading: true,
        message: checkJob.message!.th!,
      );
      return;
    }

    await getJobHeader(data.jobNo!);

    if (auth!.vehicleSupplierFlag != "Y") {
      double finishMileGps = 0;

      try {
        var res = await JobRepository().getMileVehilce();

        if (res != null && (res.results ?? []).isNotEmpty) {
          finishMileGps = res.results!.first.milage;
        }
      } catch (e) {}

      var takeMile = await Get.to(
        () => MileSaveJob(
          title: ListTile(
            visualDensity: const VisualDensity(
              horizontal: 1,
              vertical: -4,
            ),
            contentPadding: EdgeInsets.zero,
            title: Text(
              'ยืนยันการปิดงาน',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18.sm,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              'เลขที่ใบสั่งงาน: ${data.jobNo.toString()}',
              style: TextStyle(
                fontWeight: FontWeight.normal,
                fontSize: 14.sm,
                color: Colors.white,
              ),
            ),
          ),
          jobNo: data.jobNo!,
          event: JobStatus.FINISH,
          mileGps: finishMileGps,
        ),
      );

      if (takeMile ?? false == true) {
        GLFunc.instance.showLoading(null, false);

        await updateFinishJob(mileGps: finishMileGps);
        onRefreshStartFinish();
        GLFunc.instance.hideLoading();

        Get.offAll(HomePage());
      }
    } else {
      GLFunc.instance.showLoading();

      await updateFinishJob();
      onRefreshStartFinish();
      GLFunc.instance.hideLoading();

      Get.offAll(HomePage());
    }
  }

  Future txtFileDelete() async {
    Directory? directory = await getExternalStorageDirectory();
    List files = directory!
        .listSync()
        .where((e) => e.path.endsWith('${auth!.employeeNo}.txt'))
        .toList();
    print(files);
    try {
      if (files.isNotEmpty) {
        for (var file in files) {
          await file.delete();
        }
      }
    } catch (e) {
      print(e);
    }

    // List<StorageInfo> storageInfo = await PathProviderEx.getStorageInfo();
  }

  // ฟังชั่นการ POD
  Future<void> submitPod({
    required String qrCode,
    required int detailId,
    required String batchNo,
    required String jobNo,
  }) async {
    var auth = BoxCacheUtil.getAuthUser;
    var position = await jobDetailContr.locationService.getLocation();
    var battery = await jobDetailContr.batteryService.getBattery();
    var fcmToken = BoxCacheUtil.getFCMToken;
    var vehicle = BoxCacheUtil.getVehicle;
    //List sumQr = [];
    try {
      var check = await (db.select(db.onsiteQREntries)
            ..where(
                (tbl) => tbl.qrcode.equals(qrCode) & tbl.status.equals("POD")))
          .get();

      if (check.isNotEmpty) {
        return;
      }
      // tbl.onsiteDetaildEntryId.equals(detailId)

      // ดึงข้อมูล ONSITE DETAIL ออกมา โดยค้นหาจาก ID DETAIL ONSITE
      var getDetail = await (db.select(db.onsiteDetailEntries)
            ..where((tbl) => tbl.id.equals(detailId)))
          .getSingleOrNull();
      // var getDetail = await (db.select(db.onsiteDetailEntries)
      //       ..where((tbl) => tbl.id.equals(detailId)))
      //     .getSingleOrNull();

      // ดึงจำนวน POD ของ Card ทั้งหมด โดยค้นหาจาก ID DETAIL ONSITE เพื่อทำการอัพเดตยอด POD ทั้งหมดของสาขานั้น
      var getSumPod = await (db.select(db.onsiteDetailEntries)
            ..where((tbl) =>
                    // tbl.qrcode.equals(qrCode) &
                    tbl.id.equals(detailId)
                // tbl.status.equals("SOP")
                ))
          .get(); //สาขา
      var mapSum = getSumPod.map((e) => e.totalPOD);

      // ดึงข้อมูล JOB LOCATION ออกมา เพื่อทำการบันทุกเวลา ถึง ขึ้น เสร็จ ออก โดยเวลาต้องไม่มีค่า (จะได้ไม่บันทึกข้อมูลซ้ำ)
      var getLocation = await (db.select(db.jobLocationEntries)
            ..where((tbl) =>
                    tbl.id.equals(getDetail!.id!.toDouble()) &
                    tbl.deliveryFlag.equals("Y")
                // tbl.jobArrivedDt.isNull() &
                // tbl.jobLoadingDt.isNull()
                ))
          .getSingleOrNull();

      // ดึงข้อมูล สาขา ของ QR CODE ที่แสกน

      List<JobUpdateLocation> updateLocations = [];
      String statusPod = "ON-POD";
      // print("count --- > ${listqr.length}");
      //sumQr.add(listqr);

      // บันทึกข้อมูล ถึง ขึ้น ใน JOB LOCATION
      if (getLocation != null) {
        getLocation = getLocation.copyWith(
          jobArrivedDt: d.Value(DateTime.now().toIso8601String()),
          jobLoadingDt: d.Value(DateTime.now().toIso8601String()),
          jobArrivedLatitude: d.Value(position?.latitude.toString()),
          jobArrivedLongitude: d.Value(position?.longitude.toString()),
          jobLoadingLatitude: d.Value(position?.latitude.toString()),
          jobLoadingLongitude: d.Value(position?.longitude.toString()),
        );

        JobUpdateLocation jobUpdateLocationArrvide = JobUpdateLocation(
          id: getLocation.id!,
          jobDetailId: getLocation.jobDetailId!,
          type: "ARRIVED",
          fcmToken: fcmToken,
          licenseProvince: vehicle!.licenseProvince,
          geoLatitude: position?.latitude.toString(),
          geoLongitude: position?.longitude.toString(),
          batteryPercent: battery,
          createdDt: dtNow.toIso8601String(),
          actPackage: listqr.length,
          actManualPackage: listqr.length,
        );

        JobUpdateLocation jobUpdateLocationLoading = JobUpdateLocation(
          id: getLocation.id!,
          jobDetailId: getLocation.jobDetailId!,
          type: "LOADING",
          fcmToken: fcmToken,
          licenseProvince: vehicle.licenseProvince,
          geoLatitude: position?.latitude.toString(),
          geoLongitude: position?.longitude.toString(),
          batteryPercent: battery,
          createdDt: dtNow.toIso8601String(),
          actPackage: listqr.length,
          actManualPackage: listqr.length,
        );

        updateLocations.add(jobUpdateLocationArrvide);
        updateLocations.add(jobUpdateLocationLoading);

        statusPod = "ON-POD-F";

        // อัพเดต JOB LOCATION เข้าไปใหม่ (บันทึกเวลา ถึง ขึ้น)
        await db.update(db.jobLocationEntries).replace(getLocation);
      }
      var count =
          (getSumPod[0].totalPOD == null) ? 0 + 1 : getSumPod[0].totalPOD! + 1;
      //getSumPod.length + 1;
      // ปรับเปลี่ยนข้อมูลของ Onsite Detail โดยเพิ่มจำนวนยอด Total POD เข้าไป
      getDetail = getDetail?.copyWith(
        totalPOD: d.Value(count),
        modifiedBy: d.Value(auth?.userEnName),
        modifiedDt: d.Value(DateTime.now().toIso8601String()),
      );

      // อัพเดตข้อมูล Card และ Onsite Detail ใหม่

      await db.update(db.onsiteDetailEntries).replace(getDetail!);

      // ทำการเรียกฟังชั่น ดึงข้อมูลใหม่ เพื่ออัพเดต ตัวแปร ไว้แสดงผล
      await getQrAllSop(detailId);
      await getDetailAllSop(batchNo);

      // ตรวจสอบยอด POD และ TOTAL SCAN ว่าเท่ากันหรือไม่ โดยตรวจสอบทุกสาขา เพื่อไว้อัพเดต Finish Batch
      var totalDetailPod = listOfDetailSop
          .where((e) => e.totalScan == e.totalPOD)
          .toList()
          .length;

      // ดึงข้อมูล สาขาที่ทำการ SOP โดยดึงจำนวนสาขา ไม่ได้ดึงยอด Package
      var totalDetailSop =
          listOfDetailSop.where((x) => (x.totalScan ?? 0) > 0).toList().length;
      var checkSuccessPod = await (db.select(db.onsiteDetailEntries)
            ..where((tbl) => tbl.id.equals(detailId)))
          .get();
      // ตรวจสอบว่า ยอดสแกนเข้าไป และ ยอด POD เท่ากันหรือไม่
      // if (checkSuccessPod.isNotEmpty &&
      //     checkSuccessPod.first.totalScan == checkSuccessPod.first.totalPOD) {
      // ดึงข้อมูล JOB LOCATION มาใหม่ เพิ่อทำการอัพเดต เสร็จ ออก
      var getLocationFinish = await (db.select(db.jobLocationEntries)
            ..where(
                (tbl) => tbl.id.equals(checkSuccessPod.first.id!.toDouble())))
          .get();

      DateTime dtNowF = DateTime.now();
      // สร้างข้อมูล อัพเดต เวลาเสร็จ ออก เพิ่อ อัพเดต SQLITE
      getLocationFinish.first = getLocationFinish.first.copyWith(
        jobFinishedDt: d.Value(DateTime.now().toIso8601String()),
        jobLeavedDt: d.Value(DateTime.now().toIso8601String()),
        jobFinishedLatitude: d.Value(position?.latitude.toString()),
        jobFinishedLongitude: d.Value(position?.longitude.toString()),
        jobLeavedLatitude: d.Value(position?.latitude.toString()),
        jobLeavedLongitude: d.Value(position?.longitude.toString()),
      );

      // สร้างข้อมูล LOCATION UPDATE เวลา เสร็จ และ ออก
      JobUpdateLocation jobUpdateLocationFinished = JobUpdateLocation(
          id: getLocationFinish.first.id!,
          jobDetailId: getLocationFinish.first.jobDetailId!,
          type: "FINISHED",
          fcmToken: fcmToken,
          licenseProvince: vehicle!.licenseProvince,
          geoLatitude: position?.latitude.toString(),
          geoLongitude: position?.longitude.toString(),
          batteryPercent: battery,
          createdDt: dtNowF.toIso8601String(),
          actPackage: listqr.length
          // actPackage: checkSuccessPod.first.totalPOD,
          );

      JobUpdateLocation jobUpdateLocationLeaved = JobUpdateLocation(
          id: getLocationFinish.first.id!,
          jobDetailId: getLocationFinish.first.jobDetailId!,
          type: "LEAVED",
          fcmToken: fcmToken,
          licenseProvince: vehicle.licenseProvince,
          geoLatitude: position?.latitude.toString(),
          geoLongitude: position?.longitude.toString(),
          batteryPercent: battery,
          createdDt: dtNowF.toIso8601String(),
          actPackage: listqr.length
          // actPackage: checkSuccessPod.first.totalPOD,
          );

      updateLocations.add(jobUpdateLocationFinished);
      updateLocations.add(jobUpdateLocationLeaved);

      statusPod = "ON-POD-E";

      // อัพเดต JOB LOCATION ใน SQLITE
      await db.update(db.jobLocationEntries).replace(getLocationFinish.first);
      // }

      // ตรวจสอบ ว่าจำนวนสาขาทั้งหมดที่ทำการ SOP ไป ได้ POD ทุก Package แล้วหรือยัง
      if (totalDetailPod == totalDetailSop) {
        // ดึงข้อมูล ONSITE HEADER
        var getOnsiteHeader = await (db.select(db.onsiteEntries)
              ..where((tbl) => tbl.batchNo.equals(batchNo)))
            .getSingleOrNull();

        if (getOnsiteHeader == null) {
          return;
        }

        // สร้างข้อมูล เพิ่มอัพเดต ว่า BATCH นี้ ทำงานเสร็จแล้ว
        getOnsiteHeader = getOnsiteHeader.copyWith(
          startFlag: const d.Value("F"),
          modifiedBy: d.Value(auth?.userEnName),
          modifiedDt: d.Value(DateTime.now().toIso8601String()),
        );

        // อัพเดต ONSITE HEADER
        await db.update(db.onsiteEntries).replace(getOnsiteHeader);

        // refresh OBX และ เรียนฟังชั่น เพื่อดึงข้อมูลอัพเดต BATCH ใหม่ เพื่อแสดงในหน้า UI
        isRefeshSopPod(true);
        await getBatch();
        isRefeshSopPod(false);
      }

      // สร้างข้อมูล POD
      PodOnsiteModel podOnsiteModel = PodOnsiteModel(
        jobNo: jobNo,
        batchOnsiteNo: batchNo,
        branchOnsiteCode: qrCode.split('-')[1],
        driverNo: auth!.employeeId!,
        cardOnsiteBarcode: qrCode,
        lastSource: 'IMOT',
      );

      //  รวบรวมข้อมูล POD เพื่อโยนขึ้น  Transaction API
      UpdateAllPodOnsite updateAllPodOnsite = UpdateAllPodOnsite(
        locations: updateLocations,
        podOnsiteModel: podOnsiteModel,
      );

      // สร้างข้อมูล JOB SCHEDULER ของ POD

      var podOnsite = JobSchedulerEntriesCompanion.insert(
        url: '',
        activityType: d.Value(statusPod),
        request: d.Value(updateAllPodOnsite.toJson()),
        syncFlag: const d.Value('N'),
        createBy: d.Value(auth.userName),
        createDt: d.Value(DateTime.now().toIso8601String()),
        counter: const d.Value(0),
      );
// เพิ่มข้อมูล ลงไปใน JOB SCHEDULER
      await db.insertOne(db.jobSchedulerEntries, podOnsite);
    } catch (e) {
      rethrow;
    }

    // ดึงข้อมูล CARD QR CODE ออกมาจาก SQLITE
    var getQr = await (db.select(db.onsiteQREntries)
          ..where((tbl) => tbl.qrcode.equals(qrCode)))
        .getSingleOrNull();
    // เอาข้อมูล CARD QR ใน SQLITE ที่ได้มา เพิ่มเปลี่ยนข้อมูล เป็น POD
    getQr = getQr?.copyWith(
      status: const d.Value("POD"),
      statusDt: d.Value(DateTime.now().toIso8601String()),
      modifiedBy: d.Value(auth.userEnName),
      modifiedDt: d.Value(DateTime.now().toIso8601String()),
    );
    await db.update(db.onsiteQREntries).replace(getQr!);
    // โชว์ข้อความ
  }

  // ฟังชั่น ดึงข้อมูลของ CARD ทั้งหมดที่ทำการ SOP ON ไปไว้ใน ตัวแปร
  Future<void> getQrAllSop(int detailId) async {
    isRefeshSopPod(true);
    listOfQrSop = await (db.select(db.onsiteQREntries)
          ..where((tbl) => tbl.onsiteDetaildEntryId.equals(detailId)))
        .get();

    isRefeshSopPod(false);
  }

  // ฟังชั่น ดึงข้อมูลจำนวน Package ที่ทำการ SOP ON ไป และ จำนวนของสาขาที่ได้ SOP ON
  Future getSumSopDetail(String batchNo) async {
    var onsiteDetail = await (db.select(db.onsiteDetailEntries)
          ..where((tbl) => tbl.batchNo.equals(batchNo)))
        .get();

    int totalScan = 0;
    int totalDetail = 0;

    totalScan = onsiteDetail.map((e) => e.totalScan ?? 0).sum;

    totalDetail =
        onsiteDetail.where((x) => (x.totalScan ?? 0) > 0).toList().length;

    var sum = {
      'totalDetail': totalDetail,
      'totalPackage': totalScan,
    };
    // await db.close();
    return sum;
  }

  // ฟังชั่น การเริ่มงาน หลังจาก SOP ON
  Future<void> startBatchFollowSop({
    required String batchNo,
    // required List<JobDetailEntry> detail,
    required List<JobLocationEntry> detail,
  }) async {
    var position = await jobDetailContr.locationService.getLocation();
    var battery = await jobDetailContr.batteryService.getBattery();
    var fcmToken = BoxCacheUtil.getFCMToken;
    var auth = BoxCacheUtil.getAuthUser;
    final vehicle = BoxCacheUtil.getVehicle;

    List listLocationUpdateDb = [];
    List sumProduct = [];
    List<JobActivityForm> listJobLocatioApi = [];
    List<Map<String, dynamic>> detailProductLists = [];
    List<SopDetailModel> listSopDetailApi = [];
    List<JobUpdateLocation> listJobLocationApi = [];
    List<String> statusLocation = [
      'ARRIVED',
      'LOADING',
      'FINISHED',
      'LEAVED',
    ];
    var jobStart = await (db.select(db.jobHeaderEntries)
          ..where((tbl) => tbl.jobLastStatusCode.equals('START')))
        .getSingle();

    var locationDetail = await (db.select(db.jobLocationEntries)
          ..where((tbl) => tbl.jobNo.equals(jobStart.jobNo ?? '-')))
        .get();

    var listDetail = await (db.select(db.jobDetailEntries)
          ..where((tbl) => tbl.jobNo.equals(jobStart.jobNo.toString())))
        .get();
    var test = locationDetail.sublist(1);
    int count = 0;

    // ทำการสร้างข้อมูล ของแต่ละสาขา ที่ทำการ SOP ON
    // for (var e in detail) {
    for (var e in test) {
      // นับจำวนสาขาที่ดำเนินการ เพื่ออัพเดต STREAM PRCRESS
      count = count + 1;
      var branchName = listOfBranchQrLocal
          .firstWhereOrNull((xx) => xx['branchName'].contains(e.contactPerson));
      print(branchName);
      // อัพเดต STREAM PROCRESS
      addBranchStartSop(
          '$count/${detail.length}\nกำลังอ่านข้อมูล\nสาขา ${branchName?['branchName'] ?? '-'}');

      // หน่วงเวลา 0.1 วินาที
      await Future.delayed(const Duration(milliseconds: 100));

      // สร้างข้อมูล เพิ่มไว้ START JOB DETAIL
      final mapDTO = JobActivityForm(
        refId: e.id.toString(),
        // assignmentNo: e.assignmentNo,
        batteryPercent: battery,
        bookingNo: listDetail[0].bookingNo,
        licensePlate: '${vehicle?.licensePlate}',
        licenseProvince: '${vehicle?.licenseProvince}',
        supplierFlag: '${vehicle?.vehicleSupplierFlag}',
        startMileGps: null,
        startMileVehicle: null,
        endMileGps: null,
        endMileVehicle: null,
        driverNo: auth!.employeeId,
        fcmToken: fcmToken,
        remark: null,
        routeCode: auth.vehicleWithMobile?.routeCode,
        jobNo: e.jobNo,
        mobileActivityId: MobileActivity.Start.id,
        geoLatitude: '${position?.latitude}',
        geoLongitude: '${position?.longitude}',
        createdBy: auth.employeeId,
        createdDt: DateTime.now().toIso8601String(),
      );

      listLocationUpdateDb.add(mapDTO.toJson());
      listJobLocatioApi.add(mapDTO);

      // var branchCode = e.assignmentNo!.split('-').last;
      var branchCode = await db.select(db.onsiteDetailEntries).get();
      int sumPackage = 0;
      // ดึงจำนวน TOTAL PACKAGE SCAN ของสาขานั้นๆ
      // if (branchCode.) {
      for (var o in branchCode) {
        sumPackage = listOfQrLocal
            .where((qr) => qr.split('-')[1] == o.branchCode)
            .toList()
            .length;
      }
      //   return;
      // }

      try {
        // เรียกใช้ฟังชั่น เพื่ออ้พเดต SQLITE ของ JOB DETAIL
        // await updateDetailDbStartSop(
        //   data: mapDTO,
        //   total: sumPackage,
        // );

        // เรียกใช้ฟังชั่น เพื่ออ้พเดต SQLITE ของ JOB LOCATION
        await updateLocationDbStartSop(
          data: mapDTO,
          total: sumPackage,
        );

        // เรียกใช้ฟังชั่น เพื่ออ้พเดต SQLITE TABLE Onsite ทั้งหมด (มี 3 Table)
        await updateAllOnsiteStartSop(
          data: mapDTO,
        );
      } catch (e) {
        rethrow;
      }
    }

    // เรียกใช้ฟังชั่น เพื่ออ้พเดต SQLITE ของ JOB HEADER
    await updateHeaderDbStartSop(jobNo: detail[0].jobNo!);

    // อัพเดตข้อความ STREAM
    addBranchStartSop('กำลังอัพโหลดข้อมูล\nเข้าสู่ระบบ');
    List<JobLocationEntry> getAllJobLocation = [];
    // ทำการสร้างข้อมูล ที่ดำเนินการ SOP ON ทั้งหมด เพื่อส่งขึ้น API
    for (var detailLocal in listOfBranchQrLocal) {
      var branchCode = detailLocal['code'];
      List<QrSopOnsite> listQrApi = [];
      Map<String, dynamic> listProduct = {};
      for (var qr in listOfQrLocal) {
        if (qr.split('-')[1] == branchCode) {
          QrSopOnsite qrSopOnsite = QrSopOnsite(
            cardOnsiteBarcode: qr,
            sopEquipmentBy: auth!.userEnName!,
            sopEquipmentDt: DateTime.now().toIso8601String(),
          );

          listQrApi.add(qrSopOnsite);

          listProduct.addAll({
            "storeCode": qr.split('-')[1].toString(),
            "actPackage": listQrApi.length
          });
        }
      }

      SopDetailModel sopDetailModel = SopDetailModel(
        branchOnsiteCode: detailLocal['code'],
        driverNo: auth!.employeeId!,
        licensePlate: vehicle!.licensePlate!,
        createdDT: DateTime.now().toIso8601String(),
        jobId: detail[0].jobId!.toInt(),
        jobNo: detail[0].jobNo!,
        sopOnDetail: listQrApi,
      );

      listSopDetailApi.add(sopDetailModel);
      detailProductLists.add(listProduct);

      // ดึงข้อมูล JOB DETAIL ทั้งหมดของ JOB มา
      // List<JobDetailEntry> getAllJobDetail =
      //     await (db.select(db.jobDetailEntries)
      //           ..where((tbl) => tbl.jobNo.equals(detail[0].jobNo!)))
      //         .get();
      getAllJobLocation = await (db.select(db.jobLocationEntries)
            ..where((tbl) => tbl.jobNo.equals(detail[0].jobNo!)))
          .get();

      // ดึง JOB DETAIL ที่ต้องการ Branch Code ที่ทำการ For loop อยู่มา
      // var getSingleDetail = getAllJobDetail.firstWhereOrNull(
      //     (e) => e.assignmentNo!.split('-').last == branchCode);
      // var getSingleDetail = getAllJobLocation
      //     .firstWhereOrNull((e) => e.contactPerson == branchCode);
    }
    var getSingleDetail =
        getAllJobLocation.firstWhereOrNull((e) => e.pickupFlag == 'Y');

    if (getSingleDetail != null) {
      // ดึงข้อมูล JOB LOCATION ของ JOB DETAIL มาโดยเอาแค่จุดรับ
      var getJobLocation = await (db.select(db.jobLocationEntries)
            ..where((tbl) =>
                tbl.id.equals(getSingleDetail.id!) &
                tbl.pickupFlag.equals('Y')))
          .getSingleOrNull();

      if (getJobLocation != null) {
        // ดึงจำนวน Card ที่ทำการ SOP ON เข้าไป ของสาขา นั้นๆ
        var actPackage = listOfQrLocal.length;
        //  listOfQrLocal
        //     .where((qr) => qr == getSingleDetail.contactPerson)
        //     .toList()
        //     .length;

        // สร้างข้อมูล JOB LOCATION เพื่อส่งขึ้น API
        for (var location in statusLocation) {
          if (location == 'ARRIVED') {
            JobUpdateLocation jobUpdateLocation = JobUpdateLocation(
              id: getJobLocation.id!,
              jobDetailId: getJobLocation.jobDetailId!,
              type: location,
              fcmToken: fcmToken,
              licenseProvince: vehicle?.licenseProvince,
              geoLatitude: arrivedTimeSopOn.geoLat,
              geoLongitude: arrivedTimeSopOn.geoLong,
              batteryPercent: battery,
              createdDt: DateTime.now().toIso8601String(),
            );

            listJobLocationApi.add(jobUpdateLocation);
          } else if (location == 'LOADING') {
            JobUpdateLocation jobUpdateLocation = JobUpdateLocation(
              id: getJobLocation.id!,
              jobDetailId: getJobLocation.jobDetailId!,
              type: location,
              fcmToken: fcmToken,
              licenseProvince: vehicle?.licenseProvince,
              geoLatitude: arrivedTimeSopOn.geoLat,
              geoLongitude: arrivedTimeSopOn.geoLong,
              actManualPackage: 0,
              actPackage: actPackage,
              batteryPercent: battery,
              createdDt: DateTime.now().toIso8601String(),
            );

            listJobLocationApi.add(jobUpdateLocation);
          } else if (location == 'FINISHED') {
            JobUpdateLocation jobUpdateLocation = JobUpdateLocation(
              id: getJobLocation.id!,
              jobDetailId: getJobLocation.jobDetailId!,
              type: location,
              fcmToken: fcmToken,
              licenseProvince: vehicle?.licenseProvince,
              geoLatitude: arrivedTimeSopOn.geoLat,
              geoLongitude: arrivedTimeSopOn.geoLong,
              actManualPackage: 0,
              actPackage: actPackage,
              batteryPercent: battery,
              createdDt: DateTime.now().toIso8601String(),
            );

            listJobLocationApi.add(jobUpdateLocation);
          } else if (location == 'LEAVED') {
            JobUpdateLocation jobUpdateLocation = JobUpdateLocation(
              id: getJobLocation.id!,
              jobDetailId: getJobLocation.jobDetailId!,
              type: location,
              fcmToken: fcmToken,
              licenseProvince: vehicle?.licenseProvince,
              geoLatitude: arrivedTimeSopOn.geoLat,
              geoLongitude: arrivedTimeSopOn.geoLong,
              actManualPackage: 0,
              actPackage: actPackage,
              batteryPercent: battery,
              createdDt: DateTime.now().toIso8601String(),
            );

            listJobLocationApi.add(jobUpdateLocation);
          }
        }
      }
    }
//(detailProductLists.isEmpty) || detailProductLists[c]['storeCode']
    // int c = 0;
    // for (var i in listOfQrLocal) {
    //   c + 1;
    //   var qr = i.split('-')[1].toString();
    //   if (!detailProductLists.isNotEmpty) {
    //     detailProductLists.add({
    //       "storeCode": i.split('-')[1].toString(),
    //       // "actPackage": sumProduct[c]
    //     });
    //   } else if (qr != ) {
    //     detailProductLists.add({
    //       "storeCode": i.split('-')[1].toString(),
    //       // "actPackage": sumProduct[c]
    //     });
    //   }
    // }
    // for (var i in listOfQrLocal) {
    //   if (i.split('-')[1].toString() == detailProductLists[c]['storeCode']) {
    //     detailProductLists.add({
    //       // "storeCode": i.split('-')[1].toString(),
    //       "actPackage": i.split('-')[1].toString(),
    //     });
    //   }
    // }

    // รวบรวมข้อมูลที่จะดำเนินการส่งขึ้น API ทั้งหมด มาที่ชุด MODEL ตัวเดียว (ยกเว้นรูป DHL)
    StartFollowSopModel startFollowSopModel = StartFollowSopModel(
        jobNo: detail[0].jobNo!,
        batchNo: batchNo,
        driverNo: auth!.employeeId!,
        remark: remarkOnsite.text.isEmpty ? "" : remarkOnsite.text,
        listDetail: listJobLocatioApi,
        listLocation: listJobLocationApi,
        sopOnDetail: listSopDetailApi,
        detailProductList: detailProductLists);

    // สร้างข้อมูล JOB SCHEDULER ของการ START BATCH
    var jobStartOnsite = JobSchedulerEntriesCompanion.insert(
      url: '',
      activityType: const d.Value('ON-START-BATCH'),
      request: d.Value(startFollowSopModel.toJson()),
      syncFlag: const d.Value('N'),
      createBy: d.Value(auth.userName),
      createDt: d.Value(DateTime.now().toIso8601String()),
      counter: const d.Value(0),
    );

    // เพิ่มข้อมูลลงใน JOB SCHEDULER
    await db.insertOne(db.jobSchedulerEntries, jobStartOnsite);

    var getJobHeader = await (db.select(db.jobHeaderEntries)
          ..where((tbl) => tbl.jobNo.equals(detail[0].jobNo!)))
        .getSingleOrNull();

    // ทำการ สร้างข้อมูลรูป Barcode สาขา เพื่อส่งขึ้น API
    // for (var i = 0; i < listOfImageDhlLocal.length; i++) {
    //   var percentCount = ((i + 1) * 100) / listOfImageDhlLocal.length;

    // อัพเดตข้อความ STREAM
    // addBranchStartSop(
    //     '${percentCount.toInt()} %\nกำลังอัพโหลดข้อมูล\nเข้าสู่ระบบ');

    // TransactionImgModel dhlImage = TransactionImgModel(
    //   jobNo: getJobHeader?.jobNo ?? detail[0].jobNo!,
    //   jobID: getJobHeader?.id ?? 0,
    //   detailID: 0,
    //   locationID: 0,
    //   shipmentNo: "",
    //   batchNo: batchNo,
    //   actionType: "ON-IMG",
    //   actionDT: DateTime.now().toIso8601String(),
    //   fileName: '${detail[0].jobNo!}-$batchNo-$i.jpg',
    //   jsonByteArray: listOfImageDhlLocal[i].toString(),
    // );

    // สร้างข้อมูล JOB SCHEDULER ของการ START IMG DHL
    // var imgDhlOnsite = JobSchedulerEntriesCompanion.insert(
    //   url: '',
    //   activityType: const d.Value('ON-IMG'),
    //   request: d.Value(dhlImage.toJson()),
    //   syncFlag: const d.Value('N'),
    //   createBy: d.Value(auth.userName),
    //   createDt: d.Value(DateTime.now().toIso8601String()),
    //   counter: const d.Value(0),
    // );

    // listDhlImgScheduler.add(imgDhlOnsite);
    // }

    // var dataSopDhl = SopImageModel(
    //   jobNo: getJobHeader?.jobNo ?? detail[0].jobNo!,
    //   jobId: getJobHeader?.id ?? 0,
    //   batchOnsiteNo: batchNo,
    //   driverNo: auth.employeeNo ?? auth.employeeId,
    //   driverName: auth.userEnName,
    // );

    // var imgDhlTransactionHeader = JobSchedulerEntriesCompanion.insert(
    //   url: '',
    //   activityType: const d.Value('ON-IMG-HEADER'),
    //   request: d.Value(dataSopDhl.toJson()),
    //   syncFlag: const d.Value('N'),
    //   createBy: d.Value(auth.userName),
    //   createDt: d.Value(DateTime.now().toIso8601String()),
    //   counter: const d.Value(0),
    // );

    // listDhlImgScheduler.add(imgDhlTransactionHeader);

    await db.batchActionEntries(
      action: SqlAction.INSERRT_CF_UPDATE,
      table: db.jobSchedulerEntries,
      entitys: listDhlImgScheduler,
    );
  }

  // ฟังชั่นอัพเดต SQLITE ของ Table Onsite ทั้งหมด
  Future<void> updateAllOnsiteStartSop({required JobActivityForm data}) async {
    var auth = BoxCacheUtil.getAuthUser;
    var onsDetail = await (db.select(db.onsiteDetailEntries)
          ..where(
              (tbl) => tbl.id.equals(double.tryParse(data.refId!)!.toInt())))
        .getSingle();
    // var getQrScan;
    // for (var i in onsDetail) {
    // ดึงข้อมูล Card ที่สแกนไป
    var getQrScan = listOfQrLocal
        .where((e) => e.split('-')[1] == onsDetail.branchCode)
        .toList();
    // listOfQrLocal
    //     .where((e) => e.split('-')[1] == data.assignmentNo!.split('-').last)
    //     .toList();
    // }

    // ดึงข้อมูล Onsite Header
    var getOnsiteHeader = await (db.select(db.onsiteEntries)
          ..where((tbl) => tbl.jobNo.equals(data.jobNo!)))
        .getSingle();

    // ดึงข้อมูล Onsite Detail
    var idint = double.tryParse(data.refId!)!.toInt();
    var getOnsiteDetail = await (db.select(db.onsiteDetailEntries)
          ..where((tbl) => tbl.id.equals(idint)))
        .getSingle();

    // อัพเดตข้อมูล Onsite Header ให้เป็น เริ่มงาน
    getOnsiteHeader = getOnsiteHeader.copyWith(
      startFlag: const d.Value("Y"),
      startWorkDt: d.Value(data.createdDt),
      modifiedBy: d.Value(auth!.userEnName),
      modifiedDt: d.Value(data.createdDt),
    );

    // อัพเดตจำนวน Total scan ของสาขานั้นๆ
    getOnsiteDetail = getOnsiteDetail.copyWith(
      totalScan: d.Value(((getOnsiteDetail.totalScan ?? 0) + getQrScan.length)),
      modifiedDt: d.Value(data.createdDt),
      modifiedBy: d.Value(auth.userEnName),
    );

    List<OnsiteQREntry> listSaveQr = [];

    // ทำการ loop ข้อมูลสถานะ Card ที่ทำการสแกนไป ให้เป็น SOP จากที่เป็น NULL
    for (var e in getQrScan) {
      var qr = OnsiteQREntry(
        onsiteDetaildEntryId: getOnsiteDetail.id!,
        qrcode: e,
        batchNo: getOnsiteDetail.batchNo,
        status: 'SOP',
        statusDt: data.createdDt!,
        createdDt: data.createdDt!,
        createdBy: data.createdBy!,
      );

      var checkQr = await (db.select(db.onsiteQREntries)
            ..where((tbl) =>
                tbl.qrcode.equals(e) &
                tbl.batchNo.equals(getOnsiteDetail.batchNo!)))
          .getSingleOrNull();

      if (checkQr == null) {
        listSaveQr.add(qr);
      }
    }

    // อัพเดต Onsite Header
    await db.update(db.onsiteEntries).replace(getOnsiteHeader);

    // อัพเดต Onsite Detail
    await db.update(db.onsiteDetailEntries).replace(getOnsiteDetail);

    // อัพเดต Onsite QR
    await db.batchActionEntries(
      action: SqlAction.INSERRT_CF_UPDATE,
      table: db.onsiteQREntries,
      entitys: listSaveQr,
    );
  }

  // ฟังชั่น อัพเดต SQLITE JOB LOCATION
  Future<void> updateLocationDbStartSop({
    required JobActivityForm data,
    required int total,
  }) async {
    // ดึงข้อมูล JOB LOCATION ของสาขานั้นๆ
    var getLocation = await (db.select(db.jobLocationEntries)
          ..where((x) =>
              x.jobDetailId.equals(double.parse(data.refId!)) &
              x.pickupFlag.equals('Y')))
        .getSingleOrNull();

    if (getLocation == null) {
      return;
    }

    // อัพเดตข้อมูล ถึง ขึ้น เสร็จ ออก และจำนวน Package Scan ของ JOB LOCATION
    getLocation = getLocation.copyWith(
      jobArrivedDt: d.Value(arrivedTimeSopOn.arrivedTime),
      jobArrivedLatitude: d.Value(arrivedTimeSopOn.geoLat),
      jobArrivedLongitude: d.Value(arrivedTimeSopOn.geoLat),
      /////
      jobLoadingDt: d.Value(arrivedTimeSopOn.arrivedTime),
      jobLoadingLatitude: d.Value(arrivedTimeSopOn.geoLat),
      jobLoadingLongitude: d.Value(arrivedTimeSopOn.geoLat),
      /////
      jobFinishedDt: d.Value(DateTime.now().toIso8601String()),
      jobFinishedLatitude: d.Value(data.geoLatitude),
      jobFinishedLongitude: d.Value(data.geoLongitude),
      /////
      jobLeavedDt: d.Value(DateTime.now().toIso8601String()),
      jobLeavedLatitude: d.Value(data.geoLatitude),
      jobLeavedLongitude: d.Value(data.geoLongitude),
      /////
      startFlag: const d.Value("Y"),
      actScanPackage: d.Value(total),
      actPackage: d.Value(total),
      modifiedBy: d.Value(data.createdBy),
      modifiedDt: d.Value(DateTime.now().toIso8601String()),
    );

    // อัพเดต JOB LOCATION
    await db.update(db.jobLocationEntries).replace(getLocation);
  }

  // ฟังชั่นอัพเดต JOB DETAIL
  Future<void> updateDetailDbStartSop({
    required JobActivityForm data,
    required int total,
  }) async {
    // ดึงข้อมูลสาขา ตาม parameter ที่ส่งเข้ามา
    var getDetail = await (db.select(db.jobDetailEntries)
          ..where((x) => x.bookingNo.equals(data.bookingNo!)))
        .getSingleOrNull();
    // var getDetail = await (db.select(db.jobLocationEntries)
    //       ..where((x) => x.id.equals(data.refId as double)))
    //     .getSingleOrNull();

    if (getDetail == null) {
      return;
    }

    // อัพเดตข้อมูล JOB DETAIL
    getDetail = getDetail.copyWith(
      assignmentStatus: const d.Value("START"),
      assignmentStartDt: d.Value(data.createdDt),
      assignmentStartLatitude: d.Value(data.geoLatitude),
      assignmentStartLongtitude: d.Value(
        data.geoLongitude,
      ),
      totalActPackage: d.Value(total),
      modifiedBy: d.Value(data.createdBy),
      modifiedDt: d.Value(DateTime.now().toIso8601String()),
    );

    // อัพเดต JOB DETAIL
    await db.update(db.jobDetailEntries).replace(getDetail);
    // await db.close();
  }

  // ฟังชั่น อัพเดต SQLITE JOB HEADER
  Future<void> updateHeaderDbStartSop({required String jobNo}) async {
    var auth = BoxCacheUtil.getAuthUser;

    // ดึงข้อมูล JOB HEADER ตาม Parameter ที่ส่งเข้ามา
    var getHeader = await (db.select(db.jobHeaderEntries)
          ..where((tbl) => tbl.jobNo.equals(jobNo)))
        .getSingleOrNull();

    if (getHeader == null) {
      return;
    }

    // อัพเดตข้อมูล JOB HEADER
    getHeader = getHeader.copyWith(
      totalActPackage: d.Value(listOfQrLocal.length),
      modifiedBy: d.Value(auth!.userEnName),
      modifiedDt: d.Value(DateTime.now().toIso8601String()),
    );

    // อัพเดต JOB HEADER
    await db.update(db.jobHeaderEntries).replace(getHeader);
  }

  // ฟังชั่น บันทึกเวลาเริ่มต้น ถึง ขึ้น ของการ SOP ON
  Future<void> saveTimeArrivedAndLoading() async {
    var position = await jobDetailContr.locationService.getLocation();

    if (arrivedTimeSopOn.arrivedTime == null) {
      arrivedTimeSopOn = arrivedTimeSopOn.copyWith(
        arrivedTime: DateTime.now().toIso8601String(),
        geoLat: position?.latitude.toString(),
        geoLong: position?.longitude.toString(),
      );
    }
  }

  // ฟังชั่น แจ้งเตื่อนการกดกลับหน้าหลัก ทั้ง Arrow back และ Back navigator bar ของมือถือ
  Future<bool> backToHomeScreen() async {
    if (listOfBatch.first.startFlag == "N" &&
        (listOfBranchQrLocal.isNotEmpty || listOfImageDhlLocal.isNotEmpty)) {
      await Get.defaultDialog(
        title: 'แจ้งเตือน',
        content: Column(
          children: [
            const Text(
              'หากคุณไม่ได้เริ่มงาน\nข้อมูลสแกน Qr Code \nและภาพ Barcode ตะกร้า จะถูกลบ\nยืนยันการกลับไปหน้าหลัก ?',
              style: TextStyle(
                color: Colors.red,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(
              height: 20,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  child: const Text('ยกเลิก'),
                  onPressed: () => Get.back(),
                ),
                const SizedBox(
                  width: 10,
                ),
                ElevatedButton(
                  onPressed: () => Get.close(2),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade400,
                  ),
                  child: const Text(
                    'กลับสู่หน้าหลัก',
                    style: TextStyle(
                      color: Colors.white,
                    ),
                  ),
                )
              ],
            )
          ],
        ),
      );
    } else {
      Get.back();
    }
    return false;
  }

  Future<bool> backToScreen() async {
    if (listqr.isNotEmpty) {
      await Get.defaultDialog(
        title: 'แจ้งเตือน',
        content: Column(
          children: [
            const Text(
              'คุณยังไม่ได้รายการไม่สำเร็จ หากกลับไปหน้าแรกข้อมูลทั้งหมดจะหายไป',
              style: TextStyle(
                color: Colors.red,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(
              height: 20,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  child: const Text('ยกเลิก'),
                  onPressed: () => Get.back(),
                ),
                const SizedBox(
                  width: 10,
                ),
                ElevatedButton(
                  onPressed: () {
                    Get.close(2);
                    newItem.clear();
                    listqr.clear();
                    listOfImageDhlLocal.clear();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade400,
                  ),
                  child: const Text(
                    'ต้องการย้อนกลับ',
                    style: TextStyle(
                      color: Colors.white,
                    ),
                  ),
                )
              ],
            )
          ],
        ),
      );
    } else {
      Get.back();
    }
    return false;
  }

  // ฟังชั่น ดึงข้อมูล Batch ลงในตัวแปร และอัพเดตสถานะของ Batch
  Future<void> getBatch() async {
    isBatchLoading(true);
    // ดึงข้อมูล Onstite Header ทั้งหมด
    var batch = await db.select(db.onsiteEntries).get();

    // loop อัพเดต flag ของ Batch ทั้งหมด
    for (var e in batch) {
      // SOP-Del : เริ่มงาน(batch)
      // POD-P : ดำเนินการส่งไปบางส่วน (ยังส่งไม่หมด ที่รับมา)
      // POD : ส่งสำเร็จหมดแล้ว
      // SOP-ON : รับของ

      if (e.startFlag == null) {
        if (e.status == "SOP-Del" || e.status == "POD-P") {
          e = e.copyWith(startFlag: const d.Value("Y"));
        } else if (e.status == "POD") {
          e = e.copyWith(startFlag: const d.Value("F"));
        } else {
          e = e.copyWith(startFlag: const d.Value("N"));
        }

        // อัพเดต Onsite Header
        await db.updateTable(db.onsiteEntries, e);
      } else {
        if (e.status == "POD") {
          e = e.copyWith(startFlag: const d.Value("F"));
        }
        await db.updateTable(db.onsiteEntries, e);
      }
    }

    // ดึงข้อมูล Batch เข้าตัวแปร
    listOfBatch = await db.select(db.onsiteEntries).get();

    isBatchLoading(false);

    if (listOfBatch.length != 1) {
      await Get.defaultDialog(
        title: 'เกิดข้อผิดพลาด',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.signal_cellular_connected_no_internet_0_bar_rounded,
              size: 50,
              color: Colors.orange,
            ),
            const SizedBox(
              height: 20,
            ),
            const Text(
              'ไม่สามารถโหลดข้อมูลได้\nกรุณาลองใหม่',
              textAlign: TextAlign.center,
            ),
            const SizedBox(
              height: 20,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: ElevatedButton(
                onPressed: () async {
                  Get.back();
                  isBatchLoading(true);
                  await jobContr.getJobAll().whenComplete(() async {
                    var batch = await db.select(db.onsiteEntries).get();

                    // loop อัพเดต flag ของ Batch ทั้งหมด
                    for (var e in batch) {
                      if (e.startFlag == null) {
                        if (e.status == "SOP-DEL") {
                          e = e.copyWith(startFlag: const d.Value("Y"));
                        } else {
                          e = e.copyWith(startFlag: const d.Value("N"));
                        }

                        // อัพเดต Onsite Header
                        await db.updateTable(db.onsiteEntries, e);
                      }
                    }

                    // ดึงข้อมูล Batch เข้าตัวแปร
                    listOfBatch = await db.select(db.onsiteEntries).get();
                    isBatchLoading(false);
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade300,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white,
                    ),
                    const SizedBox(
                      width: 10,
                    ),
                    const Text(
                      'Refresh',
                      style: TextStyle(
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        barrierDismissible: false,
      );
    }
  }

  // ฟังชั่น ดึงข้อมูล Onsite Detail ทั้งหมดของ Batch
  Future<List<OnsiteDetailEntry>> getOnsiteDetail(int onsiteEntryId) async {
    var result = await (db.select(db.onsiteDetailEntries)
          ..where((tbl) => tbl.onsiteEntryId.equals(onsiteEntryId)))
        .get();
    return result;
  }

  // ฟังชั้นลบข้อมูล Card QR CODE
  Future<void> deleteQr(
    int rowId, {
    String desc = 'คณต้องการลบข้อมูลใช่หรือไม่',
    Widget? icon,
    Function()? onConfirm,
    Function()? onClose,
  }) async {
    await dialogUtils.showDialogCustomIcon(
      description: Padding(
        padding: const EdgeInsets.all(15.0),
        child: Text(
          desc,
          style: const TextStyle(
            fontSize: 16.5,
          ),
          textAlign: TextAlign.center,
        ),
      ),
      titleIcon: icon ??
          Icon(
            Icons.cancel,
            size: 100,
            color: Colors.red.shade400,
          ),
      actionWithContent: true,
      actions: [
        Row(
          children: [
            const SizedBox(width: 5),
            Expanded(
              child: ButtonWidgets.cancelButtonOutline(
                label: 'ออก',
                onTab: () {
                  //print('cusstom close');
                  if (onClose != null) {
                    onClose();
                    return;
                  }
                  Get.back();
                },
              ),
            ),
            Expanded(
              child: ButtonWidgets.okButtonOutline(
                onTab: () {
                  if (onConfirm != null) {
                    onConfirm();
                  }

                  Get.back();
                },
              ),
            ),
          ],
        )
      ],
    );
  }

  // ฟังชั่น สแกน Card QrCode ของตะกร้า
  Future<void> saveQrCode(String qrCode, String? jobNo) async {
    var branchCode = qrCode.split('-');

    // ค้นหาข้อมูล Card QRCode ในตัวแปร TEMP
    var checkQrInList = listOfQrLocal.where((e) => e == qrCode);

    // ดึงข้อมูล สาขา ของ Card Qrcode นั้นๆ
    var getBranchDb = await (db.select(db.jobLocationEntries)
          ..where((tbl) => tbl.jobNo.equals(jobNo!)))
        .get();

    var checkQrReady = await JobRepository().checkCardReady(qrCode);

    // SBUX-CARD-ERROR
    if (checkQrReady['code'] == 'SBUX-CARD-ERROR') {
      soundPlay('wrong.m4a');
      return GLFunc.showSnackbar(
        showIsEasyLoading: true,
        message: 'QR $qrCode ไม่ได้อยู่ในสถานะพร้อมใช้งาน',
        type: SnackType.WARNING,
      );
    }

    var getDetailId = await JobRepository()
        .getLocationDetail(getBranchDb[0].jobDetailId!.toInt());

    var mapRecipent =
        getDetailId?.where((e) => e.recipientCode == branchCode[1]).toList();

    // ตรวจสอบ ถ้ามีข้อมูล Card Qrcode แล้วให้ทำการเตื่อนและ จบฟังชั่น
    if (checkQrInList.isNotEmpty) {
      soundPlay('wrong.m4a');
      GLFunc.showSnackbar(
        showIsEasyLoading: true,
        message: 'QR $qrCode ถูกสแกนไปแล้ว',
        type: SnackType.WARNING,
      );
      return;
    }

    // แจ้งเตือน ถ้าหากไม่่มีสาขาในใบงานที่รับมา และออกจากฟังชั่น
    if (mapRecipent!.isEmpty) {
      soundPlay('wrong.m4a');
      GLFunc.showSnackbar(
        showIsEasyLoading: true,
        message: 'ไม่พบสาขา ${branchCode[1]} ในงานของท่าน',
        type: SnackType.WARNING,
      );
      return;
    }

    // ค้นหาข้อมูลสาขาในตัวแปร TEMP โดยหาจาก Card QrCode นั้นๆ

    var checkBranchInList =
        listOfBranchQrLocal.where((e) => e['code'] == branchCode[1]).toList();

    // ถ้าไม่มีข้อมูลสาขาในตัวแปร จะดำเนินการ เพิ่มข้อมูลเข้าไป (ข้อมูลสาขา)
    // List<dynamic> listOfBranchQrLocal2 = [];
    if (checkBranchInList.isEmpty) {
      listOfBranchQrLocal.add(
        {
          'code': branchCode[1],
          'branchName': mapRecipent[0].recipientName,
        },
      );
      writhBranchNameSOP(jobNo!, jsonEncode(listOfBranchQrLocal));
    }

    // เพิ่มข้อมูล Card QrCode เข้าไปในตัวแปร TEMP
    // List<dynamic> listOfQrLocal2 = [];
    listOfQrLocal.add(qrCode);

    writhBranchCodeSOP(jobNo!, jsonEncode(listOfQrLocal));

    // เสียงเตือนสำเร็จ
    soundPlay('beep.m4a');

    // readSOP(getBranchDb[0].jobNo!);
    // isRefeshSopPod(false);
    // โชว์ข้อความ
    GLFunc.showSnackbar(
      showIsEasyLoading: true,
      message: 'บันทึก $qrCode เรียบร้อย',
      type: SnackType.SUCCESS,
    );
  }

  writhBranchNameSOP(String jobNo, String data) async {
    // final Directory directory = await getApplicationDocumentsDirectory();
    //  Directory directory = await getTemporaryDirectory();
    Directory? directory = await getExternalStorageDirectory();
    final File file = File(
        '${directory!.path}/SOP_BranchName_${jobNo}_${auth!.employeeNo}.txt');
    await file.writeAsString(data);
  }

  writhBranchCodeSOP(String jobNo, String data) async {
    // final Directory directory = await getApplicationDocumentsDirectory();
    //  Directory directory = await getTemporaryDirectory();
    Directory? directory = await getExternalStorageDirectory();
    final File file = File(
        '${directory!.path}/SOP_BranchCode_${jobNo}__${auth!.employeeNo}.txt');
    await file.writeAsString(data);
  }

  Future readSOP(String jobNo) async {
    try {
      //   isRefeshSopPod(true);

      // final Directory directory = await getApplicationDocumentsDirectory();
      Directory? directory = await getExternalStorageDirectory();
      final File fileSOPBranchName = File(
          '${directory!.path}/SOP_BranchName_${jobNo}_${auth!.employeeNo}.txt');
      final File fileSOPBranchCode = File(
          '${directory.path}/SOP_BranchCode_${jobNo}_${auth!.employeeNo}.txt');

      var getSOPBranchName = await fileSOPBranchName.readAsString();
      var getSOPBranchCode = await fileSOPBranchCode.readAsString();

      listOfBranchQrLocal.addAll(jsonDecode(getSOPBranchName));
      listOfQrLocal.addAll(jsonDecode(getSOPBranchCode));
      isRefeshSopPod(false);
      //List jdecode = await jsonDecode(t);

      // for (var e in jdecodeBranchName) {
      //   listOfBranchQrLocal.add(
      //     {
      //       'code': e['code'],
      //       'branchName': e['branchName'],
      //     },
      //   );
      // }
    } catch (e) {
      print(e);
    }
  }

  // ฟังชั่น เช็คว่า มี Onsite Detail แล้วหรือไม่ ถ้าไม่มี จะทำการดึง All job ใหม่อีกครั้ง
  Future<void> checkDetailOnsite(String batchNo) async {
    var getDetailOnsite = await (db.select(db.onsiteDetailEntries)
          ..where((tbl) => tbl.batchNo.equals(batchNo)))
        .get();

    if (getDetailOnsite.isEmpty) {
      isRefeshSopPod(true);
      await Get.find<JobsController>()
          .initPage()
          .whenComplete(() => isRefeshSopPod(false));
    }
  }

  Future<void> sendDataOnsitePOD({
    required List<JobDetailEntry> detail,
    required String batchNo,
    required int idLocation,
    required String branchOnsiteCode,
  }) async {
    var auth = BoxCacheUtil.getAuthUser;
    var getJobHeader = await (db.select(db.jobHeaderEntries)
          ..where((tbl) => tbl.jobNo.equals(detail[0].jobNo!)))
        .getSingleOrNull();

    //  var idlocation = await (db.select(db.jobLocationEntries)..where((tbl) => tbl. ))

    String dtimg = DateFormat('yyyyMMddHHmmss')
        .format(DateTime.now().toLocal())
        .toString();

    int c = 1;
    var img;
    Map ojb = {};
    Map ojb2 = {};
    for (var imgByte in listOfImageDhlLocal) {
      var b64 = base64Encode(imgByte);
      ImgList imgList = ImgList(
        fileName: '${detail[0].jobNo!}$dtimg$c.jpg',
        data: b64, //'${img}'
      );
      img = jsonDecode(imgList.toJson());
      ojb.addAll({"img$c": img});

      //---------2
      ImgList imgList2 = ImgList(
        fileName: '${detail[0].jobNo!}$dtimg$c.jpg',
        data: "", //'${img}'
      );
      var img2 = jsonDecode(imgList2.toJson());
      ojb2.addAll({"img$c": img2});

      // ทำการ สร้างข้อมูลรูป ตะกร้า
      // for (var i = 0; i < listOfImageDhlLocal.length; i++) {
      // var percentCount = ((i + 1) * 100) / listOfImageDhlLocal.length;

      //  อัพเดตข้อความ STREAM
      // addBranchStartSop(
      //     '${percentCount.toInt()} %\nกำลังอัพโหลดข้อมูล\nเข้าสู่ระบบ');

      // TransactionImgModel dhlImage = TransactionImgModel(
      //   jobNo: getJobHeader?.jobNo ?? detail[0].jobNo!,
      //   jobID: getJobHeader?.id?.toInt() ?? 0,
      //   detailID: detail[0].id?.toInt(),
      //   locationID: idLocation.toInt(),
      //   shipmentNo: "",
      //   batchNo: batchNo,
      //   actionType: "ON-IMG",
      //   actionDT: dtNow.toIso8601String(),
      //   fileName: '${detail[0].jobNo!}${dtimg}${c}.jpg',
      //   jsonByteArray: '${img}',
      // );
      // print(dhlImage);

      // สร้างข้อมูล JOB SCHEDULER ของการ START IMG DHL
      // var imgDhlOnsite = JobSchedulerEntriesCompanion.insert(
      //   url: '',
      //   activityType: const d.Value('ON-IMG'),
      //   request: d.Value(dhlImage.toJson()),
      //   syncFlag: const d.Value('N'),
      //   createBy: d.Value(auth?.userName),
      //   createDt: d.Value(DateTime.now().toIso8601String()),
      //   counter: const d.Value(0),
      // );

      // listDhlImgScheduler.add(imgDhlOnsite);

      // await db.insertOne(db.jobSchedulerEntries, imgDhlOnsite);
      // }
      c++;
    }
    TransactionImgModel imgModel = TransactionImgModel(
      actionType: "ON-IMG",
      locationID: idLocation,
      detailID: detail[0].id?.toInt() ?? 0,
      batchNo: batchNo,
      jobNo: detail[0].jobNo,
      referenceCode: branchOnsiteCode,
      statusCode: "SUCCESS",
      statusDt: dtNow.toIso8601String(),
      actionDT: dtNow.toIso8601String(),
      imgList: ojb,
      jobID: getJobHeader?.id?.toInt() ?? 0,
      fileName: '',
      jsonByteArray: "",
      shipmentPrefix: "Starbuck",
      customerVipFlag: 'Y',
      customerItmsCode: "${detail[0].customerCode}",
      encodeType: "Base64",
    );
    // print(imgModel);

    var dataSopDhl = SopImageModel(
        jobNo: getJobHeader?.jobNo ?? detail[0].jobNo!,
        jobId: getJobHeader?.id ?? 0,
        detailID: detail[0].id?.toDouble(),
        locationID: idLocation.toDouble(),
        batchOnsiteNo: batchNo,
        branchOnsiteCode: branchOnsiteCode,
        driverNo: auth?.employeeNo ?? auth?.employeeId,
        driverName: auth?.userEnName,
        actionType: "ON-IMG",
        // locationID: idLocation,
        // detailID: detail[0].id?.toInt() ?? 0,
        batchNo: batchNo,
        // jobNo: detail[0].jobNo,
        referenceCode: branchOnsiteCode,
        statusCode: "SUCCESS",
        statusDt: dtNow.toIso8601String(),
        actionDT: dtNow.toIso8601String(),
        imgList: ojb2,
        jobID: getJobHeader?.id?.toInt() ?? 0,
        fileName: '',
        jsonByteArray: "",
        shipmentPrefix: "Starbuck",
        customerVipFlag: 'Y',
        customerItmsCode: "${detail[0].customerCode}");

    var imgDhlOnsite = JobSchedulerEntriesCompanion.insert(
      url: '',
      activityType: const d.Value('ON-IMG-HEADER'),
      request: d.Value(dataSopDhl.toJson()),
      syncFlag: const d.Value('N'),
      createBy: d.Value(auth?.userName),
      createDt: d.Value(DateTime.now().toIso8601String()),
      counter: const d.Value(0),
    );
    // List<JobSchedulerEntriesCompanion> imgDhlOnsiteImgScheduler;

    // imgDhlOnsiteImgScheduler.add(imgDhlOnsite);
    await db.insertOne(db.jobSchedulerEntries, imgDhlOnsite);

    var imgDhlTransactionHeader = JobSchedulerEntriesCompanion.insert(
      url: '',
      activityType: const d.Value('ON-IMG'),
      // request: d.Value(imgModel.toJson()),
      request: d.Value(imgModel.toJson()),
      syncFlag: const d.Value('N'),
      createBy: d.Value(auth?.userName),
      createDt: d.Value(dt),
      counter: const d.Value(0),
    );

    // listDhlImgScheduler.add(imgDhlTransactionHeader);
    //print(listDhlImgScheduler);
    await db.insertOne(db.jobSchedulerEntries, imgDhlTransactionHeader);
    BackgroundJobServices().jobScheduledsX();
  }

  Future checkQr({
    Function()? onTab,
  }) async {}
}
