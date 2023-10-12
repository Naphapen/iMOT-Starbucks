import 'package:dio/dio.dart';
import 'package:imot/Api_Repository_Service/dio/api_base_helper_iems.dart';

class IemsRepositoryS {
  late Dio _dio;
  IemsRepositoryS() {
    ApiBaseHelperIems.allowHttps = true;
    _dio = ApiBaseHelperIems.dio;
    ApiBaseHelperIems.addInterceptors(_dio);
  }

  Future<Map<String, dynamic>> getJobSummaryNSL() async {
    try {
      final result =
          await _dio.get('/v2/job-monitoring/all/active', queryParameters: {
        'VehicleDeptTypeId': 4,
        'JobDT': '2023-02-09',
        'JobNo': 'JO2302090206',
        'WithOutMappointFlag': 'N',
        // 'CurrentPage': 1,
        // 'PageSize': 50,
        // 'PageCount': 1,
        // 'RecordCount': 1
      });
      // print(result.data);
      return result.data;
    } catch (e) {
      rethrow;
    }
  }
}
