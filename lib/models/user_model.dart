class UserModel {
  final String id;
  final String phoneNumber;
  final String displayName;
  final String role; // 'admin', 'tactical', 'family'
  final bool isApproved; // Чи схвалений доступ тобою

  UserModel({
    required this.id,
    required this.phoneNumber,
    required this.displayName,
    required this.role,
    required this.isApproved,
  });

  // Перетворюємо дані з бази (JSON) в об'єкт Dart
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      phoneNumber: json['phone_number'] ?? '',
      displayName: json['display_name'] ?? 'Користувач',
      role: json['role'] ?? 'family', // За замовчуванням найпростіша роль
      isApproved: json['is_approved'] ?? false, // За замовчуванням доступ закритий
    );
  }

  // Клієнтська перевірка: чи має цей користувач доступ до тривожної кнопки
  bool get hasPingAccess => role == 'admin' || role == 'tactical';
}