class NotificationModel {
  final String id;
  final String icon;
  final String title;
  final String body;
  final String time;
  final bool read;
  final String type;
  final double createdAt;

  const NotificationModel({
    required this.id,
    required this.icon,
    required this.title,
    required this.body,
    required this.time,
    required this.read,
    required this.type,
    required this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> j) =>
      NotificationModel(
        id:        j['id'] as String,
        icon:      j['icon'] as String? ?? '🔔',
        title:     j['title'] as String,
        body:      j['body'] as String,
        time:      j['time'] as String,
        read:      j['read'] as bool? ?? false,
        type:      j['type'] as String? ?? 'system',
        createdAt: (j['created_at'] as num).toDouble(),
      );
}
