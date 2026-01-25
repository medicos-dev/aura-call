import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'app_theme.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize Supabase
  await Supabase.initialize(
    url:
        'https://luzazzyqihpertxteokq.supabase.co', // TODO: Replace with actual URL
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx1emF6enlxaWhwZXJ0eHRlb2txIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkzMDE2MzMsImV4cCI6MjA4NDg3NzYzM30.hkCVI2w5Hx9gIhdKh53u-JrFWB3oXuOEf6ZkQzAIRu0', // TODO: Replace with actual key
  );

  // Generate or retrieve user call ID
  await _initializeCallId();

  runApp(const AuraCallApp());
}

/// Initialize the user's 6-character call ID
Future<void> _initializeCallId() async {
  final prefs = await SharedPreferences.getInstance();
  String? callId = prefs.getString('call_id');

  if (callId == null) {
    // Generate a new 6-character alphanumeric ID
    callId = _generateCallId();
    await prefs.setString('call_id', callId);
  }
}

/// Generate a random 6-character alphanumeric call ID
String _generateCallId() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final uuid = const Uuid().v4().replaceAll('-', '').toUpperCase();
  return uuid.substring(0, 6);
}

class AuraCallApp extends StatelessWidget {
  const AuraCallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AURA CALL',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const SplashScreen(),
    );
  }
}
