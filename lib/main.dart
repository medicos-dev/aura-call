import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:crypto/crypto.dart';
import 'dart:io';

import 'app_theme.dart';
import 'screens/splash_screen.dart';
import 'services/cleanup_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://luzazzyqihpertxteokq.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx1emF6enlxaWhwZXJ0eHRlb2txIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkzMDE2MzMsImV4cCI6MjA4NDg3NzYzM30.hkCVI2w5Hx9gIhdKh53u-JrFWB3oXuOEf6ZkQzAIRu0',
  );

  // Generate or retrieve user call ID (Deterministic)
  await _initializeCallId();

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
        deviceId = androidInfo.id; // Unique ID for the device
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

      final bytes = utf8.encode(deviceId + "AURA_SALT_V1");
      final digest = sha256.convert(bytes);
      // Take first 4 bytes -> 8 hex chars. truncate to 6.
      String hex = digest.toString().toUpperCase();
      // Ensure it only contains letters/numbers? Hex is 0-9, A-F.
      // If we want more "Random" looking with full alphabet, we need base conversion.
      // But Hex (0-F) is fine for "Codes".
      callId = hex.substring(0, 6);

      print("Device ID: $deviceId -> Generated Call ID: $callId");
      await prefs.setString('call_id', callId);

      // RESTORE CHECK: Does this ID exist in Supabase?
      final supabase = Supabase.instance.client;
      try {
        final data =
            await supabase
                .from('profiles')
                .select()
                .eq('call_id', callId)
                .maybeSingle();

        if (data != null) {
          // Account exists! Restore it.
          final name = data['username'] as String?;
          final avatar = data['avatar_url'] as String?;

          if (name != null) {
            await prefs.setString('user_name', name);
            if (avatar != null) await prefs.setString('user_avatar', avatar);
            await prefs.setBool('onboarding_complete', true);
            print("Restored account for $name");
          }
        }
      } catch (e) {
        print("Error checking for existing account: $e");
      }
    } catch (e) {
      // Fallback
      callId = 'ERR000'; // Should not happen
    }
  }
}

class AuraCallApp extends StatelessWidget {
  const AuraCallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AURA CALL',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
    );
  }
}
