import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'call_service.dart';

/// Controller for managing multi-party calls
/// Handles layout, participant ordering, and PiP state
class MultiCallController extends ChangeNotifier {
  final CallService _callService;

  // Maximum participants (6 for performance)
  static const int maxParticipants = 6;

  // PiP state for 1:1 calls
  String? _pipParticipantId;
  bool _isLocalInPip = true;

  // Fullscreen participant (for 1:1 mode)
  String? _fullscreenParticipantId;

  // Local video renderer
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();

  // Remote video renderers
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};

  MultiCallController(this._callService) {
    _initialize();
  }

  Future<void> _initialize() async {
    await localRenderer.initialize();

    // Listen to call service changes
    _callService.addListener(_onCallServiceUpdate);
    _callService.onRemoteStream = _onRemoteStream;
    _callService.onParticipantLeft = _onParticipantLeft;
  }

  void _onCallServiceUpdate() {
    // Update local stream
    if (_callService.localStream != null) {
      localRenderer.srcObject = _callService.localStream;
    }
    notifyListeners();
  }

  Future<void> _onRemoteStream(String participantId, MediaStream stream) async {
    if (!_remoteRenderers.containsKey(participantId)) {
      final renderer = RTCVideoRenderer();
      await renderer.initialize();
      _remoteRenderers[participantId] = renderer;
    }

    _remoteRenderers[participantId]!.srcObject = stream;

    // Set first remote participant as fullscreen
    if (_fullscreenParticipantId == null) {
      _fullscreenParticipantId = participantId;
    }

    notifyListeners();
  }

  void _onParticipantLeft(String participantId) {
    _disposeRenderer(participantId);

    if (_fullscreenParticipantId == participantId) {
      _fullscreenParticipantId =
          _remoteRenderers.keys.isNotEmpty ? _remoteRenderers.keys.first : null;
    }

    if (_pipParticipantId == participantId) {
      _pipParticipantId = null;
    }

    notifyListeners();
  }

  Future<void> _disposeRenderer(String participantId) async {
    final renderer = _remoteRenderers.remove(participantId);
    await renderer?.dispose();
  }

  // Getters
  int get participantCount => _callService.participantCount;
  bool get isMultiParty => participantCount > 1;
  bool get isLocalInPip => _isLocalInPip;
  String? get fullscreenParticipantId => _fullscreenParticipantId;
  CallState get callState => _callService.callState;
  CallType get callType => _callService.callType;
  bool get isVideoCall => _callType == CallType.video;
  CallType get _callType => _callService.callType;

  /// Get all remote renderers for bento grid
  Map<String, RTCVideoRenderer> get remoteRenderers =>
      Map.unmodifiable(_remoteRenderers);

  /// Get list of participant IDs
  List<String> get participantIds => _remoteRenderers.keys.toList();

  /// Check if can add more participants
  bool get canAddParticipant => participantCount < maxParticipants;

  /// Toggle between local and remote in PiP (for 1:1 calls)
  void togglePipView() {
    if (!isMultiParty && participantIds.isNotEmpty) {
      _isLocalInPip = !_isLocalInPip;
      if (_isLocalInPip) {
        _fullscreenParticipantId = participantIds.first;
        _pipParticipantId = null;
      } else {
        _fullscreenParticipantId = null;
        _pipParticipantId = participantIds.first;
      }
      notifyListeners();
    }
  }

  /// Set a participant to fullscreen (for multi-party)
  void setFullscreenParticipant(String participantId) {
    if (_remoteRenderers.containsKey(participantId)) {
      _fullscreenParticipantId = participantId;
      notifyListeners();
    }
  }

  /// Get renderer for a participant
  RTCVideoRenderer? getRendererForParticipant(String participantId) {
    return _remoteRenderers[participantId];
  }

  /// Add a new participant to the call
  Future<bool> addParticipant(String callId) async {
    if (!canAddParticipant) return false;
    return await _callService.addParticipant(callId);
  }

  /// Toggle audio
  void toggleAudio() {
    _callService.toggleAudio();
  }

  /// Toggle video
  void toggleVideo() {
    _callService.toggleVideo();
  }

  /// Switch camera
  Future<void> switchCamera() async {
    await _callService.switchCamera();
  }

  /// End the call
  Future<void> endCall() async {
    await _callService.endCall();
  }

  /// Check if audio is enabled
  bool get isAudioEnabled {
    final audioTrack = _callService.localStream?.getAudioTracks().firstOrNull;
    return audioTrack?.enabled ?? false;
  }

  /// Check if video is enabled
  bool get isVideoEnabled {
    final videoTrack = _callService.localStream?.getVideoTracks().firstOrNull;
    return videoTrack?.enabled ?? false;
  }

  @override
  void dispose() {
    _callService.removeListener(_onCallServiceUpdate);
    localRenderer.dispose();
    for (final renderer in _remoteRenderers.values) {
      renderer.dispose();
    }
    _remoteRenderers.clear();
    super.dispose();
  }
}
