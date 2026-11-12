import 'package:journalist_app_1/models/reporter.dart';

/// Server-enforced roles returned by `/api/v1/auth/login`.
enum PortalUserRole {
  reporter('reporter', 'Reporter'),
  editor('editor', 'Editor'),
  seniorEditor('senior_editor', 'Senior Editor'),
  admin('admin', 'Admin');

  final String apiValue;
  final String displayLabel;

  const PortalUserRole(this.apiValue, this.displayLabel);

  static PortalUserRole fromApiValue(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    for (final role in PortalUserRole.values) {
      if (role.apiValue == normalized) {
        return role;
      }
    }
    return PortalUserRole.reporter;
  }

  bool get isEditorialStaff =>
      this == editor || this == seniorEditor || this == admin;
}

/// Authenticated user payload returned by Laravel `/api/v1/auth/login`.
class AuthUser {
  final int id;
  final String uuid;
  final String userCode;
  final String name;
  final String email;
  final PortalUserRole role;
  final String designation;
  final String? assignedArea;
  final String status;
  final bool isVerified;
  final String? googleAccountEmail;

  const AuthUser({
    required this.id,
    required this.uuid,
    required this.userCode,
    required this.name,
    required this.email,
    required this.role,
    required this.designation,
    this.assignedArea,
    this.status = 'active',
    this.isVerified = true,
    this.googleAccountEmail,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: (json['id'] as num?)?.toInt() ?? 0,
      uuid: json['uuid'] as String? ?? '',
      userCode: json['user_code'] as String? ?? '',
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: PortalUserRole.fromApiValue(json['role'] as String?),
      designation: json['designation'] as String? ?? 'Staff Reporter',
      assignedArea: json['assigned_area'] as String?,
      status: json['status'] as String? ?? 'active',
      isVerified: json['is_verified'] as bool? ?? false,
      googleAccountEmail: json['google_account_email'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uuid': uuid,
      'user_code': userCode,
      'name': name,
      'email': email,
      'role': role.apiValue,
      'designation': designation,
      'assigned_area': assignedArea,
      'status': status,
      'is_verified': isVerified,
      'google_account_email': googleAccountEmail,
    };
  }

  Reporter toReporter() {
    return Reporter(
      id: uuid.isNotEmpty ? uuid : id.toString(),
      reporterCode: userCode.isNotEmpty ? userCode : 'REP-$id',
      fullName: name,
      email: email,
      phoneNumber: '',
      designation: designation,
      assignedArea: assignedArea ?? 'Headquarters',
      googleAccountEmail: googleAccountEmail,
      isActive: status == 'active',
      isVerified: isVerified,
      createdAt: DateTime.now(),
    );
  }
}

