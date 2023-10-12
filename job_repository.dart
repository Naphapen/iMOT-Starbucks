// ignore_for_file: depend_on_referenced_packages, unused_local_variable, empty_catches

import 'dart:io';

import 'package:dio/dio.dart';

import 'package:get/get_utils/src/get_utils/get_utils.dart';
import 'package:imot/Api_Repository_Service/controllers/jobs_controller.dart';
import 'package:imot/common/cache/box_cache.dart';
import 'package:imot/common/models/form/job_activity.dart';
import 'package:imot/common/models/form/job_update_location.dart';
import 'package:imot/common/models/form/job_update_status_form_model.dart';
import 'package:imot/common/models/form/onsite/transaction_model.dart';
// import 'package:imot/common/models/form/onsite/transaction_model.dart';
import 'package:imot/common/models/form/update_status_delivery.dart';
import 'package:imot/common/models/view/job_header.dart';
import 'package:imot/common/models/view/location_view_model.dart';
import 'package:imot/common/models/shared/response_model.dart';
import 'package:imot/common/models/view/response_mile_view_model.dart';
import 'package:imot/Api_Repository_Service/dio/api_base_helper.dart';
import 'package:http_parser/http_parser.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;

class JobRepository {
  late Dio _dio;
  JobRepository() {
    ApiBaseHelper.allowHttps = true;
    _dio = ApiBaseHelper.dio;
    ApiBaseHelper.addInterceptors(_dio);
  }

  Future<ResponseModel> insertTransaction(TransactionModel data) async {
    try {
      var res = await _dio.post(
        '/v1/jobs/Transaction/insert',
        data: data.toMap(),
      );
      //   print(data.toJson());
      // trickTransaction();
      return ResponseModel.fromJson(res.data);
    } catch (e) {
      //print('----> [ ACTION TYPE : ${data.actionType} ERROR $e ] ');
      await JobsController().sendCatchError('${data.actionType}');
      rethrow;
    }
  }

  Future<void> trickTransaction() async {
    await _dio.get("/v2/systems/resync/data-auto");
  }

  final dio1 = Dio();
  Future<ResponseModel> insertTransactionImgNew(data) async {
    try {
      // print("im ${data}");

      var res = await dio1.post(
          'https://api-ftp.interexpress.co.th/JobsTransaction/Transaction/Img/insert-new?',
          data: data);

      return ResponseModel.fromJson(res.data);
      // return res.data;
    } catch (e) {
      //print('----> [ ACTION TYPE : ${data.actionType} ERROR $e ] ');
      // print('$data $e ');
      //  await JobsController().sendCatchError('${data} ${e} ');

      rethrow;
    }
  }

  Future<ResponseModel> insertTransactionImg(data) async {
    try {
      // print("data $data");
      var res = await _dio.post(
        '/v1/jobs/Transaction/img/insert',
        data: data,
      );
      // print("im ${res.data}");

      return ResponseModel.fromJson(res.data);
      // return res.data;
    } catch (e) {
      //print('----> [ ACTION TYPE : ${data.actionType} ERROR $e ] ');
      // print('$data $e ');
      //  await JobsController().sendCatchError('${data} ${e} ');

      rethrow;
    }
  }

  Future<void> putSqliteData(File file) async {
    try {
      var res = await _dio.put(
        '/v1/jobs/send/filesqlite',
        data: file,
      );
      //print('object $res');
    } catch (e) {
      await JobsController().sendCatchError('SEND_SQLITE');

      //print('object $e');
    }
    return;
  }

  Future<void> putCatchError(String activity, String result) async {
    try {
      var res = await _dio.put(
        '/v1/exception/error',
        queryParameters: {
          'str_error': activity,
        },
        data: result,
      );
      //print('object $res');
    } catch (e) {
      //print('object $e');
    }
    return;
  }

