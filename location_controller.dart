import 'dart:async';

import 'package:get/get.dart';
import 'package:imot/common/models/view/location_view_model.dart';
import 'package:imot/Api_Repository_Service/repositories/job_repository.dart';
import 'package:imot/Api_Repository_Service/services/location_service.dart';

class LocationController extends GetxController {
  LocationController();
  RxBool isLoading = true.obs;
  List<LocationViewModel> listOfLocation = [];

  final LocationService _locationService = LocationService();
  int get countAllLocation => listOfLocation.length;
  LocationService get locationService => _locationService;

  Future<void> fetchDataLocation(int? detailId) async {
    isLoading(true);

    await JobRepository().getLocationDetail(detailId).then((value) {
      listOfLocation = value ?? [];
      //print(value);
      isLoading(false);
      update();
    }).catchError((onError) {
      //print(onError);
      isLoading(false);
      update();
    }).then((value) => update());
  }
}
