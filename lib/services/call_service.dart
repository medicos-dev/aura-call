import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sound_service.dart';

enum CallType { audio, video }
enum CallState { idle, ringing, connecting, connected, ended }

/// Dummy Participant for UI Testing
class ParticipantConnection {
  final String participantId;
  MediaStream? localStream;
  MediaStream? remoteStream;
  bool isConnected = false;
  bool isAudioEnabled = true;
  bool isVideoEnabled = true;

  ParticipantConnection({required this.participantId});

  Future<void> dispose() async {
    for (final track in localStream?.getTracks() ?? []) {
      track.stop();
    }
  }
}

class CallService extends ChangeNotifier with WidgetsBindingObserver {
  String? _myCallId;
  MediaStream? _localStream;
  CallType _callType = CallType.audio;
  CallState _callState = CallState.idle;

  final Map<String, ParticipantConnection> _participants = {};

  Function(String participantId, MediaStream stream)? onRemoteStream;
  Function(String senderId, String senderName)? onIncomingCall;
  Function(String participantId)? onParticipantJoined;
  Function(String participantId)? onParticipantLeft;
  Function(CallState state)? onCallStateChanged;

  CallService() {
    WidgetsBinding.instance.addObserver(this);
  }

  String? get myCallId => _myCallId;
  CallState get callState => _callState;
  CallType get callType => _callType;
  MediaStream? get localStream => _localStream;
  List<ParticipantConnection> get participants => _participants.values.toList();
  int get participantCount => _participants.length;
  bool get isInCall =>
      _callState == CallState.connected || _callState == CallState.connecting;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _myCallId = prefs.getString('call_id');
  }

  Future<bool> startCall(String targetCallId, CallType type) async {
    if (_myCallId == null) return false;

    _callType = type;
    _updateCallState(CallState.ringing);
    await SoundService.startOutgoingRing();
    await _initializeLocalStream(type == CallType.video);

    final participant = ParticipantConnection(participantId: targetCallId);
    participant.localStream = _localStream;
    _participants[targetCallId] = participant;

    // Simulate backend response after 3 seconds
    Future.delayed(const Duration(seconds: 3), () async {
      if (_callState == CallState.ringing) {
        await SoundService.stopRing();
        _updateCallState(CallState.connected);
        await SoundService.playConnected();
        participant.isConnected = true;
        notifyListeners();
      }
    });

    return true;
  }

  Future<bool> acceptCall(String callerId, CallType type) async {
    _callType = type;
    _updateCallState(CallState.connecting);
    await SoundService.stopRing();
    await _initializeLocalStream(type == CallType.video);

    final participant = ParticipantConnection(participantId: callerId);
    participant.localStream = _localStream;
    _participants[callerId] = participant;

    Future.delayed(const Duration(seconds: 1), () async {
      _updateCallState(CallState.connected);
      await SoundService.playConnected();
      participant.isConnected = true;
      notifyListeners();
    });

    return true;
  }

  Future<bool> addParticipant(String targetCallId) async {
    if (!isInCall || _myCallId == null) return false;
    
    final participant = ParticipantConnection(participantId: targetCallId);
    participant.localStream = _localStream;
    _participants[targetCallId] = participant;

    Future.delayed(const Duration(seconds: 2), () {
      onParticipantJoined?.call(targetCallId);
      participant.isConnected = true;
      notifyListeners();
    });

    return true;
  }

  Future<void> _initializeLocalStream(bool withVideo) async {
    if (_localStream != null) return;
    try {
      final constraints = {
        'audio': true,
        'video': withVideo
            ? {
                'facingMode': 'user',
                'width': {'ideal': 1280},
                'height': {'ideal': 720},
              }
            : false,
      };
      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      notifyListeners();
    } catch (e) {
      debugPrint("Failed to get local stream: $e");
    }
  }

  Future<void> endCall() async {
    _updateCallState(CallState.ended);
    await _cleanup();
    await SoundService.stopRing();
  }

  Future<void> rejectCall(String callerId) async {
    await SoundService.stopRing();
    await SoundService.playError();
    _updateCallState(CallState.idle);
  }

  void toggleAudio() {
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = !track.enabled;
    });
    notifyListeners();
  }

  void toggleVideo() {
    _localStream?.getVideoTracks().forEach((track) {
      track.enabled = !track.enabled;
    });
    notifyListeners();
  }

  Future<void> switchCamera() async {
    final videoTrack = _localStream?.getVideoTracks().firstOrNull;
    if (videoTrack != null) {
      await Helper.switchCamera(videoTrack);
    }
  }

  void _updateCallState(CallState state) {
    _callState = state;
    onCallStateChanged?.call(state);
    notifyListeners();
  }

  Future<void> _cleanup() async {
    for (final participant in _participants.values) {
      await participant.dispose();
    }
    _participants.clear();
    await _localStream?.dispose();
    _localStream = null;
    _updateCallState(CallState.idle);
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await _cleanup();
    super.dispose();
  }
}
