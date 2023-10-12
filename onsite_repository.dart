import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:imot/Api_Repository_Service/dio/api_base_helper.dart';
import 'package:imot/common/Other/date_utils.dart';
import 'package:imot/common/models/form/onsite/sop_package_scan.dart';
import 'package:imot/common/models/shared/response_model.dart';
import 'package:imot/common/models/view/onsite/sop_del_view_model.dart';

abstract class IOnsiteRepository {
  Future<Map<String, dynamic>?> getSopDelPagined(
      {String? driverNo, String? batchOnsiteNo, DateTime? createdDt});

  Future<Map<String, dynamic>> getBatchNo(
      {String? driverNo, String? licensePlate});

  Future<Map<String, dynamic>> postSopScanPackage(SopPackageScan dataToCreate);

  Future<List<Map<String, dynamic>>> putStartBatch(
      List<Map<String, dynamic>> dataToCreate);

  Future<Map<String, dynamic>?> getSOPPackage({
    required String batchOnsiteNo,
    required String driverNo,
  });

  Future<Map<String, dynamic>?> unSOPByBranch({
    required String batchOnsiteNo,
    required String branchOnsiteCode,
    required String driverNo,
  });

  Future<Map<String, dynamic>?> getPackage({
    required String branchOnsiteCode,
  });
}

class OnsiteRepository implements IOnsiteRepository {
  late Dio _dio;
  OnsiteRepository() {
    ApiBaseHelper.allowHttps = true;

    _dio = ApiBaseHelper.dio;

    ApiBaseHelper.addInterceptors(_dio);
  }

  static String urlIEMS = dotenv.get('BASE_IEMS_API');

  //////////////// NEW ONSITE ////////////////

