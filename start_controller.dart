import 'package:get/get.dart';
import 'package:imot/common/cache/box_cache.dart';
import 'package:imot/common/models/shared/user_profile.dart';
import 'package:imot/common/models/view/job_header.dart';
import 'package:imot/common/shared/app_enum.dart';
import 'package:imot/database/database.dart';

class StartController extends GetxController {
  RxBool isLoading = true.obs;
  final RxList<JobHeader> jobStart = <JobHeader>[].obs;

  AppDatabase get db => AppDatabase.provider;

  UserProfile? user = BoxCacheUtil.getAuthUser;

  @override
  void onInit() {
    super.onInit();

    loadData();
  }

  Future<void> loadData() async {
    try {
      isLoading(true);
      jobStart.bindStream(getJobStartStreem());
    } finally {
      isLoading(false);
      update();
    }
  }

  Stream<List<JobHeader>> getJobStartStreem() {
    final jobHeaders = db.watchJobHeaders(
      userId: user!.id!,
      statusCodes: [JobStatus.START.name],
    );

    return jobHeaders;
  }
}
