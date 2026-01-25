import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app_theme.dart';
import '../services/call_service.dart';
import '../services/presence_service.dart';
import '../services/sound_service.dart';
import 'call_overlay.dart';
import 'add_person_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final TextEditingController _callIdController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  String? _myCallId;
  List<String> _onlineUsers = [];
  bool _isLoading = false;

  late CallService _callService;
  PresenceService? _presenceService;

  // Incoming call state
  String? _incomingCallerId;
  String? _incomingCallerName;
  bool _showIncomingCall = false;

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _requestPermissions();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _initializeServices() async {
    final prefs = await SharedPreferences.getInstance();
    _myCallId = prefs.getString('call_id');

    _callService = CallService();
    await _callService.initialize();

    // Set up incoming call handler
    _callService.onIncomingCall = (senderId, senderName) {
      setState(() {
        _incomingCallerId = senderId;
        _incomingCallerName = senderName;
        _showIncomingCall = true;
      });
      // Bell sound plays automatically in CallService on receiver side
    };

    _callService.onCallStateChanged = (state) {
      if (state == CallState.connected) {
        _navigateToCall();
      }
    };

    // Initialize presence
    if (_myCallId != null) {
      _presenceService = PresenceService(
        supabase: _callService._supabase,
        myCallId: _myCallId!,
        onOnlineUsersUpdated: (users) {
          setState(() {
            _onlineUsers = users.where((id) => id != _myCallId).toList();
          });
        },
      );
      _presenceService!.connect();
    }

    setState(() {});
  }

  Future<void> _requestPermissions() async {
    await [Permission.camera, Permission.microphone].request();
  }

  void _navigateToCall() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CallOverlay(callService: _callService),
      ),
    );
  }

  Future<void> _startCall({required bool isVideo}) async {
    final callId = _callIdController.text.trim().toUpperCase();

    if (callId.isEmpty) {
      _showSnackBar('Please enter a call ID');
      return;
    }

    if (callId.length != 6) {
      _showSnackBar('Call ID must be 6 characters');
      return;
    }

    if (callId == _myCallId) {
      _showSnackBar('Cannot call yourself');
      return;
    }

    setState(() => _isLoading = true);

    final success = await _callService.startCall(
      callId,
      isVideo ? CallType.video : CallType.audio,
    );

    setState(() => _isLoading = false);

    if (success) {
      _navigateToCall();
    } else {
      _showSnackBar('Failed to start call');
    }
  }

  Future<void> _acceptIncomingCall({required bool isVideo}) async {
    if (_incomingCallerId == null) return;

    setState(() {
      _showIncomingCall = false;
    });

    final success = await _callService.acceptCall(
      _incomingCallerId!,
      isVideo ? CallType.video : CallType.audio,
    );

    if (success) {
      _navigateToCall();
    }
  }

  void _rejectIncomingCall() {
    if (_incomingCallerId != null) {
      _callService.rejectCall(_incomingCallerId!);
    }

    setState(() {
      _showIncomingCall = false;
      _incomingCallerId = null;
      _incomingCallerName = null;
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _copyCallId() {
    if (_myCallId != null) {
      Clipboard.setData(ClipboardData(text: _myCallId!));
      _showSnackBar('Call ID copied!');
    }
  }

  @override
  void dispose() {
    _callIdController.dispose();
    _focusNode.dispose();
    _pulseController.dispose();
    _presenceService?.disconnect();
    _callService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.backgroundDark,
                  Color(0xFF1A1030),
                  AppTheme.backgroundDark,
                ],
              ),
            ),
          ),

          // Main content
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 24),

                // My Call ID Card
                _buildMyCallIdCard(),

                const SizedBox(height: 32),

                // Enter Call ID
                _buildCallIdInput(),

                const SizedBox(height: 24),

                // Call buttons
                _buildCallButtons(),

                const SizedBox(height: 32),

                // Online users
                Expanded(child: _buildOnlineUsers()),
              ],
            ),
          ),

          // Incoming call overlay
          if (_showIncomingCall) _buildIncomingCallOverlay(),
        ],
      ),
    );
  }

  Widget _buildMyCallIdCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: AppTheme.cardGradient,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.surfaceBorder),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryPurple.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            const Text(
              'Your Call ID',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _copyCallId,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ShaderMask(
                    shaderCallback:
                        (bounds) =>
                            AppTheme.primaryGradient.createShader(bounds),
                    child: Text(
                      _myCallId ?? '------',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(
                    Icons.copy,
                    color: AppTheme.textSecondary,
                    size: 20,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap to copy',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallIdInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.surfaceBorder),
        ),
        child: TextField(
          controller: _callIdController,
          focusNode: _focusNode,
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
          style: const TextStyle(
            fontSize: 24,
            letterSpacing: 8,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            hintText: 'ENTER ID',
            hintStyle: TextStyle(color: AppTheme.textMuted, letterSpacing: 4),
            border: InputBorder.none,
            counterText: '',
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
            UpperCaseTextFormatter(),
          ],
        ),
      ),
    );
  }

  Widget _buildCallButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // Audio call button
          Expanded(
            child: _buildCallButton(
              icon: Icons.call,
              label: 'Voice',
              gradient: const LinearGradient(
                colors: [AppTheme.primaryBlue, AppTheme.primaryCyan],
              ),
              onTap: _isLoading ? null : () => _startCall(isVideo: false),
            ),
          ),
          const SizedBox(width: 16),
          // Video call button
          Expanded(
            child: _buildCallButton(
              icon: Icons.videocam,
              label: 'Video',
              gradient: AppTheme.buttonGradient,
              onTap: _isLoading ? null : () => _startCall(isVideo: true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallButton({
    required IconData icon,
    required String label,
    required LinearGradient gradient,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: gradient.colors.first.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
              Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOnlineUsers() {
    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.backgroundCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: AppTheme.online,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Online (${_onlineUsers.length})',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child:
                _onlineUsers.isEmpty
                    ? const Center(
                      child: Text(
                        'No one online yet',
                        style: TextStyle(color: AppTheme.textMuted),
                      ),
                    )
                    : ListView.builder(
                      itemCount: _onlineUsers.length,
                      itemBuilder: (context, index) {
                        final userId = _onlineUsers[index];
                        return _buildOnlineUserTile(userId);
                      },
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildOnlineUserTile(String userId) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppTheme.online,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              userId,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                letterSpacing: 2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // Quick call buttons
          IconButton(
            onPressed: () {
              _callIdController.text = userId;
              _startCall(isVideo: false);
            },
            icon: const Icon(Icons.call, color: AppTheme.primaryCyan, size: 20),
          ),
          IconButton(
            onPressed: () {
              _callIdController.text = userId;
              _startCall(isVideo: true);
            },
            icon: const Icon(
              Icons.videocam,
              color: AppTheme.primaryPurple,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncomingCallOverlay() {
    return Container(
      color: Colors.black54,
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Pulsing avatar
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppTheme.primaryGradient,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryPurple.withOpacity(0.5),
                          blurRadius: 30,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.person,
                      size: 60,
                      color: Colors.white,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
            Text(
              _incomingCallerName ?? 'Unknown',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'ID: ${_incomingCallerId ?? ''}',
              style: const TextStyle(
                fontSize: 16,
                color: AppTheme.textSecondary,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Incoming Call...',
              style: TextStyle(fontSize: 16, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 48),

            // Accept/Reject buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Reject
                  _buildCircleButton(
                    icon: Icons.call_end,
                    color: AppTheme.error,
                    onTap: _rejectIncomingCall,
                  ),
                  // Accept audio
                  _buildCircleButton(
                    icon: Icons.call,
                    color: AppTheme.success,
                    onTap: () => _acceptIncomingCall(isVideo: false),
                  ),
                  // Accept video
                  _buildCircleButton(
                    icon: Icons.videocam,
                    color: AppTheme.primaryPurple,
                    onTap: () => _acceptIncomingCall(isVideo: true),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }
}

/// Text formatter for uppercase
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
