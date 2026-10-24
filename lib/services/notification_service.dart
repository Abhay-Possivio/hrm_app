// Port of services/notificationService.ts (notifications and sending
// broadcasts; broadcast history comes with the admin Alerts screen).

import 'package:flutter/foundation.dart';

import 'package:hrm_app/api/api_client.dart';

int _int(dynamic v) => v is num ? v.round() : int.tryParse('$v') ?? 0;
String _str(dynamic v) => v == null ? '' : '$v';
String? _strOrNull(dynamic v) => (v == null || '$v'.isEmpty) ? null : '$v';
Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : const {};

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.link,
    required this.isRead,
    required this.createdAt,
  });

  final int id;
  final String title;
  final String message;

  /// Web link the notification points to, e.g. "/alerts?id=12" for a leave request.
  final String? link;
  final bool isRead;

  /// Server time (UTC); shown in local time.
  final String createdAt;

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id,
        title: title,
        message: message,
        link: link,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt,
      );

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: _int(j['id']),
        title: _str(j['title']),
        message: _str(j['message']),
        link: _strOrNull(j['link']),
        isRead: j['is_read'] == true,
        createdAt: _str(j['created_at']),
      );
}

class NotificationPage {
  const NotificationPage({required this.results, required this.count});

  final List<AppNotification> results;
  final int count;
}

class BroadcastResult {
  const BroadcastResult({required this.success, required this.message, required this.count, required this.broadcastId});

  final bool success;
  final String message;
  final int count;
  final String broadcastId;
}

/// Ping this after reading notifications so the bell updates its count
/// (the web app's "refreshNotificationCounts" event).
class NotificationEvents extends ChangeNotifier {
  void countsChanged() => notifyListeners();
}

final notificationEvents = NotificationEvents();

class NotificationService {
  Future<NotificationPage> fetchNotifications({int page = 1, bool unreadOnly = false}) async {
    final res = await api.get('/core/notifications/', queryParameters: {
      'page': page,
      if (unreadOnly) 'unread_only': 'true',
    });
    final j = _map(res.data);
    return NotificationPage(
      results: [
        for (final e in (j['results'] as List? ?? const []))
          if (e is Map) AppNotification.fromJson(Map<String, dynamic>.from(e)),
      ],
      count: _int(j['count']),
    );
  }

  Future<void> markAsRead(int id) async {
    await api.patch('/core/notifications/$id/');
  }

  /// Sends an alert to a group, e.g. targetGroup "MY_TEAM" for a team lead.
  Future<BroadcastResult> sendBroadcast({
    required String targetGroup,
    required String title,
    required String message,
  }) async {
    final res = await api.post('/core/notifications/send/', data: {
      'target_group': targetGroup,
      'title': title,
      'message': message,
    });
    final j = _map(res.data);
    return BroadcastResult(
      success: j['success'] == true,
      message: _str(j['message']),
      count: _int(j['count']),
      broadcastId: _str(j['broadcast_id']),
    );
  }
}

final notificationService = NotificationService();