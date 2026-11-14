import 'package:flutter/material.dart';
import 'package:journalist_app_1/core/constants/app_colors.dart';

/// News submission workflow statuses matching editorial requirements.
enum NewsStatus {
  draft,
  pending,
  underReview,
  correctionRequested,
  approved,
  published,
  rejected;

  /// User-friendly label for display across UI
  String get displayName {
    switch (this) {
      case NewsStatus.draft:
        return 'Draft';
      case NewsStatus.pending:
        return 'Submitted';
      case NewsStatus.underReview:
        return 'Under Review';
      case NewsStatus.correctionRequested:
        return 'Correction Requested';
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
      case NewsStatus.underReview:
        return const Color(0xFF0284C7); // Sky Blue
      case NewsStatus.correctionRequested:
        return const Color(0xFFEA580C); // Warm Orange
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
    if (normalized == 'pending' ||
        normalized == 'submitted' ||
        normalized == 'pending_review' ||
        normalized == 'resubmitted') {
      return NewsStatus.pending;
    }
    if (normalized == 'under_review' ||
        normalized == 'in_review') {
      return NewsStatus.underReview;
    }
    if (normalized == 'correction_requested' ||
        normalized == 'correctionrequested') {
      return NewsStatus.correctionRequested;
    }
    return NewsStatus.values.firstWhere(
      (s) => s.name.toLowerCase() == normalized,
      orElse: () => NewsStatus.draft,
    );
  }
}
