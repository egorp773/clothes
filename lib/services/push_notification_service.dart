import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/firebase_config.dart';

const String pushMessagesChannelId = 'messages';
const String pushMessagesChannelName = 'Сообщения';
const String pushSilentMessagesChannelId = 'messages_silent';
const String pushSilentMessagesChannelName = 'Сообщения без звука';

const _localTapPortName = 'clothes.push.local_notification_taps';
const _messageIdPayloadKey = '_push_message_id';
const _titlePayloadKey = '_push_title';
const _bodyPayloadKey = '_push_body';

enum PushPermissionStatus {
  unsupported,
  notDetermined,
  denied,
  authorized,
  provisional,
}

class PushNotificationTap {
  const PushNotificationTap({
    required this.data,
    this.messageId,
    this.title,
    this.body,
  });

  final Map<String, dynamic> data;
  final String? messageId;
  final String? title;
  final String? body;

  String? get type => _nonEmptyString(data['type']);
  String? get route =>
      _nonEmptyString(data['route']) ??
      _nonEmptyString(data['deep_link']) ??
      _nonEmptyString(data['deeplink']);

  factory PushNotificationTap.fromRemoteMessage(RemoteMessage message) {
    return PushNotificationTap(
      data: Map<String, dynamic>.unmodifiable(message.data),
      messageId: _nonEmptyString(message.messageId),
      title: _nonEmptyString(message.notification?.title),
      body: _nonEmptyString(message.notification?.body),
    );
  }

  factory PushNotificationTap.fromPayload(String payload) {
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(payload);
      data = decoded is Map
          ? decoded.map((key, value) => MapEntry(key.toString(), value))
          : <String, dynamic>{'payload': payload};
    } catch (_) {
      data = <String, dynamic>{'payload': payload};
    }

    final messageId = _nonEmptyString(data.remove(_messageIdPayloadKey));
    final title = _nonEmptyString(data.remove(_titlePayloadKey));
    final body = _nonEmptyString(data.remove(_bodyPayloadKey));
    return PushNotificationTap(
      data: Map<String, dynamic>.unmodifiable(data),
      messageId: messageId,
      title: title,
      body: body,
    );
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final options = RuntimeFirebaseConfig.currentPlatform;
  if (options == null) return;

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: options);
    }

    // Notification payloads are displayed by FCM while the app is backgrounded.
    // Only data-only messages need a local notification here.
    if (message.notification == null) {
      await PushNotificationService._showBackgroundMessage(message);
    }
  } catch (error, stackTrace) {
    debugPrint('Push background handler failed: $error\n$stackTrace');
  }
}

@pragma('vm:entry-point')
void localNotificationTapBackground(NotificationResponse response) {
  final payload = response.payload;
  if (payload == null || payload.isEmpty) return;
  IsolateNameServer.lookupPortByName(_localTapPortName)?.send(payload);
}

class PushNotificationService {
  PushNotificationService._();

  static final _localNotifications = FlutterLocalNotificationsPlugin();
  static final _tokenRefreshController = StreamController<String>.broadcast();
  static final _tapController =
      StreamController<PushNotificationTap>.broadcast();

  static Future<bool>? _initialization;
  static StreamSubscription<String>? _tokenRefreshSubscription;
  static StreamSubscription<RemoteMessage>? _foregroundSubscription;
  static StreamSubscription<RemoteMessage>? _openedAppSubscription;
  static ReceivePort? _localTapPort;
  static bool _initializationAttempted = false;
  static bool _localNotificationsInitialized = false;
  static bool _enabled = false;
  static PushNotificationTap? _initialTap;

  static bool get isEnabled =>
      _enabled ||
      (!_initializationAttempted && RuntimeFirebaseConfig.isConfigured);

  static String get platform {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  static Stream<String> get onTokenRefresh => _tokenRefreshController.stream;

  static Stream<PushNotificationTap> get onNotificationTap =>
      _tapController.stream;

  static Future<PushPermissionStatus> get permissionStatus =>
      getPermissionStatus();

  static Future<bool> initialize() =>
      _initialization ??= _initializeTransport();

  static Future<String?> currentToken() async {
    if (!await initialize()) return null;
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (error) {
      // On iOS this can happen briefly before APNs provides its device token.
      debugPrint('FCM token is not available yet: $error');
      return null;
    }
  }

  static Future<void> deleteToken() async {
    if (!await initialize()) return;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (error) {
      debugPrint('Unable to delete FCM token: $error');
    }
  }

  static Future<PushPermissionStatus> getPermissionStatus() async {
    if (!await initialize()) return PushPermissionStatus.unsupported;
    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      return _mapPermissionStatus(settings.authorizationStatus);
    } catch (error) {
      debugPrint('Unable to read notification permission: $error');
      return PushPermissionStatus.unsupported;
    }
  }