  Future<Map<String, dynamic>> getQrCodeByBatch(String? batchNo) async {
    try {
      final result = await Dio().get(
        '$urlIEMS/v2/job-mobile/batch/by-batch',
        queryParameters: {
          'BatchOnsiteNo': batchNo,
        },
      );
      return result.data;
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> newGetBatchNo({required String jobNo}) async {
    try {
      final result = await _dio.get(
        '/v2/jobs/onsite/batch/by-job',
        queryParameters: {
          'job_no': jobNo,
        },
      );
      return result.data;
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>?> getNameBranch(
      {required String keyword}) async {
    try {
      ///onsite/company/branch?CompanyOnsiteId
      ///
      var result = await Dio().get(
        '$urlIEMS/v2/store-starbucks/company/branch/1',
        // '$urlIEMS/v2/job-mobile/mhub-sip/imot-sop/branch',
        queryParameters: {
          //  'CompanyOnsiteId': 1,
          // 'Keyword': keyword,
          'BranchOnsiteThName': keyword
        },
      );
      return List.from(result.data);
      // return result.data['Results'].first['BranchOnsiteThName'];
    } catch (e) {
      rethrow;
    }
  }

  ///////////////////////////////////////////

  @override
  Future<Map<String, dynamic>?> getSopDelPagined({
    String? driverNo,
    String? batchOnsiteNo,
    DateTime? createdDt,
  }) async {
    try {
      createdDt ??= DateTime.now();

      final result = await _dio.get(
        '$urlIEMS/v2/onsite/imot/sop/del',
        queryParameters: {
          'driverNo': driverNo,
          'createdDt': dateUtils.formattedDate(createdDt, 'yyyy-MM-dd'),
          'batchOnsiteNo': batchOnsiteNo,
        },
      );

      return result.data;
    } catch (e) {
      //print('object $e');
    }
    return null;
  }

  Future<List<dynamic>?> getBatchCheckLocal(String batchOnsiteNo) async {
    try {
      final result = await _dio.get(
        '$urlIEMS/v2/onsite/imot/sop/batch',
        queryParameters: {
          'BatchOnsiteNo': batchOnsiteNo,
        },
      );
      return result.data;
    } catch (e) {
      //print('object $e');
    }
    return null;
  }

  Future<List<dynamic>?> getBatchDetail(Map<String, dynamic> data) async {
    try {
      final result = await _dio.get(
        '$urlIEMS/v2/onsite/imot/sop/del',
        queryParameters: data,
      );
      return result.data['Results'];
    } catch (e) {
      //print('object $e');
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>?> getSOPPackageByBranch({
    String? branchCode,
  }) async {
    try {
      final result = await _dio.get(
        '$urlIEMS/v2/onsite/imot/sop/package',
        queryParameters: {
          'branchOnsiteCode': branchCode,
        },
      );

      return result.data;
    } catch (e) {
      //print('object $e');
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>?> getSOPPackage({
    required String batchOnsiteNo,
    required String driverNo,
  }) async {
    final result =
        await _dio.get('$urlIEMS/v2/onsite/imot/sop/pod', queryParameters: {
      'batchOnsiteNo': batchOnsiteNo,
      'driverNo': driverNo,
    });

    return result.data;
  }

  @override
  Future<Map<String, dynamic>?> unSOPByBranch({
    required String batchOnsiteNo,
    required String branchOnsiteCode,
    required String driverNo,
  }) async {
    try {
      final result =
          await _dio.delete('/v2/jobs/onsite/unsop/by/branch', data: {
        'batchOnsiteNo': batchOnsiteNo,
        'branchOnsiteCode': branchOnsiteCode,
        'driverNo': driverNo,
      });

      return result.data;
    } catch (e) {
      //print('object $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> onSOPByPackage({
    required String batchOnsiteNo,
    required String branchOnsiteCode,
    required String driverNo,
  }) async {
    try {
      final result =
          await _dio.delete('/v2/jobs/onsite/unsop/by/branch', data: {
        'BatchOnsiteNo': batchOnsiteNo,
        'BranchOnsiteCode': branchOnsiteCode,
        'DriverNo': driverNo,
      });

      return result.data;
    } catch (e) {
      //print('object $e');
    }
    return null;
  }

  Future<List<Map<String, dynamic>>?> getCompanyOnsiteByBranch({
    required int branchId,
  }) async {
    try {
      final result = await _dio.get('/v2/jobs/onsite/branch/$branchId');

      return List.from(result.data);
    } catch (e) {
      //print('object $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> postSopPOD({
    required Map<String, dynamic> dataToUpdate,
  }) async {
    try {
      final result = await _dio.post(
        '/v2/jobs/onsite/sop/package/pod',
        data: dataToUpdate,
      );

      return result.data;
    } catch (e) {
      //print('object $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> getOnsiteSOPStatus({
    String? sopEquipmentBy,
    String? batchOnsiteNo,
    String? dt,
    String? status = 'DEFAULT',
  }) async {
    try {
      final result =
          await _dio.get('/v2/jobs/onsite/sop/status', queryParameters: {
        'sopEquipmentBy': sopEquipmentBy,
        'batchOnsiteNo': batchOnsiteNo,
        'dt': dt,
        'status': status,
      });
      var rrr = SopDelViewModel.fromMap(result.data['Result']);
      IMOTResponse<List<SopDelViewModel>>();
      return result.data;
    } catch (e) {
      //print('object $e');
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>> getBatchNo({
    String? driverNo,
    String? licensePlate,
  }) async {
    Map<String, dynamic> messages = {};
    try {
      final result =
          await _dio.get('/v2/jobs/onsite/generate/batch/no', queryParameters: {
        'driverNo': driverNo,
        'licensePlate': licensePlate,
      });

      if (result.data['ResponseCode'] == 'OK') {
        messages.addAll({
          'result': result.data['Results'],
          'isValid': true,
        });
      } else {
        messages.addAll({
          'result':
              result.data?['Results']?['Message'] ?? result.data['Results'],
          'isValid': false,
        });
      }
    } on DioError catch (e) {
      //print('object $e');
      messages.addAll({
        'result': e.response!.data?['Results']?['Message'] ?? e.message,
        'isValid': false,
      });
    }
    return messages;
  }

  @override
  Future<Map<String, dynamic>> postSopScanPackage(
    SopPackageScan dataToCreate,
  ) async {
    try {
      var mapdata = dataToCreate.toMap();

      final result = await _dio.post(
        '/v2/jobs/onsite/sop/package',
        data: mapdata,
      );

      return result.data == "" ? {'ResponseCode': 'OK'} : {};
    } catch (e) {
      //print('object $e');
      rethrow;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> putStartBatch(
    List<Map<String, dynamic>> dataToCreate,
  ) async {
    try {
      final result = await _dio.put(
        '/v2/jobs/onsite/sop/start',
        data: dataToCreate,
      );

      List<Map<String, dynamic>> outt = [];

      if (result.data is Map) {
        outt.add(result.data);
      } else {
        outt = List<Map<String, dynamic>>.from(result.data);
      }

      return outt;
    } catch (e) {
      //print('object $e');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>?> getPackage({
    required String branchOnsiteCode,
  }) async {
    final result = await _dio.get(
      '$urlIEMS/v2/onsite/imot/sop/package',
      queryParameters: {
        'branchOnsiteCode': branchOnsiteCode,
      },
    );

    return result.data;
  }

  @override
  Future postSopImage({
    required Map<String, dynamic> sopImage,
  }) async {
    final result = await _dio.post(
      '$urlIEMS/v2/onsite/imot/sop/image',
      data: sopImage,
    );
    return result.data;
  }
}
