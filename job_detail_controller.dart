// ignore_for_file: depend_on_referenced_packages, empty_catches

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:group_button/group_button.dart';
import 'package:imot/common/Other/dialog_utils.dart';
import 'package:imot/common/Other/general_function.dart';
import 'package:imot/common/cache/box_cache.dart';
import 'package:imot/common/models/shared/summary_job.dart';
import 'package:imot/common/models/shared/user_profile.dart';
import 'package:imot/common/models/view/job_detail.dart';
import 'package:imot/common/models/view/job_header.dart';
import 'package:imot/common/models/view/job_location.dart';
import 'package:imot/Api_Repository_Service/services/battery_service.dart';
import 'package:imot/Api_Repository_Service/services/job_service.dart';
import 'package:imot/Api_Repository_Service/services/location_service.dart';
import 'package:imot/common/shared/app_enum.dart';
import 'package:imot/common/widgets/buttons/button_component.dart';
import 'package:imot/Api_Repository_Service/controllers/jobs_controller.dart';
import 'package:imot/database/database.dart';
import 'package:imot/Api_Repository_Service/repositories/job_repository.dart';
import 'package:drift/drift.dart' as d;
import 'package:collection/collection.dart' as c;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class JobDetailController extends GetxController {
  RxBool isLoading = false.obs;
  RxBool isJobStart = false.obs;

  DateTime? timeCache;
  RxList<JobDetail> listOfDetails = <JobDetail>[].obs;

  JobHeader? jobActive;
  Rx<JobDetail>? assignmentActive;
  AppDatabase get db => AppDatabase.provider;

  LocationService get locationService => LocationService();
  BatteryService get batteryService => BatteryService();
  JobService get jobService => JobService();
  UserProfile? auth = BoxCacheUtil.getAuthUser;

  List<Widget> detailRows = [];
  Summary? acceptSum;

  ///////////// JOB DETAIL SELECT GROUP /////////////

  GroupButtonController gDetailConlr = GroupButtonController();
  RxBool isLoadingSumDetail = false.obs;

  Future<int> getSumFinishDetail(List<JobDetail> jobDetail) async {
    // isLoadingSumDetail(true);
    int sum = 0;
    var a = await (db.select(db.jobDetailEntries)
          ..where((e) => e.assignmentTypeCode.equals('DC')))
        .get();
    var getLocations = await (db.select(db.jobLocationEntries)
          ..where((x) => x.deliveryFlag.equals('Y')))
        .get();
    var totalRoDc = getLocations.where((x) => x.deliveryFlag == 'Y').length;
    var findLocationFinish =
        getLocations.where((x) => x.jobFinishedDt != null).toList();
    var totalFDc = findLocationFinish.length;
    bool finishDc = (totalRoDc == totalFDc);
    if (a.isNotEmpty && finishDc) {
      sum++;
    }
    for (var x in jobDetail) {
      var i = await (db.select(db.jobLocationEntries)
            ..where((e) =>
                e.jobDetailId.equals(x.id!) &
                e.jobLeavedDt.isNotNull() &
                e.deliveryFlag.equals("Y")))
          .get();
      if (i.isNotEmpty) {
        sum++;
      }
    }
    // isLoadingSumDetail(false);
    return sum;
  }

  Future<void> initAssignentLoad() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.remove('event.triger');
    isLoading(true);

    Future.delayed(const Duration(milliseconds: 200));
    isLoading(false);
    update();
  }

  @override
  void onClose() {
    super.onClose();
    detailRows = [];
  }

  Future<void> loadData(String jobNo, String status) async {
    try {
      await Future.delayed(const Duration(milliseconds: 500));
      var bindStatus = status;
      var getHeader = await db.getJobHeadersSingle(jobNo: jobNo);

      if (getHeader != null) {
        bindStatus = getHeader.jobLastStatusCode ?? status;
        isJobStart(getHeader.jobLastStatusCode == 'START');

        status = status != bindStatus ? status : bindStatus;
      }

      if (status == JobStatus.ASSIGN.name || status == 'ACCEPT_WEB') {
        JobStatus getJobStatus = JobStatus.values.firstWhere(
            (e) => e.name == (status == 'ACCEPT_WEB' ? 'ACCEPT' : status));
        var res = await getJobInfoDetail(jobNo, getJobStatus);
        listOfDetails(res);
      } else {
        listOfDetails.bindStream(getJobDetailStream(jobNo, bindStatus));
      }

      isLoading(false);
    } on DioError catch (onError) {
      //print(onError);
      var mes = onError.response?.data != null
          ? onError.response?.data['message']['th']
          : onError.message;
      dialogUtils.showDialogCustomIcon(
        actionWithContent: false,
        description: Text(
          mes,
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 15,
          ),
          textAlign: TextAlign.center,
        ),
        actions: [
          ButtonWidgets.okButtonOutline(
            closeOverlays: true,
          ),
        ],
      );
    } finally {}
  }

  Stream<List<JobDetail>> textData(jobNo, getJobStatus) {
    var columnPrefix = '';
    var columns = [];

    columns.addAll([
      db.mapColumnName(
        db.jobDetailEntries.$columns,
        perfixAs: 'nested_0',
        perfixTable: 'd',
      ),
      db.mapColumnName(
        db.jobLocationEntries.$columns,
        perfixAs: 'nested_1',
        perfixTable: 'l',
      )
    ]);

    columnPrefix = columns.join(",");

    var qStr = 'SELECT $columnPrefix '
        ' from jobDetailEntry d'
        ' INNER JOIN jobLocationEntry l'
        ' on d.id = l.job_detail_id'
        ' WHERE d.user_id = ?'
        ' AND d.job_no = ?'
        ' AND d.accept_flag = \'Y\' '
        ' AND d.assignment_status IN(?)'
        '';

    List<d.Variable> variables = [];

    variables.add(d.Variable(auth!.id));
    variables.add(d.Variable(jobNo));
    variables.add(d.Variable(getJobStatus));

    final q = db.customSelect(
      qStr,
      variables: variables,
      readsFrom: {db.jobDetailEntries, db.jobLocationEntries},
    );

    return q.watch().asyncMap((rows) async {
      List<JobDetail> listDetails = [];
      var mapKey = <double, List<JobLocation>>{};
      for (var row in rows) {
        var readDetail =
            await db.jobDetailEntries.mapFromRow(row, tablePrefix: 'nested_0');
        var readLocation = await db.jobLocationEntries
            .mapFromRowOrNull(row, tablePrefix: 'nested_1');

        if (!listDetails.any((e) => e.id == readDetail.id)) {
          listDetails.add(JobDetail.fromMap(readDetail.toJson()));
        }

        mapKey
            .putIfAbsent(readLocation!.jobDetailId!, () => [])
            .add(JobLocation.fromMap(readLocation.toJson()));
      }
      return listDetails.map((e) {
        return e;
      }).toList();
    });
  }

  Future<void> loadSortData() async {
    var groupById = c.groupBy(listOfDetails, (JobDetail x) => x.id);
    List<JobDetail>? data = [];
    groupById.forEach((key, value) {
      var locatios = value.mapMany((e) => e.locations).toList();
      var header = value.first;

      header.locations = locatios;
      data.add(header);
    });

    data.sort((a, b) => a.joinFlag!.compareTo(b.joinFlag!));

    data.sort((a, b) => (a.seq ?? 0).compareTo(b.seq ?? 0));
    listOfDetails.clear();
    update();
  }

  void checkJobStart(jobNo) async {
    var job = await db.getJobHeadersSingle(jobNo: jobNo, userId: auth!.id);

    if (job != null) {
      isJobStart(job.jobLastStatusCode == 'START');
    }
    ////print('check job start ${isJobStart.value}');
  }

  Stream<List<JobDetail>> getJobDetailStream(
    String jobNo,
    String status,
  ) {
    try {
      status = status.toUpperCase();

      if (status == JobStatus.ASSIGN.name) {
        //  //print('load data api stream');
        var query = Stream.fromFuture(getJobInfoDetail(jobNo));

        return query;
      } else if (status == JobStatus.START.name ||
          (status == JobStatus.ACTIVE.name ||
              status == JobStatus.ACCEPT.name)) {
        return db.watchJobDetails(
          jobNo: jobNo,
        );
      }
    } finally {}
    return Stream.value([]);
  }

  Future<void> updateDragSort(int i, id) async {
    try {
      await (db.update(db.jobDetailEntries)..where((x) => x.id.equals(id)))
          .write(JobDetailEntriesCompanion(seq: d.Value(i)));
    } catch (e) {}
  }

  void updateDragSorts(int i, id) async {
    try {
      await (db.update(db.jobDetailEntries)..where((x) => x.id.equals(id)))
          .write(JobDetailEntriesCompanion(seq: d.Value(i)));
    } catch (e) {}
  }

  Future<List<JobDetail>> getJobInfoDetail(
    String jobNo, [
    JobStatus jobStatus = JobStatus.ASSIGN,
  ]) async {
    try {
      // //print('load item detail');

      List<JobDetail> localItems = [];

      try {
        var exitsDetails = await db.getJobDetail(
          jobNo: jobNo,
          statuss: [jobStatus.name],
          userId: auth!.id,
        );

        exitsDetails ??= [];

        localItems = exitsDetails;
      } catch (e) {}

      if ((localItems).isEmpty) {
        var res = await JobRepository().fetchDataJobDetail(
          jobNo,
          jobStatus.name,
        );
        var mapData = Map<String, dynamic>.from(res?.results!['item']);
        acceptSum = Summary.fromMap(res?.results!['summary']);
        jobActive = JobHeader.fromMap(mapData);
        jobActive?.details = List.from(mapData['details'])
            .map((e) => JobDetail.fromMap(e))
            .toList();

        if (mapData.containsKey('details')) {
          localItems.addAll(jobActive!.details!);
        }
      } else {
        var jobHead = await db.getJobHeadersSingle(jobNo: jobNo);
        if (jobHead != null) {
          jobActive = JobHeader.fromMap(jobHead.toJson());
        }
      }

      return localItems;
    } on DioError {
      rethrow;
    } finally {}
  }

  Future<void> jobAccept({
    String? jobNo,
    List<JobDetailEntry>? localDetails,
    Map<String, dynamic>? raw,
  }) async {
    try {
      var getByRows = listOfDetails.where((e) => e.jobNo == jobNo).toList();
      List<Map<String, dynamic>> itemToUpdate = [];

      var getjob = await db.getJobHeadersSingle(jobNo: jobNo);
      var locations = await db.getJobLocations(jobNo: jobNo);
      int i = 0;

      if (getByRows.isNotEmpty) {
        itemToUpdate = getByRows.map((e) {
          e.acceptFlag = 'Y';
          e.acceptDt = DateTime.now().toIso8601String();
          e.assignmentStatus = 'ACCEPT';
          e.seq = i;

          var newDe = e.toMap();

          if ((locations ?? []).isNotEmpty) {
            newDe['listOfLocation'] = locations!
                .where((x) => x.jobDetailId == e.id)
                .map((e) => e.toMap())
                .toList();
          } else {
            newDe['listOfLocation'] =
                e.locations.map((e) => e.toMap()).toList();

            newDe.remove('locations');
          }

          i++;
          return newDe;
        }).toList();
      }

      GLFunc.instance.showLoading(null, false);

      await jobService.jobUpdateStatus(
        jobNo: jobNo,
        data: itemToUpdate,
        status: JobStatus.ACCEPT,
        jobHeader: jobActive,
      );

      DashboardEntry? dashboard = await db.summaryDashboard();

      if (dashboard != null) {
        var add = getjob == null
            ? (dashboard.totalAccept) + 1
            : dashboard.totalAccept;
        dashboard = dashboard.copyWith(
          totalAccept: add,
        );
        await db.batchActionEntries(
            action: SqlAction.INSERRT_CF_UPDATE,
            table: db.dashboardEntries,
            entitys: [dashboard]);
      }

      Get.find<JobsController>()
          .jobWatingAcceptList
          .removeWhere((e) => e['jobNo'] == jobNo);

      // //print('accept');
    } on DioError catch (onError) {
      showDialogError(
        'ใบสั่งงานเลขที่ $jobNo ${onError.response!.data?['message']?['th'] ?? 'เกิดข้อผิดพลาดบางอย่าง ไม่สามารถรับงานได้ โปรดติดต่อผู้ดูแล'}',
      );

      // //print(onError);
    } finally {
      GLFunc.instance.hideLoading();
      update();
    }
  }

  void showDialogError(String v) {
    dialogUtils.showDialogCustomIcon(
        actionWithContent: true,
        description: Text(
          v,
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 15,
          ),
          textAlign: TextAlign.center,
        ),
        actions: [
          ButtonWidgets.okButtonOutline(
            closeOverlays: true,
          ),
        ]);
  }

  Future<void> jobReject({
    required Map<String, dynamic> exception,
    jobNo,
  }) async {
    try {
      var getByRow = listOfDetails.firstWhereOrNull((e) => e.jobNo == jobNo);

      getByRow = getByRow!.copyWith(
        acceptFlag: 'N',
        acceptDt: DateTime.now().toIso8601String(),
        assignmentStatus: 'REJECT',
      );

      var row = getByRow.toMap();

      row.addAll({
        'exceptionId': exception['id'] ?? exception['exception']['id'],
        'exceptionCode':
            exception['exceptionCode'] ?? exception['exception']['code'],
        'statusId': exception['statusId'],
        'statusCode': exception['statusCode'],
        'exceptionRemak': exception['remark'],
      });

      await jobService.jobUpdateStatus(
        jobNo: jobNo,
        data: [row],
        status: JobStatus.REJECT,
        jobHeader: jobActive,
        requestApiFirst: true,
      );

      listOfDetails.removeWhere((e) => e.jobNo == jobNo);
    } on DioError catch (onError) {
      //print(onError);
      var textError =
          'ใบสั่งงานเลขที่ $jobNo ${onError.response!.data?['message']?['th'] ?? 'เกิดข้อผิดพลาดบางอย่าง ไม่สามารถรับงานได้ โปรดติดต่อผู้ดูแล'}';
      showDialogError(textError);
    } finally {}
  }

  Future<void> checkPermision() async {
    var list = [];
    var camera = await Permission.camera.status.isGranted;
    var location = await Permission.location.isGranted;
    // var storage = await Permission.storage.isGranted;
    list.addAll([camera, location]);
    // //print(sss);
    var permis = list.contains(false);
    if (permis != false) {
      await dialogPermision(permis);
    }
    // if (!camera.isGranted) {
    //   await Permission.camera.request().then(
    //     (value) async {
    //       if (value != PermissionStatus.granted) {
    //         await dialogPermision(Permission.camera, 'กล้องถ่ายรูป');
    //         // await checkPermision();
    //       }
    //     },
    //   );
    // }
    // if (!location.isGranted) {
    //   await Permission.location.request().then(
    //     (value) async {
    //       if (value != PermissionStatus.granted) {
    //         await dialogPermision(Permission.location, 'ตำแหน่ง');
    //         // await checkPermision();
    //       }
    //     },
    //   );
    // }
    // if (!storage.isGranted) {
    //   await Permission.storage.request().then(
    //     (value) async {
    //       if (value != PermissionStatus.granted) {
    //         await dialogPermision(Permission.storage, 'พื้นที่เก็บข้อมูล');
    //         // await checkPermision();
    //       }
    //     },
    //   );
    // }
  }

  // Future dialogPermision(Permission permission, String type) async {
  Future dialogPermision(bool permission) async {
    await Get.defaultDialog(
      barrierDismissible: false,
      title: 'การขออนุญาตสิทธิ์',
      content: Column(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 100,
            color: Colors.red,
          ),
          Text(
            // 'กรุณาอนุญาตสิทธิ์การเข้าถึง\n$type\nเพื่อให้สามารถปฏิบัติงานได้',
            'กรุณาอนุญาตสิทธิ์การเข้าถึง\n${!await Permission.camera.status.isGranted ? 'กล้องถ่ายรูป\n' : ''}${!await Permission.location.status.isGranted ? 'ตำแหน่ง\n' : ''}เพื่อให้สามารถปฏิบัติงานได้',
            textAlign: TextAlign.center,
            style: GoogleFonts.prompt(
              fontSize: 18,
            ),
          ),
          const SizedBox(
            height: 20,
          ),
          ElevatedButton(
            onPressed: () async {
              // await permission.request().then(
              //   (value) async {
              //     Get.back();

              //     if (value != PermissionStatus.granted) {
              //       await openAppSettings();
              //     }
              //   },
              // );
              if (permission != false) {
                await openAppSettings();
              }
              Get.back();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade400,
            ),
            child: Text(
              'ดำเนินการต่อ',
              style: GoogleFonts.prompt(
                fontSize: 18,
                color: Colors.white,
              ),
            ),
          )
        ],
      ),
    );
  }
}
