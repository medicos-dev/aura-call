import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/call_service.dart'; // Use CallService
import '../services/sound_service.dart';

class CallOverlay extends StatefulWidget {
  final CallService callService; // Changed from WebRTCController
  final bool isVideoCall;
  final String remoteDisplayName;

  const CallOverlay({
    super.key,
    required this.callService,
    this.isVideoCall = true,
    required this.remoteDisplayName,
  });

  @override
  State<CallOverlay> createState() => _CallOverlayState();
}

class _CallOverlayState extends State<CallOverlay>
    with TickerProviderStateMixin {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _isMicMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = true;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    // Hook into CallService streams
    if (widget.callService.localStream != null) {
      _localRenderer.srcObject = widget.callService.localStream;
    }

    // Listen for remote stream callbacks from Service if using listener pattern or check existing participants
    if (widget.callService.participants.isNotEmpty &&
        widget.callService.participants.first.remoteStream != null) {
      _remoteRenderer.srcObject =
          widget.callService.participants.first.remoteStream;
    }

    // Set up listeners for stream changes (CallService should have a stream listener/callback or notifyListeners)
    widget.callService.addListener(_onServiceUpdate);
  }

  void _onServiceUpdate() {
    // Check for new streams
    if (widget.callService.participants.isNotEmpty) {
      final remote = widget.callService.participants.first.remoteStream;
      if (remote != null && _remoteRenderer.srcObject != remote) {
        setState(() {
          _remoteRenderer.srcObject = remote;
        });
        SoundService.playConnected();
      }
    }
  }

  @override
  void dispose() {
    widget.callService.removeListener(_onServiceUpdate);
    _pulseController.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  void _toggleMic() {
    SoundService.playSwitch();
    widget.callService.toggleAudio();
    setState(() => _isMicMuted = !_isMicMuted);
  }

  void _toggleSpeaker() {
    SoundService.playSwitch();
    // Helper.setSpeakerphoneOn is needed here, assuming CallService or helper has it.
    // Usually flutter_webrtc helper.
    // For now just toggle state UI
    setState(() => _isSpeakerOn = !_isSpeakerOn);
  }

  void _toggleCamera() {
    SoundService.playSwitch();
    widget.callService.toggleVideo();
    setState(() => _isCameraOff = !_isCameraOff);
  }

  void _endCall() {
    SoundService.playEnded();
    widget.callService.endCall();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background
          Positioned.fill(
            child:
                widget.isVideoCall && _remoteRenderer.srcObject != null
                    ? RTCVideoView(
                      _remoteRenderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                    : Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF1C1C1E), Color(0xFF0A0A0A)],
                        ),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Pulsing Avatar
                            AnimatedBuilder(
                              animation: _pulseController,
                              builder: (context, child) {
                                return Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF128C7E,
                                        ).withValues(
                                          alpha:
                                              0.3 +
                                              (_pulseController.value * 0.2),
                                        ),
                                        blurRadius:
                                            40 + (_pulseController.value * 20),
                                        spreadRadius:
                                            5 + (_pulseController.value * 10),
                                      ),
                                    ],
                                  ),
                                  child: CircleAvatar(
                                    radius: 70,
                                    backgroundImage: NetworkImage(
                                      'https://ui-avatars.com/api/?name=${widget.remoteDisplayName}&background=128C7E&color=fff&size=256',
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 32),
                            Text(
                              widget.remoteDisplayName,
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _remoteRenderer.srcObject != null
                                  ? 'Connected'
                                  : 'Calling...',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
          ),

          // Floating PiP - Local Video
          if (widget.isVideoCall && _localRenderer.srcObject != null)
            Positioned(
              right: 20,
              top: 60,
              child: Container(
                width: 100,
                height: 140,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: RTCVideoView(
                    _localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),
            ),

          // Controls
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Column(
              children: [
                // Secondary Controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildSecondaryButton(
                      icon:
                          _isSpeakerOn
                              ? CupertinoIcons.speaker_3_fill
                              : CupertinoIcons.speaker_slash_fill,
                      label: 'Speaker',
                      isActive: _isSpeakerOn,
                      onTap: _toggleSpeaker,
                    ),
                    const SizedBox(width: 24),
                    _buildSecondaryButton(
                      icon:
                          _isCameraOff
                              ? CupertinoIcons.video_camera_solid
                              : CupertinoIcons.video_camera_solid,
                      label: 'Camera',
                      isActive: !_isCameraOff,
                      onTap: _toggleCamera,
                    ),
                    const SizedBox(width: 24),
                    _buildSecondaryButton(
                      icon:
                          _isMicMuted
                              ? CupertinoIcons.mic_off
                              : CupertinoIcons.mic,
                      label: 'Mute',
                      isActive: !_isMicMuted,
                      onTap: _toggleMic,
                    ),
                  ],
                ),
                const SizedBox(height: 40),
                // End Call Button
                GestureDetector(
                  onTap: _endCall,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red,
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      CupertinoIcons.phone_down,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Header / Back Button
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        CupertinoIcons.chevron_back,
                        color: Colors.white,
                      ),
                      onPressed: _endCall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecondaryButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color:
                  isActive ? Colors.white.withValues(alpha: 0.2) : Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isActive ? Colors.white : Colors.black,
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
