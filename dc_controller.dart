// ignore_for_file: unused_local_variable, prefer_typing_uninitialized_variables

import 'dart:async';
import 'dart:convert';

import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' as d;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:imot/Api_Repository_Service/services/backgrounds/job_service.dart';
import 'package:imot/common/Other/contstants.dart';
import 'package:imot/common/Other/date_utils.dart';
import 'package:imot/common/Other/general_function.dart';
import 'package:imot/common/Other/string_extension.dart';

import 'package:imot/common/cache/box_cache.dart';

import 'package:imot/common/models/form/onsite/transaction_model.dart';

import 'package:imot/common/widgets/maps/gmap_util.dart';
import 'package:imot/Api_Repository_Service/controllers/jobs_controller.dart';
import 'package:imot/database/database.dart';
import 'package:imot/common/models/form/table_map_row.dart';
import 'package:imot/common/models/view/job_location.dart';
import 'package:imot/common/models/view/location_view_model.dart';
import 'package:imot/common/models/form/update_status_delivery.dart';
import 'package:imot/common/models/shared/response_model.dart';
import 'package:imot/Api_Repository_Service/repositories/job_repository.dart';
import 'package:imot/Api_Repository_Service/services/location_service.dart';
import 'package:imot/common/shared/app_enum.dart';
import 'package:intl/intl.dart';

class DcController extends GetxController {
  final ImagePicker picker = ImagePicker();

  // JobsController jobsController = Get.find();
  JobsController jobsController = Get.put(JobsController());

  final LocationService _locationService = LocationService();

  final Completer<GoogleMapController> gMapController = Completer();

  final List<Marker> customMarkers = [];

  final JobRepository _jobRepository = JobRepository();
  String? imageSRC;
  RxBool isLoading = false.obs;
  RxBool isLoadingMap = false.obs;
  RxBool isHCR = false.obs;
  RxBool isLoadingFile = false.obs;
  RxList<File> files = RxList();
  Uint8List? imagebytes;
  ExceptionEntry? exceptionStatus;
  AppDatabase get db => AppDatabase.provider;

  final List<LocationViewModel> _locationsOfDelivery = [];
  RxList<JobLocation> listOfLocation = <JobLocation>[].obs;
  Rx<JobLocation>? locationSelection;
  List<Marker> mapMarkers = [];
  final TextEditingController keyword = TextEditingController();

  TextEditingController? nextDate = TextEditingController();
  TextEditingController? consigneeName = TextEditingController();
  TextEditingController? actPackage = TextEditingController();
  TextEditingController? remark = TextEditingController();
  var modelTransaction = TransactionModel();

  // @override
  // void onInit() {
  //   super.onInit();
  //   // print('onInit');
  //   // ignore: invalid_use_of_protected_member
  // }

  Future<void> checkAndfindSetMarker() async {
    isLoadingMap(true);
    var data = locationSelection!.value;
    double? lat = double.tryParse(data.geoLatitude ?? '');
    double? long = double.tryParse(data.geoLongitude ?? '');
    if (lat == null || long == null) {
      //print('find match address');

      var dataOfAddreaa = [
        data.subDistrictThDesc,
        data.districtThDesc,
        data.provinceThDesc,
        data.postCode,
      ];

      var address = GLFunc.instance.replaceAddress(data.address ?? "");
      for (var a in dataOfAddreaa) {
        bool isMapth = address.contains(a!);
        if (!GetUtils.isNullOrBlank(a)! && !isMapth) {
          address += ' $a';
        }
      }

      address =
          address.replaceAll('ไม่ระบุตำบล', '').removeWhitespacePrefix(' ');

      // var findMatchAddress = await locationService.queryFromAddres(address);

      // if (findMatchAddress != null) {
      //   var matchOfFirst = findMatchAddress[0];
      //   //print('found address');
      //   //print(
      //       'estimate location ${matchOfFirst.latitude},${matchOfFirst.longitude}');
      //   data.geoLatitude = '${matchOfFirst.latitude}';
      //   data.geoLongitude = '${matchOfFirst.longitude}';
      //   await setMarker(data, 'pin-final.png');
      // } else {
      //   //print('not found address');
      // }
    } else {
      await setMarker(data, 'pin-final.png');
    }

    isLoadingMap(false);
    update();
  }

