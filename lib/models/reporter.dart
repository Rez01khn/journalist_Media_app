/// Represents a registered field journalist / reporter in the editorial portal.
class Reporter {
  final String id;
  final String reporterCode;
  final String fullName;
  final String email;
  final String phoneNumber;
  final String designation;
  final String assignedArea;
  final String? googleAccountEmail; // For reporter-owned Google Drive storage
  final bool isActive;
  final bool isVerified;
  final DateTime createdAt;

  const Reporter({
    required this.id,
    required this.reporterCode,
    required this.fullName,
    required this.email,
    required this.phoneNumber,
    required this.designation,
    required this.assignedArea,
    this.googleAccountEmail,
    this.isActive = true,
    this.isVerified = true,
    required this.createdAt,
  });

  Reporter copyWith({
    String? id,
    String? reporterCode,
    String? fullName,
    String? email,
    String? phoneNumber,
    String? designation,
    String? assignedArea,
    String? googleAccountEmail,
    bool? isActive,
    bool? isVerified,
    DateTime? createdAt,
  }) {
    return Reporter(
      id: id ?? this.id,
      reporterCode: reporterCode ?? this.reporterCode,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      designation: designation ?? this.designation,
      assignedArea: assignedArea ?? this.assignedArea,
      googleAccountEmail: googleAccountEmail ?? this.googleAccountEmail,
      isActive: isActive ?? this.isActive,
      isVerified: isVerified ?? this.isVerified,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'reporter_code': reporterCode,
      'full_name': fullName,
      'email': email,
      'phone_number': phoneNumber,
      'designation': designation,
      'assigned_area': assignedArea,
      'google_account_email': googleAccountEmail,
      'is_active': isActive,
      'is_verified': isVerified,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Reporter.fromJson(Map<String, dynamic> json) {
    return Reporter(
      id: json['id'] as String,
      reporterCode: json['reporter_code'] as String? ?? 'REP-000',
      fullName: json['full_name'] as String,
      email: json['email'] as String,
      phoneNumber: json['phone_number'] as String,
      designation: json['designation'] as String,
      assignedArea: json['assigned_area'] as String,
      googleAccountEmail: json['google_account_email'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      isVerified: json['is_verified'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}

