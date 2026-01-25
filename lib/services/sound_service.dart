import 'package:audioplayers/audioplayers.dart';

class SoundService {
  static final AudioPlayer _player = AudioPlayer();
  static final AudioPlayer _loopPlayer = AudioPlayer();

  static Future<void> playConnected() async {
    await _stopLoop();
    await _player.play(AssetSource('call-connected.mp3'));
  }

  static Future<void> playEnded() async {
    await _stopLoop();
    await _player.play(AssetSource('call-ended.mp3'));
  }

  static Future<void> playError() async {
    await _stopLoop();
    await _player.play(AssetSource('error-busy-hung.mp3'));
  }

  static Future<void> playPing() async {
    await _player.play(AssetSource('ping.mp3'));
  }

  static Future<void> playSwitch() async {
    await _player.play(AssetSource('switch-call.mp3'));
  }

  static Future<void> startOutgoingRing() async {
    await _loopPlayer.setReleaseMode(ReleaseMode.loop);
    await _loopPlayer.play(AssetSource('outgoing.mp3'));
  }

  static Future<void> startIncomingRing() async {
    // Usually handled by CallKit, but for in-app header notification:
    await _loopPlayer.setReleaseMode(ReleaseMode.loop);
    await _loopPlayer.play(AssetSource('incoming.mp3'));
  }

  static Future<void> stopRing() async {
    await _stopLoop();
  }

  static Future<void> _stopLoop() async {
    try {
      await _loopPlayer.stop();
      await _loopPlayer.release();
    } catch (e) {
      // ignore
    }
  }
}
