import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart';
import 'package:imot/common/Other/general_function.dart';
import 'package:imot/common/cache/box_cache.dart';
import 'package:imot/common/models/shared/response_model.dart';
import 'package:imot/common/models/shared/user_profile.dart';
import 'package:imot/common/models/view/job_header.dart';
import 'package:imot/Api_Repository_Service/services/battery_service.dart';
import 'package:imot/Api_Repository_Service/services/job_service.dart';
import 'package:imot/Api_Repository_Service/services/location_service.dart';
import 'package:imot/common/shared/app_enum.dart';
import 'package:imot/database/database.dart';
import 'package:imot/Api_Repository_Service/repositories/iems_repository.dart';
import 'package:imot/Api_Repository_Service/repositories/job_repository.dart';
import 'package:drift/drift.dart' as drift;
import 'package:path/path.dart' as path;

class UploadMileController extends GetxController {
  RxDouble? currentMileGPS;
  RxBool isLoadingMile = false.obs;
  RxString? mileImageSrc;
  RxBool togleImage = false.obs;

  AppDatabase get db => AppDatabase.provider;
  LocationService get locationService => LocationService();
  JobService get jobService => JobService();
  BatteryService batteryService = BatteryService();
  JobHeader? jobHeader;

  UserProfile? get auth => BoxCacheUtil.getAuthUser;

  Future<void> getCurretMile([String? jobNo]) async {
    try {
      if (isLoadingMile.isFalse) {
        isLoadingMile(true);
      }

      if (await GLFunc.isClientOnline() && auth!.vehicleSupplierFlag != 'Y') {
        var res = await JobRepository().getMileVehilce();

        if (res != null && (res.results ?? []).isNotEmpty) {
          currentMileGPS = RxDouble(res.results!.first.milage);
        }
        var localVehicleKey = BoxCacheUtil.box.read('vehicle_key');
        if (localVehicleKey == null) {
          var vehicle = BoxCacheUtil.getVehicle;
          String mapLicensePlate =
              '${vehicle?.licensePlate}|${vehicle?.licenseProvince}';
          var res = await IemsRepository().fetchVehicle(mapLicensePlate);
          if (res != null) {
            BoxCacheUtil.setVehicle(res.toMap());
            BoxCacheUtil.box.write('vehicle_key', '${res.id}');
          }
        }
      }
    } catch (e) {
      //print('get mile error $e');
    } finally {
      if (jobNo != null) {
        var localHeader = await db.getJobHeadersSingle(jobNo: jobNo);

        jobHeader = JobHeader.fromMap(localHeader!.toJson());
      }
      isLoadingMile(false);
      update();
    }
  }

  Future<void> uploadImageMileage(
    JobStatus event, {
    required String jobNo,
    double currentMileGPS = 0,
    required String currentFilePath,
    String? newFileName,
    double? locationId,
  }) async {
    var auth = BoxCacheUtil.getAuthUser;

    var imageCompress =
        await GLFunc.instance.compressAndTryCatch(path: currentFilePath);

    newFileName = path
        .basenameWithoutExtension(newFileName ?? '$jobNo-MILE-${event.name}');

    var fileCompress = await GLFunc.instance
        .saveFileOnDisk(imageCompress!, '$newFileName.jpg', 'miles');

    File newFile = File(fileCompress);

    var getDocument = await db.getFileDocuments(
      refNo: jobNo,
      docType: 'MILE-${event.name}',
      userId: auth!.id!,
    );

    FileDocumentEntriesCompanion fileDoc;
    ActivityEntriesCompanion? activity;
    if (getDocument.isEmpty) {
      fileDoc = FileDocumentEntriesCompanion.insert(
        documentType: 'MILE-${event.name}',
        name: newFileName,
        path: newFile.path,
        rawFile: newFile.readAsBytesSync(),
        referance: jobNo,
        userId: drift.Value(auth.id),
        syncFlag: const drift.Value('N'),
        jobLocationId: drift.Value(locationId),
        syncDate: DateTime.now().toIso8601String(),
        createDt: DateTime.now().toIso8601String(),
      );
    } else {
      var findWithName =
          getDocument.firstWhereOrNull((e) => e.name.contains(newFileName!));
      if (findWithName != null) {
        fileDoc = findWithName.toCompanion(true);
        fileDoc = fileDoc.copyWith(
          name: drift.Value(newFileName),
          path: drift.Value(newFile.path),
          rawFile: drift.Value(newFile.readAsBytesSync()),
        );
      } else {
        fileDoc = getDocument.first.toCompanion(true);
      }
    }

    try {
      var dataLog = GLFunc.instance.jEncode({
        'jobNo': jobNo,
        'action': event.name,
        'currentMile': currentMileGPS,
        'file': [fileDoc.path.value],
      });

      var jobEntry = JobSchedulerEntriesCompanion.insert(
        url: '',
        activityType: drift.Value('${event.name}.MILE'),
        request: drift.Value(dataLog),
        syncFlag: const drift.Value('N'),
        createBy: drift.Value(auth.userName),
        createDt: drift.Value(DateTime.now().toIso8601String()),
        counter: const drift.Value(0),
      );

      await db.jobSchedulerEntries.insertOne(jobEntry);

      String message = 'บันทึกรายการสำเร็จ';

      message = 'บันทึกรายการสำเร็จ';

      db.fileDocumentEntries.insertOnConflictUpdate(fileDoc);

      if (await GLFunc.isClientOnline() && 1 == 2) {
        var resUpdateMileGPS = await JobRepository().putUpdateMileage(
          jobNo: jobNo,
          action: event.name,
          currentMile: currentMileGPS,
          file: newFile,
        );
        fileDoc = fileDoc.copyWith(
          syncDate: drift.Value(DateTime.now().toIso8601String()),
          syncFlag: const drift.Value('Y'),
        );

        message = resUpdateMileGPS.message!.th!;
      } else {
        message = 'บันทึกรายการสำเร็จ';
      }

      if (event == JobStatus.FINISH) {
        // var user = BoxCacheUtil.getAuthUser;
        var dashboardActive = await db.summaryDashboard();

        dashboardActive = dashboardActive?.copyWith(
          jobNo: const drift.Value(null),
          total: 0,
          totalDelvery: 0,
          totalPickup: 0,
        );

        db.updateTable(db.dashboardEntries, dashboardActive!);
      }

      GLFunc.showSnackbar(
        showIsEasyLoading: true,
        type: SnackType.SUCCESS,
        message: message,
      );
    } on DioError catch (e) {
      fileDoc = fileDoc.copyWith(
        syncDate: drift.Value(DateTime.now().toIso8601String()),
        syncFlag: const drift.Value('E'),
      );
      db.activityEntries.insertOnConflictUpdate(activity!);

      ResponseModel res = ResponseModel.fromJson(e.response!.data);
      EasyLoading.showError(res.message!.th!);
    } finally {}
  }
}
