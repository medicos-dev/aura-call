import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../app_theme.dart';
import '../services/call_service.dart';
import '../services/multi_call_controller.dart';
import 'add_person_sheet.dart';

class CallOverlay extends StatefulWidget {
  final CallService callService;

  const CallOverlay({super.key, required this.callService});

  @override
  State<CallOverlay> createState() => _CallOverlayState();
}

class _CallOverlayState extends State<CallOverlay>
    with TickerProviderStateMixin {
  late MultiCallController _multiCallController;
  bool _controlsVisible = true;
  late AnimationController _controlsAnimController;

  // PiP drag position
  Offset _pipPosition = const Offset(16, 100);

  @override
  void initState() {
    super.initState();
    _multiCallController = MultiCallController(widget.callService);
    _multiCallController.addListener(_onControllerUpdate);

    _controlsAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();

    // Auto-hide controls after 5 seconds
    _startControlsTimer();
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});

    // Check if call ended
    if (_multiCallController.callState == CallState.ended) {
      Navigator.of(context).pop();
    }
  }

  void _startControlsTimer() {
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _controlsVisible) {
        _hideControls();
      }
    });
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideControls();
    } else {
      _showControls();
    }
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _controlsAnimController.forward();
    _startControlsTimer();
  }

  void _hideControls() {
    _controlsAnimController.reverse().then((_) {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _showAddPersonSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => AddPersonSheet(
            onAdd: (callId) async {
              Navigator.of(context).pop();
              await _multiCallController.addParticipant(callId);
            },
          ),
    );
  }

  @override
  void dispose() {
    _multiCallController.removeListener(_onControllerUpdate);
    _multiCallController.dispose();
    _controlsAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: [
            // Background
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF1A1030), AppTheme.backgroundDark],
                ),
              ),
            ),

            // Main video content
            _buildVideoContent(),

            // Controls overlay
            if (_controlsVisible) ...[
              // Top bar
              _buildTopBar(),

              // Bottom controls
              _buildBottomControls(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVideoContent() {
    final participantCount = _multiCallController.participantCount;

    if (participantCount == 0) {
      // Waiting for connection
      return _buildConnectingView();
    } else if (participantCount == 1) {
      // 1:1 call - WhatsApp style
      return _buildOneToOneLayout();
    } else {
      // Multi-party - Bento grid
      return _buildBentoGridLayout();
    }
  }

  Widget _buildConnectingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryPurple.withOpacity(0.5),
                  blurRadius: 30,
                ),
              ],
            ),
            child: const Icon(Icons.person, size: 50, color: Colors.white),
          ),
          const SizedBox(height: 24),
          const Text(
            'Connecting...',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.primaryCyan,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOneToOneLayout() {
    final remoteParticipantId = _multiCallController.participantIds.first;
    final remoteRenderer = _multiCallController.getRendererForParticipant(
      remoteParticipantId,
    );
    final localRenderer = _multiCallController.localRenderer;
    final isLocalInPip = _multiCallController.isLocalInPip;

    return Stack(
      children: [
        // Fullscreen view
        Positioned.fill(
          child: GestureDetector(
            onDoubleTap: _multiCallController.togglePipView,
            child: _buildVideoTile(
              renderer: isLocalInPip ? remoteRenderer : localRenderer,
              participantId: isLocalInPip ? remoteParticipantId : null,
              colorIndex: 0,
              isFullscreen: true,
            ),
          ),
        ),

        // PiP view (draggable)
        Positioned(
          left: _pipPosition.dx,
          top: _pipPosition.dy + MediaQuery.of(context).padding.top,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _pipPosition += details.delta;
                // Clamp to screen bounds
                final size = MediaQuery.of(context).size;
                _pipPosition = Offset(
                  _pipPosition.dx.clamp(0, size.width - 120),
                  _pipPosition.dy.clamp(0, size.height - 200),
                );
              });
            },
            onDoubleTap: _multiCallController.togglePipView,
            child: Container(
              width: 110,
              height: 160,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.getParticipantColor(isLocalInPip ? 1 : 0),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _buildVideoTile(
                  renderer: isLocalInPip ? localRenderer : remoteRenderer,
                  participantId: isLocalInPip ? null : remoteParticipantId,
                  colorIndex: isLocalInPip ? 1 : 0,
                  showLabel: false,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBentoGridLayout() {
    final participantIds = _multiCallController.participantIds;
    // Include local in the grid
    final allParticipants = ['local', ...participantIds];
    final count = allParticipants.length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: _buildGridForCount(allParticipants, count),
      ),
    );
  }

  Widget _buildGridForCount(List<String> participants, int count) {
    switch (count) {
      case 2:
        return Column(
          children: [
            Expanded(child: _buildParticipantTile(participants[0], 0)),
            const SizedBox(height: 8),
            Expanded(child: _buildParticipantTile(participants[1], 1)),
          ],
        );
      case 3:
        return Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildParticipantTile(participants[0], 0)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildParticipantTile(participants[1], 1)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildParticipantTile(participants[2], 2)),
          ],
        );
      case 4:
        return Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildParticipantTile(participants[0], 0)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildParticipantTile(participants[1], 1)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildParticipantTile(participants[2], 2)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildParticipantTile(participants[3], 3)),
                ],
              ),
            ),
          ],
        );
      case 5:
        return Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildParticipantTile(participants[0], 0)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildParticipantTile(participants[1], 1)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildParticipantTile(participants[2], 2)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildParticipantTile(participants[3], 3)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildParticipantTile(participants[4], 4)),
                ],
              ),
            ),
          ],
        );
      case 6:
      default:
        return Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildParticipantTile(participants[0], 0)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildParticipantTile(participants[1], 1)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildParticipantTile(participants[2], 2)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                children: [
                  for (int i = 3; i < participants.length && i < 6; i++) ...[
                    if (i > 3) const SizedBox(width: 8),
                    Expanded(child: _buildParticipantTile(participants[i], i)),
                  ],
                ],
              ),
            ),
          ],
        );
    }
  }

  Widget _buildParticipantTile(String participantId, int colorIndex) {
    final isLocal = participantId == 'local';
    final renderer =
        isLocal
            ? _multiCallController.localRenderer
            : _multiCallController.getRendererForParticipant(participantId);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.getParticipantColor(colorIndex),
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.getParticipantColor(colorIndex).withOpacity(0.3),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: _buildVideoTile(
          renderer: renderer,
          participantId: isLocal ? null : participantId,
          colorIndex: colorIndex,
          showLabel: true,
          label: isLocal ? 'You' : participantId,
        ),
      ),
    );
  }

  Widget _buildVideoTile({
    RTCVideoRenderer? renderer,
    String? participantId,
    required int colorIndex,
    bool isFullscreen = false,
    bool showLabel = true,
    String? label,
  }) {
    final isVideoCall = _multiCallController.isVideoCall;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Video or avatar background
        if (isVideoCall && renderer != null && renderer.srcObject != null)
          RTCVideoView(
            renderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            mirror: participantId == null, // Mirror local video
          )
        else
          Container(
            color: AppTheme.backgroundElevated,
            child: Center(
              child: Container(
                width: isFullscreen ? 120 : 60,
                height: isFullscreen ? 120 : 60,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.getParticipantColor(colorIndex),
                      AppTheme.getParticipantColor(colorIndex + 1),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person,
                  size: isFullscreen ? 60 : 30,
                  color: Colors.white,
                ),
              ),
            ),
          ),

        // Label overlay
        if (showLabel && label != null)
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isFullscreen ? 14 : 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: FadeTransition(
        opacity: _controlsAnimController,
        child: Container(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            bottom: 16,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withOpacity(0.6), Colors.transparent],
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Back button
              _buildTopButton(
                icon: Icons.arrow_back,
                onTap: () => Navigator.of(context).pop(),
              ),

              // Call duration placeholder
              const Text(
                '00:00',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),

              // Add person button
              if (_multiCallController.canAddParticipant)
                _buildTopButton(
                  icon: Icons.person_add,
                  onTap: _showAddPersonSheet,
                )
              else
                const SizedBox(width: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildBottomControls() {
    final isAudioEnabled = _multiCallController.isAudioEnabled;
    final isVideoEnabled = _multiCallController.isVideoEnabled;
    final isVideoCall = _multiCallController.isVideoCall;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: FadeTransition(
        opacity: _controlsAnimController,
        child: Container(
          padding: EdgeInsets.only(
            top: 24,
            left: 24,
            right: 24,
            bottom: MediaQuery.of(context).padding.bottom + 24,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black.withOpacity(0.8), Colors.transparent],
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Mute button
              _buildControlButton(
                icon: isAudioEnabled ? Icons.mic : Icons.mic_off,
                label: isAudioEnabled ? 'Mute' : 'Unmute',
                isActive: !isAudioEnabled,
                onTap: _multiCallController.toggleAudio,
              ),

              // Video toggle (only for video calls)
              if (isVideoCall)
                _buildControlButton(
                  icon: isVideoEnabled ? Icons.videocam : Icons.videocam_off,
                  label: isVideoEnabled ? 'Video' : 'Video Off',
                  isActive: !isVideoEnabled,
                  onTap: _multiCallController.toggleVideo,
                ),

              // End call button
              _buildEndCallButton(),

              // Camera switch (only for video calls)
              if (isVideoCall)
                _buildControlButton(
                  icon: Icons.cameraswitch,
                  label: 'Switch',
                  onTap: _multiCallController.switchCamera,
                ),

              // Add person (if room)
              if (_multiCallController.canAddParticipant)
                _buildControlButton(
                  icon: Icons.person_add,
                  label: 'Add',
                  onTap: _showAddPersonSheet,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    bool isActive = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isActive ? Colors.white : Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isActive ? AppTheme.backgroundDark : Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEndCallButton() {
    return GestureDetector(
      onTap: () async {
        await _multiCallController.endCall();
        if (mounted) Navigator.of(context).pop();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.error, Color(0xFFDC2626)],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.error.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.call_end, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            'End',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
