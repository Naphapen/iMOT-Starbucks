import 'package:dio/dio.dart';
import 'package:imot/Api_Repository_Service/dio/api_base_helper.dart';

class OptionRepository {
  late Dio _dio;
  OptionRepository() {
    ApiBaseHelper.allowHttps = true;
    _dio = ApiBaseHelper.dio;
    ApiBaseHelper.addInterceptors(_dio);
  }

  Future<List<Map<String, dynamic>>> getExcaptionAll() async {
    final res = await _dio.get('/v1/options/exception');

    return List.from(res.data);
  }

  Future<List<Map<String, dynamic>>> getExcaptionDLY() async {
    final res = await _dio.get('/v1/options/exception/dly');

    return List.from(res.data);
  }
}
