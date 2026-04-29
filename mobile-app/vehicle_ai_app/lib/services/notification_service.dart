import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

/// Manages all local notifications for document expiry reminders.
/// Call [NotificationService.instance.init()] once in main() before runApp.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = "doc_expiry_channel";
  static const String _channelName = "Document Expiry Reminders";
  static const String _channelDesc =
      "Reminds you when vehicle documents are expiring";

  // ── Init ──────────────────────────────────────────────────────────────────
  Future<void> init() async {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata')); // IST

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _onTapped,
    );

    // Android 13+ explicit permission
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  void _onTapped(NotificationResponse response) {
    // payload = "vehicleNumber|docType" — extend for deep navigation if needed
    debugPrint('[Notification tapped] payload: ${response.payload}');
  }

  // ── Notification details ──────────────────────────────────────────────────
  NotificationDetails get _details => const NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  // ── Stable ID from vehicle+docType so rescheduling cancels old ones ───────
  int _id(String vehicleNumber, String docType, {required bool isWarning}) {
    final base = (vehicleNumber + docType).hashCode.abs() % 900;
    return isWarning ? 1000 + base : 2000 + base;
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Schedule 7-day warning + expiry-day alert for one document.
  /// Safe to call multiple times — cancels existing before rescheduling.
  Future<void> scheduleDocumentReminders({
    required String vehicleNumber,
    required String docType,
    required String expiryDateStr, // "DD/MM/YYYY"
  }) async {
    await cancelDocumentReminders(
      vehicleNumber: vehicleNumber,
      docType: docType,
    );

    DateTime expiryDate;
    try {
      final p = expiryDateStr.split('/');
      // Notify at 9 AM on the relevant days
      expiryDate = DateTime(
        int.parse(p[2]),
        int.parse(p[1]),
        int.parse(p[0]),
        9,
      );
    } catch (_) {
      debugPrint('[Notifications] Bad date: $expiryDateStr');
      return;
    }

    final now = DateTime.now();
    final days = expiryDate.difference(now).inDays;
    final payload = '$vehicleNumber|$docType';

    // Already expired → immediate alert
    if (days < 0) {
      await _plugin.show(
        _id(vehicleNumber, docType, isWarning: false),
        '⚠️ $docType Expired!',
        'Your $docType for $vehicleNumber expired $expiryDateStr. Renew immediately.',
        _details,
        payload: payload,
      );
      return;
    }

    // Within 7 days but warning date already passed → show immediately
    final warnDate = expiryDate.subtract(const Duration(days: 7));
    if (warnDate.isAfter(now)) {
      // Schedule 7-day warning for the future
      await _zonedSchedule(
        id: _id(vehicleNumber, docType, isWarning: true),
        title: '📋 $docType Expiring in 7 Days',
        body:
            'Your $docType for $vehicleNumber expires on $expiryDateStr. Tap to renew.',
        at: warnDate,
        payload: payload,
      );
    } else if (days <= 7) {
      // Already inside the 7-day window → show now
      await _plugin.show(
        _id(vehicleNumber, docType, isWarning: true),
        '📋 $docType Expiring in $days Day(s)',
        'Your $docType for $vehicleNumber expires on $expiryDateStr. Please renew soon.',
        _details,
        payload: payload,
      );
    }

    // Schedule expiry-day alert
    if (expiryDate.isAfter(now)) {
      await _zonedSchedule(
        id: _id(vehicleNumber, docType, isWarning: false),
        title: '🚨 $docType Expires Today!',
        body:
            'Your $docType for $vehicleNumber expires today ($expiryDateStr). Renew now.',
        at: expiryDate,
        payload: payload,
      );
    }

    debugPrint(
      '[Notifications] Reminders scheduled for $vehicleNumber $docType — $days days left',
    );
  }

  /// Cancel both reminders for a specific document.
  Future<void> cancelDocumentReminders({
    required String vehicleNumber,
    required String docType,
  }) async {
    await _plugin.cancel(_id(vehicleNumber, docType, isWarning: true));
    await _plugin.cancel(_id(vehicleNumber, docType, isWarning: false));
  }

  /// Cancel every scheduled notification.
  Future<void> cancelAll() async => _plugin.cancelAll();

  // ── Internal scheduler ────────────────────────────────────────────────────
  Future<void> _zonedSchedule({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    required String payload,
  }) async {
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(at, tz.local),
      _details,
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}
