import 'package:dio/dio.dart';
import 'package:imot/Api_Repository_Service/dio/api_base_helper.dart';
import 'package:imot/common/models/view/vehicle_view_model.dart';

class IemsRepository {
  late Dio _dio;
  IemsRepository() {
    ApiBaseHelper.allowHttps = true;
    _dio = ApiBaseHelper.dio;
    ApiBaseHelper.addInterceptors(_dio);
  }

  Future<VehicleViewModel?> fetchVehicle(String licensePlate) async {
    try {
      await Future.delayed(const Duration(seconds: 2));

      final result = await _dio.get(
        '/v1/users/vehicle/active',
        queryParameters: {
          'licensePlate': licensePlate,
        },
      );

      return VehicleViewModel.fromMap(result.data);
    } catch (e) {
      //print('object $e');
    }
    return null;
  }
//?VehicleDeptTypeId=4&JobDT=2023-02-08&JobNo=JO2302080171

}
