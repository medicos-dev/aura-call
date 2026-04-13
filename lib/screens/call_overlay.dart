import 'dart:ui';
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:proximity_sensor/proximity_sensor.dart';
import '../services/call_service.dart';
import '../services/sound_service.dart';
import '../widgets/app_toast.dart';
import 'home_screen.dart';

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
  bool _isSpeakerOn = false; // Tracks speaker vs earpiece
  bool _controlsVisible = true;
  bool _isSwapped = false; // For PiP swap functionality
  bool _isInitialized = false; 
  bool _isNearEar = false;
  bool _isEndingCall = false; // Guard against double navigation
  bool _isRequestingVideo = false; // WhatsApp-style video switch pending
  bool _isFrontCamera = true; // Track camera direction for mirroring
  StreamSubscription<dynamic>? _proximitySubscription;
  String? _remoteAvatarUrl;

  String _bgOption = 'assets/call_background.png';

  // PiP position (draggable)
  double _pipX = 20;
  double _pipY = 60;

  DateTime? _connectedStartTime;
  Timer? _timer;
  String _timeString = '00:00';

  late AnimationController _pulseController;
  late AnimationController _controlsFadeController;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Audio call: earpiece + proximity. Video call: speaker, no proximity.
    _isSpeakerOn = widget.isVideoCall;
    _isCameraOff = !widget.isVideoCall; // Audio call starts with camera off

    if (!widget.isVideoCall) {
      _startProximity();
    }

    // Set initial audio route
    Helper.setSpeakerphoneOn(_isSpeakerOn);

    _loadBackground();
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

  void _startProximity() async {
    _proximitySubscription?.cancel();
    try {
      await ProximitySensor.setProximityScreenOff(true);
    } catch (e) {
      // Ignore
    }
    _proximitySubscription = ProximitySensor.events.listen((int event) {
      if (!mounted) return;
      setState(() {
        _isNearEar = (event > 0);
      });
    });
  }

  void _stopProximity() async {
    _proximitySubscription?.cancel();
    _proximitySubscription = null;
    try {
      await ProximitySensor.setProximityScreenOff(false);
    } catch (e) {
      // Ignore
    }
    if (mounted) {
      setState(() => _isNearEar = false);
    }
  }

  Future<void> _loadBackground() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _bgOption = prefs.getString('call_background') ?? 'assets/call_background_1.png';
      // For remote dummy, use a different default seed or if they are in contacts, use that.
      _remoteAvatarUrl = 'https://api.dicebear.com/7.x/adventurer/png?seed=${widget.remoteDisplayName}';
    });
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

    if (mounted) {
      setState(() => _isInitialized = true);
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _connectedStartTime ??= DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      final diff = DateTime.now().difference(_connectedStartTime!);
      final minutes = diff.inMinutes.remainder(60).toString().padLeft(2, '0');
      final seconds = diff.inSeconds.remainder(60).toString().padLeft(2, '0');
      setState(() {
        if (diff.inHours > 0) {
          final hours = diff.inHours.toString().padLeft(2, '0');
          _timeString = '$hours:$minutes:$seconds';
        } else {
          _timeString = '$minutes:$seconds';
        }
      });
    });
  }

  void _onServiceUpdate() {
    if (widget.callService.participants.isNotEmpty) {
      final remote = widget.callService.participants.first.remoteStream;
      if (remote != null && _remoteRenderer.srcObject != remote) {
        setState(() {
          _remoteRenderer.srcObject = remote;
        });
      }
    }

    if (widget.callService.callState == CallState.connected && _connectedStartTime == null) {
      _startTimer();
    }

    // Handle call ended — do NOT navigate here; _endCall handles it.
    // This prevents double-navigation race conditions that cause crashes.
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    try {
      ProximitySensor.setProximityScreenOff(false);
    } catch (e) {
      debugPrint('Screen off disabled failed: $e');
    }
    _proximitySubscription?.cancel();
    _timer?.cancel();
    widget.callService.removeListener(_onServiceUpdate);
    _pulseController.dispose();
    _controlsFadeController.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  void _toggleMic() {
    widget.callService.toggleAudio();
    setState(() => _isMicMuted = !_isMicMuted);
  }

  void _toggleVideo() {
    if (_isCameraOff) {
      // Currently audio mode → request video switch (WhatsApp style)
      if (_isRequestingVideo) return; // Already requesting
      _requestVideoSwitch();
    } else {
      // Currently video mode → turn off camera instantly (back to audio)
      widget.callService.toggleVideo();
      setState(() => _isCameraOff = true);
      // Keep speaker as-is, don't restart proximity
    }
  }

  void _requestVideoSwitch() async {
    setState(() => _isRequestingVideo = true);
    AppToast.show(context, 'Requesting video switch...', type: AppToastType.info);

    // Play repeating ring sound to simulate request to remote
    await SoundService.startOutgoingRing();

    // Simulate remote user's response after 3 seconds (dummy mode)
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted || _isEndingCall) return;

    await SoundService.stopRing();

    // In a real app, we'd wait for remote signaling. 
    // Here we simulate the remote user accepting our request:
    _acceptVideoSwitch();
  }

  void _acceptVideoSwitch() {
    widget.callService.toggleVideo();
    setState(() {
      _isCameraOff = false;
      _isRequestingVideo = false;
    });
    // Force speaker, kill proximity
    _isSpeakerOn = true;
    Helper.setSpeakerphoneOn(true);
    _stopProximity();
    AppToast.show(context, 'Switched to video call', type: AppToastType.success);
  }

  void _toggleSpeaker() {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    Helper.setSpeakerphoneOn(_isSpeakerOn);

    if (!_isSpeakerOn && _isCameraOff) {
      // Switched to earpiece during audio-mode: enable proximity
      _startProximity();
    } else {
      // On speaker: disable proximity
      _stopProximity();
    }
  }

  void _endCall() {
    if (_isEndingCall) return; // Prevent double-tap
    _isEndingCall = true;
    SoundService.playEnded();
    widget.callService.endCall();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        CupertinoPageRoute(builder: (_) => const HomeScreen()), 
        (route) => false
      );
    }
  }

  void _acceptCall() async {
    await widget.callService.acceptCall(
      widget.callService.participants.isNotEmpty 
          ? widget.callService.participants.first.participantId 
          : 'Unknown', 
      widget.isVideoCall ? CallType.video : CallType.audio
    );
  }

  void _toggleControls() {
    if (!_isConnected) return; // Don't toggle in incoming state
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

  bool get _isConnected => widget.callService.callState == CallState.connected;
  bool get _isRinging => widget.callService.callState == CallState.ringing;

  Widget _buildBackgroundContext() {
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage(_bgOption),
          fit: BoxFit.cover,
        )
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(backgroundColor: Colors.black, body: _buildLoadingView());
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: [
            // 1. Fullscreen Background Layer
            Positioned.fill(
              child: _isConnected && widget.isVideoCall && !_isCameraOff 
                ? _buildVideoBackground() 
                : _buildBackgroundContext(),
            ),

            // 2. Translucent dark overlay for contrast
            Positioned.fill(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: _isConnected && _controlsVisible ? 0.4 : 0.2,
                child: Container(color: Colors.black),
              )
            ),

            // 3. Avatar Layer (If Audio Call or Camera Off)
            if ((!_isConnected || !widget.isVideoCall || _isCameraOff) && _controlsVisible)
              _buildAvatarCenter(),

            // 4. Secondary Background PIP (Video only)
            if (_isConnected && widget.isVideoCall)
              _buildDraggablePiP(MediaQuery.of(context).size),

            // 5. Apple Style Incoming Overlays
            if (_isRinging)
               _buildIncomingAppleStyle(),

            // 6. WhatsApp Style Connected Overlays
            if (_isConnected)
               _buildConnectedWhatsAppStyle(),
               
            // 7. Proximity Sensor Blackout Overlay
            if (_isNearEar)
              Positioned.fill(
                child: Container(
                  color: Colors.black,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarCenter() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(
                        alpha: 0.1 + (_pulseController.value * 0.1),
                      ),
                      blurRadius: 30 + (_pulseController.value * 20),
                      spreadRadius: 2 + (_pulseController.value * 5),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 70,
                  backgroundColor: Colors.grey.shade900,
                  backgroundImage: NetworkImage(_remoteAvatarUrl ?? ''),
                ),
              );
            },
          ),
          if (!_isConnected) ...[
            const SizedBox(height: 32),
            Text(
              widget.remoteDisplayName,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w400, // Apple-esque lighter font
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'AURA ${widget.isVideoCall ? "Video" : "Audio"}...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildIncomingAppleStyle() {
    return Positioned(
      bottom: 80,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Decline Button (Red, Left)
          GestureDetector(
            onTap: _endCall,
            child: Column(
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF3B30),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(CupertinoIcons.phone_down_fill, color: Colors.white, size: 36),
                ),
                const SizedBox(height: 12),
                const Text('Decline', style: TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
          ),
          
          // Accept Button (Green, Right)
          GestureDetector(
            onTap: _acceptCall,
            child: Column(
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: const Color(0xFF34C759),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF34C759).withValues(alpha: 0.4),
                        blurRadius: 15,
                        spreadRadius: 4,
                      )
                    ]
                  ),
                  child: const Icon(CupertinoIcons.phone_fill, color: Colors.white, size: 36),
                ),
                const SizedBox(height: 12),
                const Text('Accept', style: TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedWhatsAppStyle() {
    return AnimatedBuilder(
      animation: _controlsFadeController,
      builder: (context, child) {
        return IgnorePointer(
          ignoring: !_controlsVisible,
          child: Opacity(
            opacity: _controlsFadeController.value,
            child: Stack(
              children: [
                // Top Bar
                Positioned(
                  top: 0, left: 0, right: 0,
                  child: Container(
                    padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 10, bottom: 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent],
                      )
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(CupertinoIcons.chevron_down, color: Colors.white, size: 30),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        Column(
                          children: [
                            Text(
                              widget.remoteDisplayName,
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _timeString, 
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14)
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(CupertinoIcons.person_add_solid, color: Colors.white, size: 26),
                          onPressed: _showAddParticipantSheet,
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom Island (Glassmorphism)
                Positioned(
                  bottom: 60,
                  left: 20,
                  right: 20,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(40),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(40),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.5),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Video toggle (always visible)
                            _buildIslandButton(
                              icon: _isRequestingVideo 
                                ? CupertinoIcons.video_camera 
                                : (_isCameraOff ? CupertinoIcons.video_camera : CupertinoIcons.video_camera_solid),
                              isActive: _isRequestingVideo ? false : !_isCameraOff,
                              onTap: _isRequestingVideo ? null : _toggleVideo,
                            ),
                            // Mic toggle (always visible)
                            _buildIslandButton(
                              icon: _isMicMuted ? CupertinoIcons.mic_off : CupertinoIcons.mic_solid,
                              isActive: !_isMicMuted,
                              onTap: _toggleMic,
                            ),
                            // Speaker toggle: only in audio mode (camera off)
                            if (_isCameraOff)
                              _buildIslandButton(
                                icon: _isSpeakerOn ? CupertinoIcons.speaker_3_fill : CupertinoIcons.speaker_1_fill,
                                isActive: _isSpeakerOn,
                                onTap: _toggleSpeaker,
                              ),
                            // Camera switch: only when camera is on
                            if (!_isCameraOff)
                              _buildIslandButton(
                                 icon: CupertinoIcons.switch_camera_solid,
                                 isActive: true,
                                 onTap: () {
                                   widget.callService.switchCamera();
                                   setState(() => _isFrontCamera = !_isFrontCamera);
                                 },
                              ),
                            GestureDetector(
                              onTap: _endCall,
                              child: Container(
                                width: 56,
                                height: 56,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFF3B30),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(CupertinoIcons.phone_down_fill, color: Colors.white, size: 28),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildIslandButton({required IconData icon, required bool isActive, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1.0,
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: isActive ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: isActive ? Colors.white : Colors.white54, size: 28),
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return const Center(child: CupertinoActivityIndicator(radius: 20));
  }

  Widget _buildVideoBackground() {
    RTCVideoRenderer mainRenderer = _isSwapped ? _localRenderer : _remoteRenderer;

    if (mainRenderer.srcObject == null) {
      if (_localRenderer.srcObject != null) {
        mainRenderer = _localRenderer; // Fallback to local if remote isn't ready
      } else {
        return _buildLoadingView();
      }
    }

    return RTCVideoView(
      mainRenderer,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      mirror: mainRenderer == _localRenderer && _isFrontCamera,
    );
  }

  Widget _buildDraggablePiP(Size screenSize) {
    if (_isCameraOff) return const SizedBox(); // Hide PiP if camera is off
    
    RTCVideoRenderer pipRenderer = _isSwapped ? _remoteRenderer : _localRenderer;

    if (pipRenderer.srcObject == null) return const SizedBox();

    return Positioned(
      right: _pipX,
      top: _pipY,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _pipX -= details.delta.dx;
            _pipY += details.delta.dy;
            _pipX = _pipX.clamp(20, screenSize.width - 120);
            _pipY = _pipY.clamp(60, screenSize.height - 200);
          });
        },
        onPanEnd: (details) {
          // Snap magnetic
          final isTop = _pipY < screenSize.height / 2;
          final isLeft = _pipX > screenSize.width / 2; // X corresponds to Right

          setState(() {
            _pipY = isTop ? 60.0 : screenSize.height - 200.0;
            _pipX = isLeft ? screenSize.width - 120.0 : 20.0;
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
                blurRadius: 10,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: RTCVideoView(
              pipRenderer,
              mirror: pipRenderer == _localRenderer && _isFrontCamera,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),
        ),
      ),
    );
  }

  void _showAddParticipantSheet() async {
    final prefs = await SharedPreferences.getInstance();
    final contacts = prefs.getStringList('contacts') ?? [];
    
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SafeArea(
              bottom: true,
              child: Container(
                height: MediaQuery.of(context).size.height * 0.75,
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E).withValues(alpha: 0.95),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        Container(
                          width: 44, 
                          height: 5, 
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.3), 
                            borderRadius: BorderRadius.circular(3)
                          )
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Add Participants', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                              GestureDetector(
                                onTap: () => Navigator.pop(sheetContext),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), shape: BoxShape.circle),
                                  child: const Icon(CupertinoIcons.xmark, color: Colors.white, size: 20),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Premium Search Bar
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                          child: Container(
                            height: 46,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                            ),
                            child: Row(
                              children: [
                                const SizedBox(width: 16),
                                Icon(CupertinoIcons.search, color: Colors.white.withValues(alpha: 0.5), size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text('Search contacts...', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 16)),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: contacts.isEmpty 
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(CupertinoIcons.person_2_fill, size: 64, color: Colors.white.withValues(alpha: 0.2)),
                                  const SizedBox(height: 16),
                                  Text("No contacts found", style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 16)),
                                ],
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                                itemCount: contacts.length,
                                separatorBuilder: (_, __) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                                  child: Divider(color: Colors.white.withValues(alpha: 0.05), height: 1),
                                ),
                                itemBuilder: (context, index) {
                                  final contactId = contacts[index];
                                  final name = contactId; 
                                  
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                      radius: 26,
                                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                                      backgroundImage: NetworkImage('https://api.dicebear.com/9.x/adventurer/png?seed=${Uri.encodeComponent(name)}'),
                                    ),
                                    title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                                    subtitle: Text('Contact', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14)),
                                    trailing: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF128C7E),
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                      ),
                                      onPressed: () {
                                        Navigator.pop(sheetContext);
                                        AppToast.show(context, 'Added $name to the call', type: AppToastType.success);
                                      },
                                      child: const Text('Add', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                    ),
                                  );
                                },
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