  static Future<PushPermissionStatus> requestPermission({
    bool provisional = false,
  }) async {
    if (!await initialize()) return PushPermissionStatus.unsupported;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: provisional,
      );
      return _mapPermissionStatus(settings.authorizationStatus);
    } catch (error) {
      debugPrint('Unable to request notification permission: $error');
      return PushPermissionStatus.unsupported;
    }
  }

  /// Returns and clears the notification that launched the application.
  /// Call after awaiting [initialize].
  static PushNotificationTap? takeInitialTap() {
    final tap = _initialTap;
    _initialTap = null;
    return tap;
  }

  static Future<bool> _initializeTransport() async {
    _initializationAttempted = true;
    final options = RuntimeFirebaseConfig.currentPlatform;
    if (options == null) {
      debugPrint(
        'Push transport disabled: Firebase --dart-define values are missing '
        'or the current platform is unsupported.',
      );
      return false;
    }

    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: options);
      }

      await _initializeLocalNotifications(registerCallbacks: true);
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: false,
            badge: false,
            sound: false,
          );

      _listenForLocalBackgroundTaps();
      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh
          .listen(
            _tokenRefreshController.add,
            onError: (Object error, StackTrace stackTrace) {
              debugPrint('FCM token refresh failed: $error\n$stackTrace');
            },
          );
      await _foregroundSubscription?.cancel();
      _foregroundSubscription = FirebaseMessaging.onMessage.listen(
        _handleForegroundMessage,
      );
      await _openedAppSubscription?.cancel();
      _openedAppSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => _emitTap(PushNotificationTap.fromRemoteMessage(message)),
      );

      await _readInitialTap();
      _enabled = true;
      return true;
    } catch (error, stackTrace) {
      _enabled = false;
      debugPrint('Push transport initialization failed: $error\n$stackTrace');
      return false;
    }
  }

  static Future<void> _initializeLocalNotifications({
    required bool registerCallbacks,
  }) async {
    if (_localNotificationsInitialized) return;

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        defaultPresentAlert: false,
        defaultPresentBadge: false,
        defaultPresentSound: false,
        defaultPresentBanner: false,
        defaultPresentList: false,
      ),
    );
    await _localNotifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: registerCallbacks
          ? _handleLocalNotificationResponse
          : null,
      onDidReceiveBackgroundNotificationResponse: registerCallbacks
          ? localNotificationTapBackground
          : null,
    );
    await _createAndroidChannels();
    _localNotificationsInitialized = true;
  }

  static Future<void> _createAndroidChannels() async {
    if (defaultTargetPlatform != TargetPlatform.android || kIsWeb) return;
    final android = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        pushMessagesChannelId,
        pushMessagesChannelName,
        description: 'Новые сообщения и важные события',
        importance: Importance.high,
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        pushSilentMessagesChannelId,
        pushSilentMessagesChannelName,
        description: 'Сообщения без звука и вибрации',
        importance: Importance.high,
        playSound: false,
        enableVibration: false,
      ),
    );
  }

  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    // Chat/message updates already have an in-app realtime presentation.
    // A second system banner here would be a distracting duplicate.
    if (_messageType(message) == 'message') return;
    await _showLocalNotification(message);
  }

  static Future<void> _showBackgroundMessage(RemoteMessage message) async {
    await _initializeLocalNotifications(registerCallbacks: false);
    await _showLocalNotification(message);
  }

  static Future<void> _showLocalNotification(RemoteMessage message) async {
    final title = _notificationTitle(message);
    final body = _notificationBody(message);
    if (title == null && body == null) return;

    final silent = _isSilent(message);
    final channelId = silent
        ? pushSilentMessagesChannelId
        : pushMessagesChannelId;
    final channelName = silent
        ? pushSilentMessagesChannelName
        : pushMessagesChannelName;
    final threadId = _nonEmptyString(message.data['thread_id']);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: silent
            ? 'Сообщения без звука и вибрации'
            : 'Новые сообщения и важные события',
        importance: Importance.high,
        priority: Priority.high,
        playSound: !silent,
        enableVibration: !silent,
        groupKey: threadId,
        category: AndroidNotificationCategory.message,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentBadge: true,
        presentSound: !silent,
        threadIdentifier: threadId,
      ),
    );
    await _localNotifications.show(
      id: _notificationId(message),
      title: title,
      body: body,
      notificationDetails: details,
      payload: _encodePayload(message, title: title, body: body),
    );
  }

  static Future<void> _readInitialTap() async {
    final localLaunch = await _localNotifications
        .getNotificationAppLaunchDetails();
    final localPayload = localLaunch?.didNotificationLaunchApp == true
        ? localLaunch?.notificationResponse?.payload
        : null;
    if (localPayload != null && localPayload.isNotEmpty) {
      _initialTap = PushNotificationTap.fromPayload(localPayload);
    }

    final remoteMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (remoteMessage != null) {
      _initialTap ??= PushNotificationTap.fromRemoteMessage(remoteMessage);
    }
  }

  static void _listenForLocalBackgroundTaps() {
    if (_localTapPort != null) return;
    final receivePort = ReceivePort();
    if (!IsolateNameServer.registerPortWithName(
      receivePort.sendPort,
      _localTapPortName,
    )) {
      IsolateNameServer.removePortNameMapping(_localTapPortName);
      IsolateNameServer.registerPortWithName(
        receivePort.sendPort,
        _localTapPortName,
      );
    }
    _localTapPort = receivePort;
    receivePort.listen((payload) {
      if (payload is String && payload.isNotEmpty) {
        _emitTap(PushNotificationTap.fromPayload(payload));
      }
    });
  }

  static void _handleLocalNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    _emitTap(PushNotificationTap.fromPayload(payload));
  }

  static void _emitTap(PushNotificationTap tap) {
    if (!_tapController.isClosed) _tapController.add(tap);
  }

  static PushPermissionStatus _mapPermissionStatus(AuthorizationStatus status) {
    return switch (status) {
      AuthorizationStatus.authorized => PushPermissionStatus.authorized,
      AuthorizationStatus.provisional => PushPermissionStatus.provisional,
      AuthorizationStatus.denied => PushPermissionStatus.denied,
      AuthorizationStatus.notDetermined => PushPermissionStatus.notDetermined,
    };
  }

  static String _messageType(RemoteMessage message) =>
      _nonEmptyString(message.data['type'])?.toLowerCase() ?? '';

  static bool _isSilent(RemoteMessage message) {
    final channelId =
        _nonEmptyString(message.data['channel_id']) ??
        _nonEmptyString(message.notification?.android?.channelId);
    if (channelId == pushSilentMessagesChannelId) return true;
    final raw = _nonEmptyString(message.data['silent'])?.toLowerCase();
    if (raw == 'true' || raw == '1' || raw == 'yes') return true;
    final soundEnabled = _nonEmptyString(
      message.data['sound_enabled'],
    )?.toLowerCase();
    return soundEnabled == 'false' || soundEnabled == '0';
  }

  static String? _notificationTitle(RemoteMessage message) =>
      _nonEmptyString(message.notification?.title) ??
      _nonEmptyString(message.data['title']) ??
      'Clothes';

  static String? _notificationBody(RemoteMessage message) =>
      _nonEmptyString(message.notification?.body) ??
      _nonEmptyString(message.data['body']) ??
      _nonEmptyString(message.data['message']);

  static String _encodePayload(
    RemoteMessage message, {
    required String? title,
    required String? body,
  }) {
    return jsonEncode(<String, dynamic>{
      ...message.data,
      if (_nonEmptyString(message.messageId) case final messageId?)
        _messageIdPayloadKey: messageId,
      if (title != null) _titlePayloadKey: title,
      if (body != null) _bodyPayloadKey: body,
    });
  }

  static int _notificationId(RemoteMessage message) {
    final source =
        _nonEmptyString(message.messageId) ??
        '${message.sentTime?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch}'
            '${message.data}';
    var hash = 0;
    for (final codeUnit in source.codeUnits) {
      hash = ((hash * 31) + codeUnit) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }
}

String? _nonEmptyString(Object? value) {
  final normalized = value?.toString().trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}
