import 'package:get/get.dart';
import 'package:imot/common/cache/box_cache.dart';
import 'package:imot/common/models/shared/user_profile.dart';
import 'package:imot/common/models/view/job_header.dart';
import 'package:imot/common/shared/app_enum.dart';
import 'package:imot/database/database.dart';

class AcceptController extends GetxController {
  RxBool isLoading = true.obs;
  final RxList<JobHeader> jobAccepts = <JobHeader>[].obs;
  // final RxList<JobHeader> jobs = <JobHeader>[].obs;
  List jobs = [];

  AppDatabase get db => AppDatabase.provider;

  UserProfile? user = BoxCacheUtil.getAuthUser;

  @override
  void onInit() {
    super.onInit();

    loadData();
    loadData2();
  }

  Future<void> loadData() async {
    try {
      isLoading(true);
      jobAccepts.bindStream(getJobAcceptsStreem());
    } finally {
      isLoading(false);
      update();
    }
  }

  Future<List?> loadData2() async {
    try {
      isLoading(true);
      var res = await (db.select(db.jobHeaderEntries)
            ..where((e) => e.jobLastStatusCode.isIn(['ACCEPT', 'ACTIVE'])))
          .get();
      res.sort((a, b) => (DateTime.tryParse(b.acceptDt!) ?? DateTime.now())
          .compareTo(DateTime.tryParse(a.acceptDt!) ?? DateTime.now()));

      jobs.add(res);
    } finally {
      isLoading(false);
      update();
    }
    return null;
  }

  Stream<List<JobHeader>> getJobAcceptsStreem() {
    final jobHeaders = db.watchJobHeaders(
      userId: user!.id!,
      statusCodes: [
        JobStatus.ACCEPT.name,
        JobStatus.ACTIVE.name,
      ],
    );

    return jobHeaders;
  }
}
