import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/call_signal_model.dart';
import 'sound_service.dart';

/// Represents a single peer connection with a participant
class ParticipantConnection {
  final String participantId;
  RTCPeerConnection? peerConnection;
  MediaStream? remoteStream;
  MediaStream? localStream;
  bool isConnected = false;
  bool isAudioEnabled = true;
  bool isVideoEnabled = true;
  DateTime? connectedAt;

  ParticipantConnection({required this.participantId});

  Future<void> dispose() async {
    await peerConnection?.close();
    peerConnection = null;
    await remoteStream?.dispose();
    remoteStream = null;
    // Note: localStream is shared, disposed separately
  }
}

enum CallType { audio, video }

enum CallState { idle, ringing, connecting, connected, ended }

class CallService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  String? _myCallId;
  MediaStream? _localStream;
  CallType _callType = CallType.audio;
  CallState _callState = CallState.idle;

  // Multi-party support: map of participant ID to their connection
  final Map<String, ParticipantConnection> _participants = {};

  // Realtime subscription
  RealtimeChannel? _signalChannel;
  Timer? _heartbeatTimer;
  Timer? _connectionCheckTimer;

  // Callbacks
  Function(String participantId, MediaStream stream)? onRemoteStream;
  Function(String senderId, String senderName)? onIncomingCall;
  Function(String participantId)? onParticipantJoined;
  Function(String participantId)? onParticipantLeft;
  Function(CallState state)? onCallStateChanged;

  // ICE servers configuration
  static const Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ],
  };

  // Getters
  String? get myCallId => _myCallId;
  CallState get callState => _callState;
  CallType get callType => _callType;
  MediaStream? get localStream => _localStream;
  List<ParticipantConnection> get participants => _participants.values.toList();
  int get participantCount => _participants.length;
  bool get isInCall =>
      _callState == CallState.connected || _callState == CallState.connecting;

  /// Initialize the call service
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _myCallId = prefs.getString('call_id');

    if (_myCallId != null) {
      _subscribeToSignals();
      _startHeartbeat();
    }
  }

  /// Subscribe to incoming signals
  void _subscribeToSignals() {
    _signalChannel =
        _supabase
            .channel('signals:$_myCallId')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'signals',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'receiver_id',
                value: _myCallId!,
              ),
              callback: (payload) {
                _handleIncomingSignal(payload.newRecord);
              },
            )
            .subscribe();
  }

  /// Handle incoming signals
  Future<void> _handleIncomingSignal(Map<String, dynamic> data) async {
    try {
      final signal = CallSignal.fromJson(data);

      switch (signal.type) {
        case 'ping':
          // Bell notification - play sound on RECEIVER side
          await SoundService.playPing();
          onIncomingCall?.call(
            signal.senderId,
            signal.data['name'] ?? 'Unknown',
          );
          break;

        case 'offer':
          await _handleOffer(signal);
          break;

        case 'answer':
          await _handleAnswer(signal);
          break;

        case 'ice':
          await _handleIceCandidate(signal);
          break;

        case 'reject':
          await _handleReject(signal);
          break;

        case 'hangup':
          await _handleHangup(signal);
          break;
      }

      // Delete processed signal
      await _deleteSignal(signal.id);
    } catch (e) {
      debugPrint('Error handling signal: $e');
    }
  }

  /// Start a call to a participant
  Future<bool> startCall(String targetCallId, CallType type) async {
    if (_myCallId == null) return false;

    try {
      _callType = type;
      _updateCallState(CallState.ringing);

      // Send ping to alert receiver (they will hear the bell)
      await _sendSignal(targetCallId, 'ping', {
        'name': 'User', // TODO: Get actual display name
        'call_type': type == CallType.video ? 'video' : 'audio',
      });

      // Start outgoing ring locally
      await SoundService.startOutgoingRing();

      // Initialize local media
      await _initializeLocalStream(type == CallType.video);

      // Create peer connection
      await _createPeerConnection(targetCallId, isInitiator: true);

      return true;
    } catch (e) {
      debugPrint('Error starting call: $e');
      _updateCallState(CallState.ended);
      await SoundService.playError();
      return false;
    }
  }

  /// Accept an incoming call
  Future<bool> acceptCall(String callerId, CallType type) async {
    try {
      _callType = type;
      _updateCallState(CallState.connecting);

      await SoundService.stopRing();

      // Initialize local media
      await _initializeLocalStream(type == CallType.video);

      // Peer connection will be created when we receive the offer

      return true;
    } catch (e) {
      debugPrint('Error accepting call: $e');
      return false;
    }
  }

  /// Add a participant to an ongoing call
  Future<bool> addParticipant(String targetCallId) async {
    if (!isInCall || _myCallId == null) return false;

    try {
      // Send ping to new participant
      await _sendSignal(targetCallId, 'ping', {
        'name': 'User',
        'call_type': _callType == CallType.video ? 'video' : 'audio',
        'is_group_invite': true,
      });

      // Create peer connection for new participant
      await _createPeerConnection(targetCallId, isInitiator: true);

      onParticipantJoined?.call(targetCallId);
      notifyListeners();

      return true;
    } catch (e) {
      debugPrint('Error adding participant: $e');
      return false;
    }
  }

  /// Initialize local media stream
  Future<void> _initializeLocalStream(bool withVideo) async {
    if (_localStream != null) return;

    final constraints = {
      'audio': true,
      'video':
          withVideo
              ? {
                'facingMode': 'user',
                'width': {'ideal': 1280},
                'height': {'ideal': 720},
              }
              : false,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
  }

  /// Create a peer connection for a participant
  Future<void> _createPeerConnection(
    String participantId, {
    required bool isInitiator,
  }) async {
    final participant = ParticipantConnection(participantId: participantId);
    participant.localStream = _localStream;

    final pc = await createPeerConnection(_iceServers);
    participant.peerConnection = pc;

    // Add local tracks
    _localStream?.getTracks().forEach((track) {
      pc.addTrack(track, _localStream!);
    });

    // Handle remote stream
    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        participant.remoteStream = event.streams[0];
        onRemoteStream?.call(participantId, event.streams[0]);
        notifyListeners();
      }
    };

    // Handle ICE candidates
    pc.onIceCandidate = (RTCIceCandidate candidate) {
      _sendSignal(participantId, 'ice', {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    // Handle connection state
    pc.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('Connection state with $participantId: $state');

      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          participant.isConnected = true;
          participant.connectedAt = DateTime.now();
          if (_callState != CallState.connected) {
            _updateCallState(CallState.connected);
            SoundService.stopRing();
            SoundService.playConnected();
          }
          _startConnectionCheck();
          break;

        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _handleParticipantDisconnected(participantId);
          break;

        default:
          break;
      }
      notifyListeners();
    };

    _participants[participantId] = participant;

    // If initiator, create and send offer
    if (isInitiator) {
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      await _sendSignal(participantId, 'offer', {
        'sdp': offer.sdp,
        'type': offer.type,
      });
    }
  }

  /// Handle incoming offer
  Future<void> _handleOffer(CallSignal signal) async {
    _updateCallState(CallState.connecting);

    // Create peer connection if not exists
    if (!_participants.containsKey(signal.senderId)) {
      await _initializeLocalStream(_callType == CallType.video);
      await _createPeerConnection(signal.senderId, isInitiator: false);
    }

    final participant = _participants[signal.senderId];
    if (participant?.peerConnection == null) return;

    final pc = participant!.peerConnection!;

    // Set remote description
    final offer = RTCSessionDescription(
      signal.data['sdp'] as String,
      signal.data['type'] as String,
    );
    await pc.setRemoteDescription(offer);

    // Create and send answer
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);

    await _sendSignal(signal.senderId, 'answer', {
      'sdp': answer.sdp,
      'type': answer.type,
    });
  }

  /// Handle incoming answer
  Future<void> _handleAnswer(CallSignal signal) async {
    final participant = _participants[signal.senderId];
    if (participant?.peerConnection == null) return;

    final answer = RTCSessionDescription(
      signal.data['sdp'] as String,
      signal.data['type'] as String,
    );
    await participant!.peerConnection!.setRemoteDescription(answer);

    await SoundService.stopRing();
    _updateCallState(CallState.connecting);
  }

  /// Handle incoming ICE candidate
  Future<void> _handleIceCandidate(CallSignal signal) async {
    final participant = _participants[signal.senderId];
    if (participant?.peerConnection == null) return;

    final candidate = RTCIceCandidate(
      signal.data['candidate'] as String,
      signal.data['sdpMid'] as String?,
      signal.data['sdpMLineIndex'] as int?,
    );
    await participant!.peerConnection!.addCandidate(candidate);
  }

  /// Handle call rejection
  Future<void> _handleReject(CallSignal signal) async {
    await SoundService.stopRing();
    await SoundService.playError();

    await _removeParticipant(signal.senderId);

    if (_participants.isEmpty) {
      _updateCallState(CallState.ended);
    }
  }

  /// Handle hangup from participant
  Future<void> _handleHangup(CallSignal signal) async {
    await _removeParticipant(signal.senderId);
    onParticipantLeft?.call(signal.senderId);

    if (_participants.isEmpty) {
      await endCall();
    }
  }

  /// Handle participant disconnection
  Future<void> _handleParticipantDisconnected(String participantId) async {
    await _removeParticipant(participantId);
    onParticipantLeft?.call(participantId);

    if (_participants.isEmpty) {
      await endCall();
    }
  }

  /// Remove a participant
  Future<void> _removeParticipant(String participantId) async {
    final participant = _participants.remove(participantId);
    await participant?.dispose();
    notifyListeners();
  }

  /// End the entire call
  Future<void> endCall() async {
    _updateCallState(CallState.ended);

    // Notify all participants
    for (final participantId in _participants.keys.toList()) {
      await _sendSignal(participantId, 'hangup', {});
    }

    // Clean up
    await _cleanup();

    await SoundService.stopRing();
    await SoundService.playEnded();
  }

  /// Reject an incoming call
  Future<void> rejectCall(String callerId) async {
    await _sendSignal(callerId, 'reject', {});
    await SoundService.stopRing();
    await SoundService.playError();
    _updateCallState(CallState.idle);
  }

  /// Toggle audio
  void toggleAudio() {
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = !track.enabled;
    });
    notifyListeners();
  }

  /// Toggle video
  void toggleVideo() {
    _localStream?.getVideoTracks().forEach((track) {
      track.enabled = !track.enabled;
    });
    notifyListeners();
  }

  /// Switch camera
  Future<void> switchCamera() async {
    final videoTrack = _localStream?.getVideoTracks().firstOrNull;
    if (videoTrack != null) {
      await Helper.switchCamera(videoTrack);
    }
  }

  /// Send signal to a participant
  Future<void> _sendSignal(
    String receiverId,
    String type,
    Map<String, dynamic> data,
  ) async {
    try {
      await _supabase.from('signals').insert({
        'sender_id': _myCallId,
        'receiver_id': receiverId,
        'type': type,
        'data': data,
      });
    } catch (e) {
      debugPrint('Error sending signal: $e');
    }
  }

  /// Delete a processed signal
  Future<void> _deleteSignal(String signalId) async {
    try {
      await _supabase.from('signals').delete().eq('id', signalId);
    } catch (e) {
      debugPrint('Error deleting signal: $e');
    }
  }

  /// Start heartbeat to keep connection alive
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      // Refresh presence
      notifyListeners();
    });
  }

  /// Start connection health check
  void _startConnectionCheck() {
    _connectionCheckTimer?.cancel();
    _connectionCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkConnectionHealth();
    });
  }

  /// Check connection health and clean up stale connections
  void _checkConnectionHealth() {
    final now = DateTime.now();
    final staleParticipants = <String>[];

    for (final entry in _participants.entries) {
      final participant = entry.value;

      // Check if connection is stale (no activity for 30 seconds)
      if (participant.connectedAt != null &&
          now.difference(participant.connectedAt!).inSeconds > 60 &&
          !participant.isConnected) {
        staleParticipants.add(entry.key);
      }
    }

    for (final id in staleParticipants) {
      _handleParticipantDisconnected(id);
    }
  }

  /// Update call state
  void _updateCallState(CallState state) {
    _callState = state;
    onCallStateChanged?.call(state);
    notifyListeners();
  }

  /// Clean up all resources
  Future<void> _cleanup() async {
    _heartbeatTimer?.cancel();
    _connectionCheckTimer?.cancel();

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
    await _signalChannel?.unsubscribe();
    await _cleanup();
    super.dispose();
  }
}
