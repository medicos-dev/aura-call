import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://luzazzyqihpertxteokq.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx1emF6enlxaWhwZXJ0eHRlb2txIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkzMDE2MzMsImV4cCI6MjA4NDg3NzYzM30.hkCVI2w5Hx9gIhdKh53u-JrFWB3oXuOEf6ZkQzAIRu0',
  );

  final supabase = Supabase.instance.client;

  // Initialize Local Notifications for PING
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  String? myCallId;

  service.on('init').listen((event) {
    if (event != null && event['call_id'] != null) {
      myCallId = event['call_id'];

      supabase
          .channel('public:signals')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'signals',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'receiver_id',
              value: myCallId,
            ),
            callback: (payload) async {
              final newRecord = payload.newRecord;
              final type = newRecord['type'];
              final senderId = newRecord['sender_id'];

              if (type == 'ping') {
                // Trigger High Priority Notification
                const AndroidNotificationDetails
                androidPlatformChannelSpecifics = AndroidNotificationDetails(
                  'aura_ping_channel',
                  'AURA Pings',
                  channelDescription: 'High priority pings from friends',
                  importance: Importance.max,
                  priority: Priority.high,
                  showWhen: true,
                );
                const NotificationDetails platformChannelSpecifics =
                    NotificationDetails(
                      android: androidPlatformChannelSpecifics,
                    );

                await flutterLocalNotificationsPlugin.show(
                  0,
                  'PING!',
                  '$senderId is looking for you.',
                  platformChannelSpecifics,
                  payload: 'ping',
                );
              } else if (type == 'offer') {
                // Trigger CallKit
                CallKitParams callKitParams = CallKitParams(
                  id: newRecord['id'],
                  nameCaller: senderId,
                  appName: 'AURA',
                  avatar:
                      'https://ui-avatars.com/api/?name=$senderId&background=007AFF&color=fff',
                  handle: senderId,
                  type: 0,
                  textAccept: 'Accept',
                  textDecline: 'Decline',
                  missedCallNotification: const NotificationParams(
                    id: 1,
                    isShowCallback: true,
                  ),
                  extra: newRecord,
                  headers: {},
                  android: const AndroidParams(
                    isCustomNotification: true,
                    isShowLogo: false,
                    ringtonePath: 'incoming',
                    backgroundColor: '#007AFF',
                    backgroundUrl: 'assets/call_background.png',
                    actionColor: '#4CAF50',
                  ),
                  ios: const IOSParams(
                    iconName: 'CallKitLogo',
                    handleType: '',
                    supportsVideo: true,
                    maximumCallGroups: 2,
                    maximumCallsPerCallGroup: 1,
                    audioSessionMode: 'default',
                    audioSessionActive: true,
                    audioSessionPreferredSampleRate: 44100.0,
                    audioSessionPreferredIOBufferDuration: 0.005,
                    supportsDTMF: true,
                    supportsHolding: true,
                    supportsGrouping: false,
                    supportsUngrouping: false,
                    ringtonePath: 'incoming.mp3',
                  ),
                );

                await FlutterCallkitIncoming.showCallkitIncoming(callKitParams);
              }
            },
          )
          .subscribe();
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
