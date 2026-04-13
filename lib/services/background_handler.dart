import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';


import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // CRITICAL FIX: Promote to foreground immediately to prevent "ForegroundServiceDidNotStartInTimeException"
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });

    // Auto promote now
    service.setAsForegroundService();
  }

  // No backend initialization in dummy mode

  // Initialize Local Notifications for PING
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  service.on('app_lifecycle').listen((event) {
    if (event != null && event['state'] != null) {
      // isAppInForeground logic... 
    }
  });

  service.on('init').listen((event) {
    if (event != null && event['call_id'] != null) {
      // Dummy mode: Background polling disabled
      // Future Cloudflare logic would poll or listen to WebSocket here.
    }
  });
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'aura_call_foreground',
      initialNotificationTitle: 'AURA Service',
      initialNotificationContent: 'Listening for calls...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onServiceBackground,
    ),
  );

  service.startService();
}

@pragma('vm:entry-point')
Future<bool> onServiceBackground(ServiceInstance service) async {
  return true;
}
