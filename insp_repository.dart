import 'package:dio/dio.dart';
import 'package:imot/Api_Repository_Service/dio/api_base_helper.dart';

class InspRepository {
  late Dio _dio;
  InspRepository() {
    ApiBaseHelper.allowHttps = true;
    _dio = ApiBaseHelper.dio;
    ApiBaseHelper.addInterceptors(_dio);
  }

  Future<List<Map<String, dynamic>>> getManifest(String manifestNo) async {
    try {
      var result = await _dio.get(
        '/v2/jobs/manifest/$manifestNo',
      );

      return List.from(result.data);
    } catch (e) {
      rethrow;
    }
  }
}