  Future<void> setMarker(JobLocation data, [String? icon]) async {
    double? lat = double.tryParse(data.geoLatitude ?? '');
    double? long = double.tryParse(data.geoLongitude ?? '');
    if (lat == null && long == null) return;
    final pin1 = await GmapUtils()
        .getBytesFromAsset('assets/images/${icon ?? 'truck.png'}', 160);
    final markerPin = await GmapUtils().fromBytes(pin1);
    customMarkers.clear();
    customMarkers.addAll([
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

  Future<void> onLoadLocationByDetail(double detailId) async {
    listOfLocation.bindStream(db.watchJobLocationJoinDt(detailId: detailId));
  }

  Future<bool> isClientOnline() async {
    var result = await Connectivity().checkConnectivity();
    return !(result == ConnectivityResult.none &&
        result != ConnectivityResult.bluetooth);
  }

  void addFile(File f) {
    isLoadingFile(true);
    files.add(f);
    isLoadingFile(false);
    update();
  }

  void removeFileAy(int i) {
    files.removeAt(i);
  }

  Future<void> removeFile(path) async {
    isLoadingFile(true);
    var getImeage = files.firstWhereOrNull((e) => e.path == path);
    if (getImeage != null) {
      files.remove(getImeage);

      ((db.fileDocumentEntries))
          .deleteWhere((t) => t.path.equals(getImeage.path));

      try {
        getImeage.deleteSync();
      } finally {}
    }

    isLoadingFile(false);
    update();
  }

  RxBool isResonLoading = false.obs;

  RxBool get requiredImage => RxBool(
      exceptionStatus != null && exceptionStatus?.requireImageFlag == 'Y');
  // exceptionStatus?.?['requireImageFlag'] == 'Y');
  RxBool get requiredDate => RxBool(
      exceptionStatus != null && exceptionStatus?.requireTimeStampFlag == 'Y');
  // exceptionStatus?.rawData?['requireTimeStampFlag'] == 'Y');
  RxBool get requiredReson =>
      RxBool(exceptionStatus != null && exceptionStatus?.reasonRequired == 'Y');
  // exceptionStatus?.rawData?['reasonRequired'] == 'Y');

  List<LocationViewModel> get getLocationsOfDelivery => _locationsOfDelivery;
  LocationService get locationService => _locationService;
  void setDataLocationDelivery(v) {
    _locationsOfDelivery.addAll(v);
  }

  void clearLocationDelivery() {
    _locationsOfDelivery.clear();
  }

  // RxList<ExceptionStatus> listStatus = <ExceptionStatus>[].obs;
  RxList<ExceptionEntry> listStatus = <ExceptionEntry>[].obs;
  Future<void> getListException() async {
    isLoading(true);

    List<Map<String, dynamic>> items = [];
    List<ExceptionEntry> getException = await db.watchExceptionEntry();
    Map<String, dynamic> newmap = {};
    try {
      var itemsCache =
          BoxCacheUtil.box.read(AppConstants.EXCEPTION_CACHE) ?? [];

      items = itemsCache;
    } catch (e) {
      //print(e);
    }

    listStatus(getException);

    isLoading(false);
  }

  Future<ResponseModel?> updateStatusDelivery(
    Map<String, dynamic> v,
    ActionStatus status,
  ) async {
    try {
      var auth = BoxCacheUtil.getAuthUser;
      var mapData = UpdateStatusDelivery(
        jobLocationId: v['id'],
        jobDetailId: v['jobDetailId'],
        jobNo: v['jobNo'],
        actManualPackage: v['actManualPackage'],
        actPackage: v['actPackage'],
        batteryPercent: await jobsController.batteryService.getBattery(),
        consigneeName: v['consigneeName'],
        exceptionCode: v['exceptionCode'],
        exceptionId: v['exceptionId'] ?? 0,
        exceptionRemark: v['exceptionRemark'],
        geoLatitude: v['geoLatitude'],
        geoLongitude: v['geoLongitude'],
        hcrFlag: isHCR.value ? 'Y' : 'N',
        podDt: DateTime.now().toIso8601String(),
        reasonDesc: v['reasonDesc'],
        reasonId: v['reasonId'] ?? "0",
        shipmentId: v['shipmentId'],
        shipmentNo: v['shipmentNo'],
        statusName: status.name,
      );

      List<FileDocumentEntriesCompanion> fileUploads = [];

      var locationByJob = await db.getJobLocations(
        jobNo: mapData.jobNo,
        jobDetailId: mapData.jobDetailId,
      );

      var getJobLocation = locationByJob?.firstWhere((e) => e.id == v['id']);

      var getJobDetails = await db.getJobDetail(jobNo: getJobLocation?.jobNo!);

      var getDetailById =
          getJobDetails?.firstWhereOrNull((x) => x.id == mapData.jobDetailId);

      getJobLocation = getJobLocation?.copyWith(
        podFlag: status == ActionStatus.SUCCESS ? 'Y' : 'N',
        lastStatusCode: status == ActionStatus.SUCCESS ? 'POD' : 'DLY',
        podDt: mapData.podDt,
        hcrFlag: mapData.hcrFlag,
        jobFinishedLatitude: mapData.geoLatitude,
        jobFinishedLongitude: mapData.geoLongitude,
        jobFinishedDt: mapData.podDt,
        actPackage: mapData.actPackage,
        consigneeName: mapData.consigneeName,
        lastExceptionCode: mapData.exceptionCode,
        lastExceptionId: mapData.exceptionId,
        signatueName: mapData.consigneeName,
      );

      DashboardEntry? dash;

      int countFile = 1;

      await db.fileDocumentEntries.deleteWhere((x) =>
          x.referance.equals(mapData.shipmentNo!) &
          x.jobLocationId.equals(mapData.jobLocationId));

      var nameImage;
      var jsEnData;
      var ss;
      Map<String, dynamic> dataImg = {};
      Map<String, dynamic> jsData = {};
      List<String> fileNames = [];
      List<String> paths = [];
      List<String> bytesPaths = [];

      var dt = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
//files

      for (var file in files) {
        var curFile = file.readAsBytesSync();

        var newFileName =
            '${mapData.shipmentNo}-${status.name == 'SUCCESS' ? 'S' : 'F'}-${dateUtils.formattedDate(DateTime.now(), 'yyyyMMdd')}-$countFile.jpg';
        var saveFile = await GLFunc.instance
            .saveFileOnDisk(curFile, newFileName, status.name);

        var fileWithPath = File(saveFile);

        fileUploads.add(
          FileDocumentEntriesCompanion(
              documentType: d.Value(status.name),
              syncDate: d.Value(DateTime.now().toIso8601String()),
              rawFile: d.Value(fileWithPath.readAsBytesSync()),
              path: d.Value(fileWithPath.path),
              name: d.Value(newFileName),
              syncFlag: const d.Value('N'),
              referance: d.Value(mapData.shipmentNo!),
              jobLocationId: d.Value(mapData.jobLocationId),
              userId: d.Value(auth!.id!),
              createDt: d.Value(DateTime.now().toIso8601String())),
        );
        paths.add(fileWithPath.path);

        //  print("Bytes : $curFile");
        // bytesPaths.add(curFile.toString());

        // fileNames.add(basename(file.path));

        // dataImg.addAll({
        //   "jobNo": mapData.jobNo,
        //   "jobID": getJobLocation?.jobId,
        //   "detailID": mapData.jobDetailId,
        //   "locationID": mapData.jobLocationId,
        //   "shipmentNo": getJobLocation?.shipmentNo,
        //   "actiontype": "POD-DATA",
        //   "ActionDT": dt,
        //   "fileName": basename(file.path),
        //   "jsonByteArray": jsonEncode(curFile).toString(),
        // });
        // var jsEntryIMG = JobSchedulerEntriesCompanion.insert(
        //   url: '',
        //   activityType: const d.Value('POD-IMG'),
        //   request: d.Value(jsonEncode(dataImg).toString()),
        //   syncFlag: const d.Value('N'),
        //   createBy: d.Value(auth!.userName),
        //   createDt: d.Value(DateTime.now().toIso8601String()),
        //   counter: const d.Value(0),
        // );
        // await db.jobSchedulerEntries.insertOne(jsEntryIMG);

        countFile++;
      }

      //image toc
      mapData = mapData.copyWith(
        paths: paths,
      );

      try {
        if (await GLFunc.isClientOnline() && 1 == 2) {
          try {
            var res = await _jobRepository.putUpdateDeliveryStatus(
              dataToCreate: mapData,
              files: files,
            );

            // //print(res);

            for (var e in fileUploads) {
              e.copyWith(syncFlag: const d.Value('Y'));
            }

            return res;
          } finally {}
        }

        jsData.addAll({
          "ShipmentNo": mapData.shipmentNo,
          "BatteryPercent": mapData.batteryPercent,
          "ActionDT": dt.toString(),
          "PodDT": mapData.podDt,
          "StatusName": mapData.statusName,
          "ExceptionId": mapData.exceptionId,
          "ExceptionCode": mapData.exceptionCode,
          "ExceptionRemark": mapData.exceptionRemark,
          "ActPackage": mapData.actPackage,
          "DriverFullname": auth?.userEnName,
          "GeoLatitude": mapData.geoLatitude,
          "GeoLongitude": mapData.geoLongitude,
          "ConsigneeName": mapData.consigneeName,
          "HcrFlag": mapData.hcrFlag,
          "ReasonId": mapData.reasonId,
          "ReasonDesc": mapData.reasonDesc,
          "FileNames": fileNames
        });

        jsEnData = jsonEncode(jsData).toString();

        // data
      } finally {
        var locationUpdate = JobLocationEntry.fromJson(getJobLocation!.toMap());

        await db.updateTables([
          TableInfoWithData(
            table: db.jobDetailEntries,
            entity: JobDetailEntry.fromJson(getDetailById!.toMap()),
          ),
          TableInfoWithData(
              table: db.jobLocationEntries, entity: locationUpdate)
        ]);
        await db.batchActionEntries(
            action: SqlAction.INSERT,
            table: db.fileDocumentEntries,
            entitys: fileUploads);

        if (dash != null) {
          dash.copyWith(
            totalDelvery: 0,
            totalPickup: 0,
            jobNo: const d.Value(null),
          );

          await db.updateTable(db.dashboardEntries, dash);
        }

        if (getDetailById.assignmentTypeCode == 'DC') {
          locationByJob =
              locationByJob?.where((x) => x.pickupFlag != "Y").toList();
        }

        if (locationByJob?.length ==
            locationByJob?.where((x) => x.jobFinishedDt != null).length) {
          getDetailById = getDetailById.copyWith(
            finishFlag: "Y",
          );

          dash = await db.summaryDashboard();
        }

        // var jsDataTnm = {
        //   "jobNo": mapData.jobNo,
        //   "jobID": getJobLocation.jobId,
        //   "detailID": mapData.jobDetailId,
        //   "shipmentNo": mapData.shipmentNo,
        //   "locationID": mapData.jobLocationId,
        //   "priorityLevel": 3,
        //   "actionType": 'POD-DATA',
        //   "jsonString": jsEnData
        // };

        // var xx = jsonEncode(jsDataTnm).toString();
        // var jsEntryData = JobSchedulerEntriesCompanion.insert(
        //   url: '',
        //   activityType: const d.Value('POD-DATA'),
        //   request: d.Value(xx),
        //   syncFlag: const d.Value('N'),
        //   createBy: d.Value(auth!.userName),
        //   createDt: d.Value(DateTime.now().toIso8601String()),
        //   counter: const d.Value(0),
        // );
        // await db.jobSchedulerEntries.insertOne(jsEntryData); // data
        var jobEntry = JobSchedulerEntriesCompanion.insert(
          url: '',
          activityType: const d.Value('DELIVERY'),
          request: d.Value(mapData.toJson()),
          syncFlag: const d.Value('N'),
          createBy: d.Value(auth!.userName),
          createDt: d.Value(DateTime.now().toIso8601String()),
          counter: const d.Value(0),
        );

        await db.jobSchedulerEntries.insertOne(jobEntry);

        files.clear();
        Future.delayed(const Duration(microseconds: 500)).then((_) {
          GLFunc.instance.hideLoading();
          Get.back(closeOverlays: true, result: 'reload');
        });
      }

      GLFunc.showSnackbar(
        message: 'ทำรายการสำเร็จแล้ว ระบบจะดำเนินการแจ้งให้ทราบในภายหลัง',
        showIsEasyLoading: true,
        type: SnackType.SUCCESS,
      );
      BackgroundJobServices().jobScheduledsX();
    } catch (e) {
      //print("ERROR $e");
    }
    return null;
  }

  Stream<List<JobLocation>?> getLocationsByDetail(
    double jobDetailId, {
    double? locationId,
    int? recordId,
  }) {
    var queryChanged = AppDatabase.provider.watchJobLocations(
      id: locationId,
      jobDetailId: jobDetailId,
    );

    return queryChanged;
  }
}