  Future<Map<String, dynamic>?> postActivity(JobActivityForm model) async {
    try {
      var res = await _dio.post('/v2/jobs/activity', data: model.toMap());
      //print('object $res');
    } catch (e) {
      //print('object $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> getJobSummary() async {
    try {
      CancelToken cancelToken = CancelToken();
      final result = await _dio.get('/v2/jobs', cancelToken: cancelToken);

      return result.data;
      // return null;
    } catch (e) {
      //print('object $e');
    }
    return null;
  }

  Future<ResponseModel?> fetchDataJobDetail(String jobNo,
      [String? status]) async {
    try {
      CancelToken cancelToken = CancelToken();
      String url = '/v2/jobs/detail/by/$jobNo';
      final result = await _dio.get(
        url,
        queryParameters: {
          'status': status,
        },
        cancelToken: cancelToken,
      );
      final mapResult = ResponseModel.fromJson(result.data);

      return mapResult;
    } catch (e) {
      //print('object $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>?> getJobAssign() async {
    try {
      CancelToken cancelToken = CancelToken();
      final result =
          await _dio.get('/v2/jobs/assign', cancelToken: cancelToken);
      var listOfAssign = List<Map<String, dynamic>>.from(result.data ?? []);
      //print(listOfAssign);
      return listOfAssign;
    } catch (e) {
      //print('object $e');
      rethrow;
    }
  }

  Future<ResponseModel> checkJob(String jobNo, String action) async {
    try {
      final result = await _dio.get(
        '/v2/jobs/activity/last/$jobNo',
        queryParameters: {'action': action},
      );
      return ResponseModel.fromJson(result.data!);
    } catch (e) {
      //print('object $e');
      rethrow;
    }
  }

  Future<List<LocationViewModel>?> getLocationDetail(int? detailId,
      [int? locationId, String? deliveryFlag]) async {
    try {
      CancelToken cancelToken = CancelToken();
      final result = await _dio.get(
        '/v1/jobs/locations/$detailId',
        cancelToken: cancelToken,
      );

      if ((result.data as List).isNotEmpty) {
        return (result.data as List)
            .map((e) => LocationViewModel.fromMap(e))
            .toList();
      }
      return [];
    } catch (e) {
      //print('object $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> putJobUpdateStatus(
      JobUpdateStatusFormModel model) async {
    try {
      var data = model.toMap();

      CancelToken cancelToken = CancelToken();

      final result = await _dio.put(
        '/v1/jobs/accepted/${model.jobNo}',
        data: data,
        queryParameters: {
          'flagCompany': model.vehicleSupplierFlag,
          'platform': 'Mobile',
        },
        cancelToken: cancelToken,
      );

      return Map.from(result.data);
    } catch (dioError) {
      //print('----> [ JOB ACCEPT ERROR $dioError ] ');
      rethrow;
    }
  }

  Future<ResponseModel> updateJobStart(
      double detailId, JobActivityForm model) async {
    try {
      CancelToken cancelToken = CancelToken();
      model.platform = 'Mobile';
      var dataToStart = model.toMap();

      try {
        if (GetUtils.isNumericOnly(
            dataToStart['createdDt']?.toString() ?? '')) {
          int ts = dataToStart['createdDt'];
          DateTime tsdate = DateTime.fromMillisecondsSinceEpoch(ts);
          dataToStart['createdDt'] = tsdate.toIso8601String();
        }
      } catch (e) {}

      PackageInfo packageInfo = await PackageInfo.fromPlatform();

      final result = await _dio.put(
        '/v1/jobs/start/by/$detailId',
        data: dataToStart,
        queryParameters: {
          'supplierFlag': model.supplierFlag,
        },
        cancelToken: cancelToken,
      );

      return ResponseModel.fromJson(result.data);
    } catch (e) {
      //print('----> [ JOB updateJobStart ERROR $e ] ');
      await JobsController().sendCatchError('START');
      rethrow;
    }
  }

  Future<ResponseModel> updateJobFinish(
      String jobNo, JobActivityForm model) async {
    try {
      CancelToken cancelToken = CancelToken();
      var dataToFinish = model.toMap();

      final result = await _dio.put(
        '/v1/jobs/finish/by/$jobNo',
        data: dataToFinish,
        cancelToken: cancelToken,
      );
      //print('onsuccess $result');

      return ResponseModel.fromJson(result.data);
    } catch (dioError) {
      //print('----> [ JOB updateJobFinish ERROR $dioError ] ');
      await JobsController().sendCatchError('FINISH');

      rethrow;
    }
  }

  Future<dynamic> updateLocation(JobUpdateLocation model) async {
    try {
      CancelToken cancelToken = CancelToken();
      var dataNew = model.toMap();

      final result = await _dio.put(
        '/v1/jobs/location/update',
        data: dataNew,
        queryParameters: {
          'vSubContractFlag': model.vSubContractFlag,
          'deliveryFlag': model.deliveryFlag,
        },
        cancelToken: cancelToken,
      );

      return result.data;
    } catch (dioError) {
      //print('----> [ JOB ACCEPT ERROR $dioError ] ');
      await JobsController().sendCatchError('LOCATION');
      rethrow;
    }
  }

  Future<ResponseModel?> getJobActiveLicensePlate(String? licensePlate) async {
    try {
      CancelToken cancelToken = CancelToken();

      final result = await _dio.get(
        '/v2/jobs/active/license-plate',
        queryParameters: {
          'licensePlate': licensePlate,
        },
        cancelToken: cancelToken,
      );
      return ResponseModel.fromJson(result.data);
    } catch (dioError) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> finishJob(
      String jobNo, JobActivityForm model) async {
    try {
      CancelToken cancelToken = CancelToken();

      final result = await _dio.put(
        '/v1​/jobs​/finish​/by​/$jobNo',
        data: model.toJson(),
        cancelToken: cancelToken,
      );
      //print('onsuccess $result');
      return Map.from(result.data);
    } catch (dioError) {
      //print('----> [ JOB Finish ERROR $dioError ] ');
      rethrow;
    }
  }

  Future<List<JobHeader>?> getJobActiveNonStart(
      [String status = 'ACTIVE']) async {
    try {
      CancelToken cancelToken = CancelToken();
      final result = await _dio.get(
        '/v1/jobs/assign/by/status',
        queryParameters: {'status': status},
        cancelToken: cancelToken,
      );

      return (result.data as List).map((element) {
        return JobHeader.fromMap(element);
      }).toList();
    } catch (dioError) {
      //print('----> [ GET JOB ACTIVE ERROR $dioError ] ');
      rethrow;
    }
  }

  Future<ResponseModel?> getJobsV2() async {
    try {
      CancelToken cancelToken = CancelToken();
      final result = await _dio.get(
        '/v2/jobs/all',
        cancelToken: cancelToken,
      );

      ResponseModel mapResult = ResponseModel.fromJson(result.data);

      return mapResult;
    } catch (dioError) {
      //print('----> [ GET JOB ACTIVE ERROR $dioError ] ');
      rethrow;
    }
  }

  Future<ResponseMileViewModel?> getMileVehilce() async {
    try {
      final getVhicleInfo = BoxCacheUtil.getVehicle;
      CancelToken cancelToken = CancelToken();
      int? mappointId = int.tryParse(getVhicleInfo?.mappointId ?? '');

      final result = await _dio.get(
        '/v1/mappoint/current/mileage',
        queryParameters: {
          'vehicleId': mappointId,
          'licensePlate': getVhicleInfo?.licensePlate,
          'province': getVhicleInfo?.licenseProvince
        },
        cancelToken: cancelToken,
      );

      var mapResult = ResponseMileViewModel.fromMap(result.data);

      //print('getMileVehilce $result');
      return mapResult;
    } catch (dioError) {
      //print('----> [ GET getMileVehilce$dioError ] ');
      rethrow;
    }
  }

  Future<ResponseModel> putUpdateMileage({
    required double currentMile,
    required String jobNo,
    required File file,
    String action = 'START',
  }) async {
    try {
      CancelToken cancelToken = CancelToken();

      String fileName = path.basenameWithoutExtension(file.path);

      FormData formData = FormData.fromMap({
        "file": await MultipartFile.fromFile(
          file.path,
          filename: fileName,
          contentType: MediaType.parse('image/jpeg'),
        ),
      });

      final result = await _dio.put(
        '/v1/jobs/upload/images/mileage/$jobNo',
        data: formData,
        cancelToken: cancelToken,
        queryParameters: {
          'action': action,
          'currentMile': currentMile,
        },
      );

      //print('result update mile $result');
      return ResponseModel.fromJson(result.data);
    } catch (dioError) {
      //print('----> [ GET getMileVehilce$dioError ] ');
      rethrow;
    }
  }

  Future<void> updateIems({
    required UpdateStatusDelivery dataToCreate,
  }) async {
    try {
      Map<String, dynamic> formData = dataToCreate.toMap();
      FormData datatoUpload = FormData.fromMap(formData);
      await _dio.put(
        '/v2/jobs/shipment/delivery/saveIems/${dataToCreate.jobLocationId}',
        data: datatoUpload,
      );
    } catch (e) {
      //print('----> [ UPDATE LOCATION IEMS WITHOUT IMAGE\n$e ] ');
      await JobsController().sendCatchError("DELIVERY");
    }
  }

  Future<ResponseModel?> putUpdateDeliveryStatus({
    required UpdateStatusDelivery dataToCreate,
    required List<File> files,
  }) async {
    try {
      Map<String, dynamic> formRequest = dataToCreate.toMap();
      formRequest['fileRequest'] = [];
      for (var e in files) {
        String fileName = e.path.split('/').last;
        var res = MultipartFile.fromFileSync(
          e.path,
          filename: fileName,
          contentType: MediaType.parse('image/jpeg'),
        );
        //print(res);
        formRequest['fileRequest'].add(res);
      }
      FormData formData = FormData.fromMap(formRequest);
      final result = await _dio.put(
        '/v2/jobs/shipment/delivery/${dataToCreate.jobLocationId}',
        data: formData,
      );

      //print('result update mile $result');

      if (result.statusMessage == 'OK') {
        // files = files.map((e) => formData).cast<File>().toList();
        //  files.clear();
        formData.files.clear();
      }

      return ResponseModel.fromJson(result.data);
    } catch (dioError) {
      //print('----> [ GET getMileVehilce$dioError ] ');
      await JobsController().sendCatchError("DELIVERY");
      rethrow;
    }
  }

  Future<void> postcurrentLocation(data) async {
    try {
      final result = await _dio.post('/v1/mobile/location/log', data: data);

      //print('log location success: $result');
    } on DioError {
      //print(
      //   'log location error: ${dioError.response?.data ?? dioError.message}');
      rethrow;
    }
  }

  Future<ResponseModel?> putPackageScans(data) async {
    try {
      CancelToken cancelToken = CancelToken();
      final result = await _dio.put('/v1/package-scan/shipment',
          data: data, cancelToken: cancelToken);
      //print('onsuccess $result');
      return ResponseModel.fromJson(result.data);
    } catch (dioError) {
      //print('----> [ JOB Finish ERROR $dioError ] ');
      await JobsController().sendCatchError('PACKAGE');
      rethrow;
    }
  }

  Future postMessage(String message) async {
    try {
      var dataToPost = {
        "message": message,
      };
      await _dio.post('/v2/jobs/delivery/notification', data: dataToPost);
    } catch (dioError) {
      //print('----> [ JOB Finish ERROR $dioError ] ');
      rethrow;
    }
  }

  Future<ResponseModel?> getCheckOutWorkTimeFlag(jobNo) async {
    try {
      CancelToken cancelToken = CancelToken();
      final result = await _dio.get(
        '/v2/jobs/check/finger-scan/four-hour/$jobNo',
      );
      return ResponseModel.fromJson(result.data);
    } catch (dioError) {
      rethrow;
    }
  }

  Future<ResponseModel?> getCheckFingerScan(jobNo) async {
    try {
      CancelToken cancelToken = CancelToken();
      final result = await _dio.get(
        '/v2/jobs/check/finger-scan/$jobNo',
      );
      return ResponseModel.fromJson(result.data);
    } catch (dioError) {
      rethrow;
    }
  }

  Future<List?> getHistory(emp) async {
    try {
      final result = await _dio.get(
        '/v2/jobs/History/jobs-finished/$emp',
      );

      return result.data;
    } catch (dioError) {
      rethrow;
    }
  }

  Future<ResponseModel?> uploadSignatureByLocationId(
    double locationId,
    String name,
    String filePath, {
    List<int>? fileByte,
  }) async {
    try {
      File signatureFIle = File(filePath);
      String fileName = path.basename(signatureFIle.path);

      MultipartFile? res;
      bool readFilePathError = false;
      try {
        res = MultipartFile.fromFileSync(
          signatureFIle.path,
          filename: fileName,
          contentType: MediaType.parse('image/jpeg'),
        );
      } catch (e) {
        readFilePathError = true;
      }
      if (fileByte != null && readFilePathError) {
        res = MultipartFile.fromBytes(fileByte,
            contentType: MediaType.parse('image/jpeg'));
      }

      FormData formData = FormData.fromMap({'file': res});
      final result = await _dio.put(
        '/v1/package-scan/signature/location/$locationId',
        data: formData,
        queryParameters: {
          'name': name,
        },
      );
      //print('onsuccess $result');
      return ResponseModel.fromJson(result.data);
    } catch (dioError) {
      //print('----> [ JOB Finish ERROR $dioError ] ');
      rethrow;
    }
  }

  Future<ResponseModel?> uploadPackageScanImageByLocationId(
      double locationId, List<String> filePaths,
      [List<List<int>>? filesBypte]) async {
    try {
      List<MultipartFile> files = [];
      int fileI = 0;
      for (var f in filePaths) {
        File image = File(f);
        String fileName = path.basename(image.path);

        bool isOpenFileOk = false;
        MultipartFile? res;
        try {
          var readFile = image.existsSync();
          if (readFile) {
            res = MultipartFile.fromFileSync(
              image.path,
              filename: fileName,
              contentType: MediaType.parse('image/jpeg'),
            );
            isOpenFileOk = true;
          }
        } catch (e) {
          isOpenFileOk = false;
        }

        if (!isOpenFileOk && filesBypte != null) {
          res = MultipartFile.fromBytes(
            filesBypte[fileI],
            filename: fileName,
            contentType: MediaType.parse('image/jpeg'),
          );
        }

        files.add(res!);
        fileI++;
      }

      FormData formData = FormData.fromMap({'files': files});

      final result = await _dio.put(
        '/v2/package-scan/upload/scan/image/$locationId',
        data: formData,
      );
      //print('onsuccess $result');
      return ResponseModel.fromJson(result.data);
    } catch (dioError) {
      //print('----> [ JOB Finish ERROR $dioError ] ');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getDataIems(String job) async {
    try {
      final result = await _dio.get('/v2/jobs/datafromiems/$job');
      // print(result.data);
      return result.data;
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> checkCardReady(String qr) async {
    try {
      var res = await _dio.get('/v1/starbuck/check/card-ready?$qr');

      return res.data;
    } catch (e) {
      rethrow;
    }
  }

  ///v2/systems/resync/data-auto
  // Future<ResponseModel?> resyncDataAuto() async {
  //   try {
  //     var res = await _dio.get('/v2/systems/resync/data-auto');
  //     print(res);
  //     return ResponseModel.fromJson(res.data);
  //   } catch (e) {
  //     print(e);
  //   }
  //   return null;
  // }
}
