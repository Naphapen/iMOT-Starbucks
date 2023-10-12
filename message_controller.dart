import 'package:get/get.dart';
import 'package:imot/common/firebase/firebase_notifications.dart';

class MessageController extends GetxController {
  List<Map<String, dynamic>> listOfMessage = [];

  RxBool isLoading = true.obs;
  RxBool reloadData = false.obs;

  // RxInt totalAssignment = listOfDetail.length;
  int get countMessage => listOfMessage.length;

  FirebaseNotifications get firebase => FirebaseNotifications();

  @override
  void onInit() {
    super.onInit();
    isLoading(false);
    init();
    update();
  }

  void init() {}

  void add(Map<String, dynamic> message) async {
    isLoading(true);
    await Future.delayed(const Duration(milliseconds: 200)).then((value) {
      listOfMessage.add(message);
      isLoading(false);
      update();
      //print('total message $countMessage');
    });
  }

  Future<bool>? onLoading() {
    return null;
  }
}
