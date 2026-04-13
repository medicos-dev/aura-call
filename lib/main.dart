import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:crypto/crypto.dart';
import 'dart:io';

import 'app_theme.dart';
import 'screens/splash_screen.dart';
import 'services/cleanup_service.dart';
import 'services/navigator_service.dart';
import 'services/contact_cache_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Generate or retrieve user call ID (Deterministic)
  await _initializeCallId();

  // Load contact cache from disk for instant hydrated UI
  await ContactCacheService().loadFromDisk();

  // Start the cleanup service (runs every 20 minutes)
  CleanupService().start();

  runApp(const AuraCallApp());
}

/// Initialize the user's 6-character call ID deterministically
Future<void> _initializeCallId() async {
  final prefs = await SharedPreferences.getInstance();
  String? callId = prefs.getString('call_id');

  // Always regenerate/verify ID based on hardware to ensure persistence across reinstalls
  if (callId == null) {
    try {
      String deviceId = 'unknown_device';
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        // Use a combination of truly unique identifiers
        // androidInfo.id is Build.ID which is NOT unique per device!
        // Use fingerprint + display which vary between devices
        deviceId =
            '${androidInfo.fingerprint}_${androidInfo.display}_${androidInfo.host}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceId =
            iosInfo.identifierForVendor ?? 'ios_vendor_id'; // Unique vendor ID
      }

      // Hash the deviceId to get a consistent 6-char code
      // We use SHA-256 and take first 3 bytes hex ? No, we need 6 chars.
      // Let's use MD5 for shorter hash, taking first 6 chars of hex might be enough collision resistance for this scale.
      // Actually, base32 of sha256 is better.
      // For simplicity and readability matching previous: 6 UPPERCASE alphanum.

      final bytes = utf8.encode('${deviceId}AURA_SALT_V1');
      final digest = sha256.convert(bytes);
      // Take first 4 bytes -> 8 hex chars. truncate to 6.
      String hex = digest.toString().toUpperCase();
      // Ensure it only contains letters/numbers? Hex is 0-9, A-F.
      // If we want more "Random" looking with full alphabet, we need base conversion.
      // But Hex (0-F) is fine for "Codes".
      callId = hex.substring(0, 6);

      // Account restore mock (Supabase removed)
      // Usually we would fetch profile from backend here.
      // For dummy frontend, we assume the local cache is all we need.
      debugPrint("Device ID: $deviceId -> Generated Call ID: $callId");
      await prefs.setString('call_id', callId);
    } catch (e) {
      callId = 'ERR000';
    }
  }
}

class AuraCallApp extends StatefulWidget {
  const AuraCallApp({super.key});

  @override
  State<AuraCallApp> createState() => _AuraCallAppState();
}

class _AuraCallAppState extends State<AuraCallApp> {
  @override
  void initState() {
    super.initState();
    _checkPendingCall();
  }

  Future<void> _checkPendingCall() async {
    // Dummy Mode - Check pending calls locally
    final prefs = await SharedPreferences.getInstance();
    final answered = prefs.getBool('answered_from_background') ?? false;
    if (answered) {
      // route appropriately
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AURA CALL',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      navigatorKey: NavigatorService().navigatorKey,
      home: const SplashScreen(),
    );
  }
}
