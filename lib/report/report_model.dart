// lib/report/report_model.dart

class UserReport {
  final String id;
  final String title;
  final String locationName;
  final double latitude;
  final double longitude;
  final String date;
  final String description; // 詳細事件描述
  final String category;    // 公廁/旅館/診所等
  final bool verified;      // 預設為 false (待審核)

  UserReport({
    required this.id,
    required this.title,
    required this.locationName,
    required this.latitude,
    required this.longitude,
    required this.date,
    required this.description,
    required this.category,
    this.verified = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'location_name': locationName,
        'latitude': latitude,
        'longitude': longitude,
        'date': date,
        'description': description,
        'category': category,
        'source_type': 'USER_REPORT',
        'verified': verified,
      };
}