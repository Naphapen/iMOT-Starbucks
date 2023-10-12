//import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';

enum SOUND {
  closejob,
  dup,
  ok1,
  ok2,
  ok3,
  ok4,
  ok5,
  ok6,
  ok7,
  ok8,
  ok9,
  ok10,
  startjob,
  scannedpass,
  beep,
}

extension ParseSoundToString on SOUND {
  String get name => describeEnum(this);
}

class AudioPlayerController extends GetxController {
  final _player = AudioPlayer();

  Future<void> paySound(SOUND sound, [String ext = 'm4a']) async {
    // Try to load audio from a source and catch any errors.
    try {
      // var res = await _player.setAsset('assets/sound/${sound.name}.$ext');
      await _player.setAsset('assets/sound/${sound.name}.$ext');
      _player.setVolume(0.3);
      //_player.play();
      // var duration = await _player.load();
      await _player.load();

      // Permanently release decoders/resources used by the player.

      await _player.play();

      //print(res);
    } catch (e) {
      //print("Error loading audio source: $e");
    }
  }

  Future<void> stop() => _player.stop();
}
