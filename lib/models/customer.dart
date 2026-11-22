enum CustomerSegment {
  retail,
  regular,
  wholesale;

  static CustomerSegment fromName(String? value) {
    return CustomerSegment.values.firstWhere(
      (s) => s.name == value,
      orElse: () => CustomerSegment.retail,
    );
  }
}

class Customer {
  const Customer({
    required this.id,
    required this.name,
    this.phone = '',
    this.note = '',
    this.segment = CustomerSegment.retail,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String phone;
  final String note;
  final CustomerSegment segment;
  final DateTime createdAt;

  Customer copyWith({
    String? id,
    String? name,
    String? phone,
    String? note,
    CustomerSegment? segment,
    DateTime? createdAt,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      note: note ?? this.note,
      segment: segment ?? this.segment,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'note': note,
      'segment': segment.name,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'] as String,
      name: json['name'] as String,
      phone: (json['phone'] as String?) ?? '',
      note: (json['note'] as String?) ?? '',
      segment: CustomerSegment.fromName(json['segment'] as String?),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
