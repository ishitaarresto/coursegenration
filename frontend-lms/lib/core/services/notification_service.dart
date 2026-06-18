import '../../data/models/notification_model.dart';
import 'api_client.dart';

class NotificationService {
  static Future<List<NotificationModel>> list(String recipientId) async {
    final resp = await apiClient.get(
      '/api/v1/notifications',
      queryParameters: {'recipient_id': recipientId},
    );
    final data = resp.data as Map<String, dynamic>;
    final items = data['notifications'] as List<dynamic>? ?? [];
    return items
        .map((e) => NotificationModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> markRead(String notifId) async {
    await apiClient.patch('/api/v1/notifications/$notifId/read');
  }

  static Future<void> markAllRead(String recipientId) async {
    await apiClient.patch(
      '/api/v1/notifications/read-all',
      queryParameters: {'recipient_id': recipientId},
    );
  }
}
