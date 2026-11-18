class Customer {
  const Customer({
    required this.id,
    required this.name,
    this.phone = '',
    this.note = '',
    required this.createdAt,
  });

  final String id;
  final String name;
  final String phone;
  final String note;
  final DateTime createdAt;

  Customer copyWith({
    String? id,
    String? name,
    String? phone,
    String? note,
    DateTime? createdAt,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'note': note,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'] as String,
      name: json['name'] as String,
      phone: (json['phone'] as String?) ?? '',
      note: (json['note'] as String?) ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
