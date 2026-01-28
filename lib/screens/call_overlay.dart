import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/call_service.dart';
import '../services/sound_service.dart';

class CallOverlay extends StatefulWidget {
  final CallService callService;
  final bool isVideoCall;
  final String remoteDisplayName;
  final bool answeredFromBackground;

  const CallOverlay({
    super.key,
    required this.callService,
    this.isVideoCall = true,
    required this.remoteDisplayName,
    this.answeredFromBackground = false,
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
  bool _controlsVisible = true;
  bool _isSwapped = false; // For PiP swap functionality

  // PiP position (draggable)
  double _pipX = 20;
  double _pipY = 60;

  late AnimationController _pulseController;
  late AnimationController _controlsFadeController;

  @override
  void initState() {
    super.initState();
    _initRenderers();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _controlsFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1.0,
    );
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    if (widget.callService.localStream != null) {
      _localRenderer.srcObject = widget.callService.localStream;
    }

    if (widget.callService.participants.isNotEmpty &&
        widget.callService.participants.first.remoteStream != null) {
      _remoteRenderer.srcObject =
          widget.callService.participants.first.remoteStream;
    }

    widget.callService.addListener(_onServiceUpdate);
  }

  void _onServiceUpdate() {
    if (widget.callService.participants.isNotEmpty) {
      final remote = widget.callService.participants.first.remoteStream;
      if (remote != null && _remoteRenderer.srcObject != remote) {
        setState(() {
          _remoteRenderer.srcObject = remote;
        });
        SoundService.playConnected();
      }
    }

    // Handle call ended
    if (widget.callService.callState == CallState.ended ||
        widget.callService.callState == CallState.idle) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  void dispose() {
    widget.callService.removeListener(_onServiceUpdate);
    _pulseController.dispose();
    _controlsFadeController.dispose();
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
    setState(() => _isSpeakerOn = !_isSpeakerOn);
  }

  void _toggleCamera() {
    SoundService.playSwitch();
    widget.callService.toggleVideo();
    setState(() => _isCameraOff = !_isCameraOff);
  }

  void _switchCamera() {
    SoundService.playSwitch();
    widget.callService.switchCamera();
  }

  void _endCall() {
    SoundService.playEnded();
    widget.callService.endCall();
    Navigator.of(context).pop();
  }

  void _toggleControls() {
    setState(() {
      _controlsVisible = !_controlsVisible;
    });
    if (_controlsVisible) {
      _controlsFadeController.forward();
    } else {
      _controlsFadeController.reverse();
    }
  }

  void _swapViews() {
    setState(() => _isSwapped = !_isSwapped);
  }

  bool get _isConnected => _remoteRenderer.srcObject != null;
  String get _statusText {
    switch (widget.callService.callState) {
      case CallState.ringing:
        return 'Ringing...';
      case CallState.connecting:
        return 'Connecting...';
      case CallState.connected:
        return 'Connected';
      default:
        return 'Calling...';
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: widget.isVideoCall ? _toggleControls : null,
        child: Stack(
          children: [
            // === MAIN BACKGROUND ===
            Positioned.fill(
              child:
                  widget.isVideoCall
                      ? _buildVideoBackground()
                      : _buildAudioBackground(),
            ),

            // === PiP LOCAL VIDEO (Video calls only, when connected) ===
            if (widget.isVideoCall &&
                _localRenderer.srcObject != null &&
                _isConnected)
              _buildDraggablePiP(screenSize),

            // === CONTROLS (fade in/out) ===
            AnimatedBuilder(
              animation: _controlsFadeController,
              builder: (context, child) {
                return IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: Opacity(
                    opacity: _controlsFadeController.value,
                    child: child,
                  ),
                );
              },
              child: _buildControls(),
            ),

            // === HEADER ===
            _buildHeader(),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoBackground() {
    // Determine which renderer to show full screen
    RTCVideoRenderer mainRenderer;

    if (_isSwapped) {
      // Swapped: Local is main, remote is PiP
      mainRenderer =
          _localRenderer.srcObject != null ? _localRenderer : _remoteRenderer;
    } else {
      // Normal: Remote is main (when connected), local when calling
      if (_isConnected) {
        mainRenderer = _remoteRenderer;
      } else {
        mainRenderer = _localRenderer;
      }
    }

    if (mainRenderer.srcObject == null) {
      return Container(color: Colors.black);
    }

    return RTCVideoView(
      mainRenderer,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      mirror: mainRenderer == _localRenderer,
    );
  }

  Widget _buildAudioBackground() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Blurred avatar background
        Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: NetworkImage(
                'https://ui-avatars.com/api/?name=${widget.remoteDisplayName}&background=1C1C1E&color=fff&size=512',
              ),
              fit: BoxFit.cover,
            ),
          ),
        ),
        // Heavy blur + dark overlay
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
          child: Container(color: Colors.black.withValues(alpha: 0.6)),
        ),
        // Centered caller info
        Center(
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
                          color: const Color(0xFF128C7E).withValues(
                            alpha: 0.3 + (_pulseController.value * 0.2),
                          ),
                          blurRadius: 40 + (_pulseController.value * 20),
                          spreadRadius: 5 + (_pulseController.value * 10),
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
                _statusText,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDraggablePiP(Size screenSize) {
    RTCVideoRenderer pipRenderer =
        _isSwapped ? _remoteRenderer : _localRenderer;

    return Positioned(
      right: _pipX,
      top: _pipY,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _pipX -= details.delta.dx;
            _pipY += details.delta.dy;
            // Keep within bounds
            _pipX = _pipX.clamp(0, screenSize.width - 120);
            _pipY = _pipY.clamp(50, screenSize.height - 200);
          });
        },
        onTap: _swapViews,
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
            child:
                pipRenderer.srcObject != null
                    ? RTCVideoView(
                      pipRenderer,
                      mirror: pipRenderer == _localRenderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                    : Container(color: Colors.grey.shade800),
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Positioned(
      bottom: 60,
      left: 0,
      right: 0,
      child: Column(
        children: [
          // Secondary Controls Row
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
              if (widget.isVideoCall) ...[
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
                  icon: CupertinoIcons.switch_camera,
                  label: 'Flip',
                  isActive: true,
                  onTap: _switchCamera,
                ),
                const SizedBox(width: 24),
              ],
              _buildSecondaryButton(
                icon: _isMicMuted ? CupertinoIcons.mic_off : CupertinoIcons.mic,
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
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withValues(alpha: 0.5),
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
    );
  }

  Widget _buildHeader() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(
                  CupertinoIcons.chevron_back,
                  color: Colors.white,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
              if (widget.isVideoCall && _isConnected)
                Text(
                  'Tap to ${_controlsVisible ? 'hide' : 'show'} controls',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              const SizedBox(width: 48), // Balance the back button
            ],
          ),
        ),
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
