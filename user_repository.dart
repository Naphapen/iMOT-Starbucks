import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:imot/common/models/shared/auth_status.dart';
import 'package:imot/common/models/shared/user_profile.dart';
import 'package:imot/common/models/view/login_response_model.dart';
import 'package:imot/Api_Repository_Service/dio/api_base_helper.dart';

class UserRepository extends ChangeNotifier {
  AuthStatus _status = AuthStatus.Uninitialized;
  UserProfile? _user;
  AuthStatus get status => _status;

  late Dio _dio;

  UserRepository.instance() {
    ApiBaseHelper.allowHttps = true;
    _dio = ApiBaseHelper.dio;
    ApiBaseHelper.addInterceptors(_dio);
  }

  UserProfile? get user => _user;

  Future<Map<String, dynamic>> getEmployee(String empNo) async {
    Response res = await _dio.get('/v1/users/employee/$empNo');
    return Map.from(res.data);
  }

  Future<bool> signIn(String username, String password, String? mobileId,
      String? fcmToken) async {
    try {
      _status = AuthStatus.Authenticating;
      notifyListeners();

      Response res = await _dio.post('/v1/users/auth', data: {
        "Username": username,
        "Password": password,
        "FCMToken": fcmToken,
        "MobileId": mobileId
      });

      LoginResponseModel model = LoginResponseModel.fromJson(res.data);
      _user = model.results;

      return true;
    } catch (e) {
      _status = AuthStatus.Unauthenticated;
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>> postRigister(Map data) async {
    try {
      Response res = await _dio.post('/v1/users/registration', data: {
        "username": data['username'],
        "password": data['password'],
        "fcmToken": data['fcmToken'],
        "mobileId": data['mobileId'],
        "employeeNo": data['employeeNo'],
        "mobileVersion": data['mobileVersion'],
        "routeId": data['routeId'],
        "routeCode": data['routeCode'],
        "routeType": data['routeType'],
        "dcId": data['dcId'],
        "dcCode": data['dcCode'],
        "dcThDesc": data['dcThDesc'],
        "dcEnDesc": data['dcEnDesc'],
        "vehicleId": data['vehicleId'],
        "vehicleCode": data['vehicleCode'],
        "vehicleSupplierFlag": data['vehicleSupplierFlag'],
        "licensePlat": data['licensePlat'],
        "licenseProvince": data['licenseProvince']
      });
      return res.data;
    } catch (e) {
      //print(e);
      rethrow;
    }
  }

  Future signOut() async {
    _status = AuthStatus.Unauthenticated;
    notifyListeners();
    return Future.delayed(Duration.zero);
  }

  // Future<void> _onAuthStateChanged(UserProfile? user) async {
  //   if (user == null) {
  //     _status = AuthStatus.Unauthenticated;
  //   } else {
  //     _user = user;
  //     _status = AuthStatus.Authenticated;
  //   }
  //   notifyListeners();
  // }
}
