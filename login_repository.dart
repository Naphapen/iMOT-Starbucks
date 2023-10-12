import 'package:dio/dio.dart';
import 'package:imot/common/cache/box_cache.dart';
import 'package:imot/common/models/shared/user_profile.dart';
import 'package:imot/common/models/shared/user_token.dart';
import 'package:imot/common/models/view/login_response_model.dart';
import 'package:imot/Api_Repository_Service/dio/api_base_helper.dart';
import 'package:imot/Api_Repository_Service/services/system_info_service.dart';

class LoginRepository {
  late Dio _dio;
  LoginRepository() {
    ApiBaseHelper.allowHttps = true;
    _dio = ApiBaseHelper.dio;
    ApiBaseHelper.addInterceptors(_dio);
  }

  Future<LoginResponseModel?> login(String username, String password,
      String? mobileId, String? fcmToken) async {
    try {
      var version = await SystemInfoService().getAppInfo();
      Response res = await _dio.post('/v1/users/auth', data: {
        "Username": username,
        "Password": password,
        "FCMToken": fcmToken,
        "MobileId": mobileId,
        'AppVersion': version.version,
      });

      LoginResponseModel model = LoginResponseModel.fromJson(res.data);

      return model;
    } catch (e) {
      rethrow;
    }
  }

  Future<LoginResponseModel?> loginEmployee(String employeeNo) async {
    try {
      var version = await SystemInfoService().getAppInfo();
      Response res = await _dio.post('/v1/users/auth/employee', data: {
        'Username': employeeNo,
        "Password": null,
        "FCMToken": null,
        "MobileId": null,
        'AppVersion': version.version,
      });

      LoginResponseModel model = LoginResponseModel.fromJson(res.data);

      return model;
    } catch (e) {
      rethrow;
    }
  }

  Future<UserProfile?> getMe() async {
    try {
      Response res = await _dio.get(
        '/v1/users/me',
        options: Options(headers: {
          'gToken': BoxCacheUtil.getFCMToken,
        }),
      );
      return UserProfile.fromJson(res.data['results']);
    } catch (e) {
      rethrow;
    }
  }

  Future<UserToken?> refreshToken(
    String refreshToken,
  ) async {
    try {
      Response res =
          await _dio.post('/v1/users/refresh-token', data: refreshToken);

      UserToken model = UserToken.fromJson(res.data);

      return model;
    } catch (e) {
      rethrow;
    }
  }
}
