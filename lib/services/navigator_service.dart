import 'package:flutter/cupertino.dart';
import '../screens/call_overlay.dart';
import '../services/call_service.dart';

/// Global navigator service for navigation from background/services
class NavigatorService {
  static final NavigatorService _instance = NavigatorService._internal();
  factory NavigatorService() => _instance;
  NavigatorService._internal();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// Push call screen directly (works from foreground or background)
  void pushCallScreen({
    required CallService callService,
    required String displayName,
    required bool isVideoCall,
    bool answeredFromBackground = false,
  }) {
    navigatorKey.currentState?.push(
      CupertinoPageRoute(
        builder:
            (_) => CallOverlay(
              callService: callService,
              remoteDisplayName: displayName,
              isVideoCall: isVideoCall,
              answeredFromBackground: answeredFromBackground,
            ),
      ),
    );
  }

  /// Pop current screen
  void pop() {
    navigatorKey.currentState?.pop();
  }

  /// Check if can pop
  bool canPop() {
    return navigatorKey.currentState?.canPop() ?? false;
  }
}
