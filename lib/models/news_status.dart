import 'package:flutter/material.dart';
import 'package:journalist_app_1/core/constants/app_colors.dart';

/// News submission workflow statuses matching editorial requirements.
enum NewsStatus {
  draft,
  pending,
  approved,
  published,
  rejected;

  /// User-friendly label for display across UI
  String get displayName {
    switch (this) {
      case NewsStatus.draft:
        return 'Draft';
      case NewsStatus.pending:
        return 'Pending';
      case NewsStatus.approved:
        return 'Approved';
      case NewsStatus.published:
        return 'Published';
      case NewsStatus.rejected:
        return 'Rejected';
    }
  }

  /// Official status color
  Color get color {
    switch (this) {
      case NewsStatus.draft:
        return AppColors.statusDraft;
      case NewsStatus.pending:
        return AppColors.statusPending;
      case NewsStatus.approved:
        return AppColors.statusApproved;
      case NewsStatus.published:
        return AppColors.statusPublished;
      case NewsStatus.rejected:
        return AppColors.statusRejected;
    }
  }

  /// String value for API / database serialization
  String toValue() => name;

  /// Parse from string value
  static NewsStatus fromString(String value) {
    final normalized = value.toLowerCase().replaceAll(' ', '_');
    if (normalized == 'pending_review' || normalized == 'under_review') {
      return NewsStatus.pending;
    }
    return NewsStatus.values.firstWhere(
      (s) => s.name.toLowerCase() == normalized,
      orElse: () => NewsStatus.draft,
    );
  }
}
