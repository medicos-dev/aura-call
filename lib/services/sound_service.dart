import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

class SoundService with WidgetsBindingObserver {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal() {
    WidgetsBinding.instance.addObserver(this);
  }

  static final AudioPlayer _player = AudioPlayer();
  static final AudioPlayer _loopPlayer = AudioPlayer();

  // Track if app is in foreground
  static bool _isInForeground = true;
  static bool get isInForeground => _isInForeground;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isInForeground = state == AppLifecycleState.resumed;
  }

  static void init() {
    // Initialize the singleton to start observing lifecycle
    _instance;
  }

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
    await _stopLoop();
    await _loopPlayer.setReleaseMode(ReleaseMode.loop);
    await _loopPlayer.setSource(AssetSource('outgoing.mp3'));
    await _loopPlayer.resume();
  }

  static Future<void> startIncomingRing() async {
    // Used when app is in foreground (CallKit handles background)
    await _stopLoop();
    await _loopPlayer.setReleaseMode(ReleaseMode.loop);
    await _loopPlayer.setSource(AssetSource('incoming.mp3'));
    await _loopPlayer.resume();
  }

  static Future<void> stopRing() async {
    await _stopLoop();
  }

  static Future<void> _stopLoop() async {
    try {
      await _loopPlayer.stop();
    } catch (e) {
      // ignore
    }
  }
}
