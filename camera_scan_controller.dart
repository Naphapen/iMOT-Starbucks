import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class CameraScanController extends GetxController {
  RxBool isLoading = false.obs;

  Rx<String?> barcode = Rx(null);
  final player = AudioPlayer();

  MobileScannerController mobileScancontroller = MobileScannerController(
    torchEnabled: false,
    facing: CameraFacing.back,
  );

  bool isStarted = true;

  void initAudio(
      [name = 'beep.m4a', bool isPlay = false, double volumn = 0.2]) async {
    try {
      player.setVolume(volumn);

      await player.setAsset('assets/sound/$name');

      if (isPlay) await play();
    } catch (e) {
      //print("Error loading audio source: $e");
    }
  }

  Future<void> play() async {
    await player.load();
    await player.play();
  }

  @override
  void onInit() {
    // //print('oniniste');
    super.onInit();
    initAudio();
  }

  void startCam() {
    mobileScancontroller.start();
  }

  void stopCam() {
    mobileScancontroller.stop();
  }

  void switchCam() {
    mobileScancontroller.switchCamera();
  }

  void clearScan() {
    isLoading(true);
    barcode('');
    isLoading(false);
    update();
  }

  @override
  void onClose() {
    super.onClose();
    barcode(null);
    player.dispose();
  }
}
