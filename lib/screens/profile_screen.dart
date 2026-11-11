import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journalist_app_1/models/news_media.dart';
import 'package:journalist_app_1/providers/google_drive_provider.dart';

/// The ProfileScreen displays a journalist's official editorial credentials,
/// contact details, assigned bureau/beat, account status, and Google Drive personal storage.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  // Local sample mock journalist data
  static const String fullName = 'Rezwan Karim';
  static const String reporterId = 'REP-2026-084';
  static const String designation = 'Senior Field Correspondent';
  static const String email = 'rezwan.karim@newsdesk.bd';
  static const String phone = '+880 1712-345678';
  static const String assignedArea = 'Dhaka Central & South (Motijheel, Old Town)';
  static const String accountStatus = 'Active & Verified';

  void _showNotice(BuildContext context, String action) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$action is a prototype and will be connected in a future task.',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0D253F),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const navyPrimary = Color(0xFF0D253F);
    const navyDark = Color(0xFF091B2E);
    const neutralLight = Color(0xFFF7F9FC);

    final driveState = ref.watch(googleDriveStateProvider);

    return Scaffold(
      backgroundColor: neutralLight,
      appBar: AppBar(
        backgroundColor: navyPrimary,
        elevation: 0,
        title: const Text(
          'Reporter Profile',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Profile Header Card ---
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Avatar Placeholder
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 42,
                          backgroundColor: navyPrimary.withValues(alpha: 0.1),
                          child: const Icon(
                            Icons.person_rounded,
                            size: 50,
                            color: navyPrimary,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Color(0xFF16A34A),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Full Name
                    const Text(
                      fullName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: navyDark,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Designation & Bureau
                    Text(
                      designation,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Official Press ID Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: navyPrimary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: navyPrimary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.verified_rounded,
                            size: 14,
                            color: navyPrimary,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'PRESS ID: $reporterId',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: navyPrimary,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // --- Section: Editorial Credentials ---
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'Editorial Credentials',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: navyDark,
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildInfoTile(
                      icon: Icons.badge_outlined,
                      label: 'Reporter ID',
                      value: reporterId,
                      navyPrimary: navyPrimary,
                      isMonospace: true,
                    ),
                    _buildDivider(),
                    _buildInfoTile(
                      icon: Icons.work_outline_rounded,
                      label: 'Designation',
                      value: designation,
                      navyPrimary: navyPrimary,
                    ),
                    _buildDivider(),
                    _buildInfoTile(
                      icon: Icons.map_outlined,
                      label: 'Assigned Area',
                      value: assignedArea,
                      navyPrimary: navyPrimary,
                    ),
                    _buildDivider(),
                    _buildInfoTile(
                      icon: Icons.check_circle_outline_rounded,
                      label: 'Account Status',
                      value: accountStatus,
                      navyPrimary: navyPrimary,
                      valueColor: const Color(0xFF16A34A),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // --- Section: Contact Information ---
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'Contact Information',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: navyDark,
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildInfoTile(
                      icon: Icons.email_outlined,
                      label: 'Official Email',
                      value: email,
                      navyPrimary: navyPrimary,
                    ),
                    _buildDivider(),
                    _buildInfoTile(
                      icon: Icons.phone_outlined,
                      label: 'Phone Number',
                      value: phone,
                      navyPrimary: navyPrimary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // --- Section: Google Drive Storage ---
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Google Drive Storage',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: navyDark,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: driveState.isConnected
                            ? const Color(0xFFDCFCE7)
                            : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            driveState.isConnected
                                ? Icons.cloud_done_rounded
                                : Icons.cloud_off_rounded,
                            size: 13,
                            color: driveState.isConnected
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFD97706),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            driveState.isConnected ? 'Connected' : 'Not Connected',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: driveState.isConnected
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFFD97706),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!driveState.isConnected) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: navyPrimary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.add_to_drive_rounded,
                              color: navyPrimary,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Personal Reporter Drive',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: navyDark,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Original high-res photos, field audio dispatches, and draft backups are safely uploaded directly to your own Google Drive account.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (driveState.errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: Color(0xFFDC2626),
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  driveState.errorMessage!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFFB91C1C),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: driveState.isLoading
                              ? null
                              : () async {
                                  final success = await ref
                                      .read(googleDriveStateProvider.notifier)
                                      .connectAccount(preferredEmail: email);
                                  if (context.mounted && success) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Google Drive connected successfully!',
                                        ),
                                        backgroundColor: Color(0xFF16A34A),
                                      ),
                                    );
                                  }
                                },
                          icon: driveState.isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.login_rounded, size: 18),
                          label: Text(
                            driveState.isLoading
                                ? 'Connecting...'
                                : 'Connect Google Drive',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: navyPrimary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      _buildInfoTile(
                        icon: Icons.account_circle_outlined,
                        label: 'Connected Google Account',
                        value: driveState.accountEmail ?? 'Connected',
                        navyPrimary: navyPrimary,
                      ),
                      _buildDivider(),
                      _buildInfoTile(
                        icon: Icons.folder_special_outlined,
                        label: 'App Storage Folder',
                        value: driveState.folderName,
                        navyPrimary: navyPrimary,
                      ),
                      _buildDivider(),
                      _buildInfoTile(
                        icon: Icons.cloud_done_outlined,
                        label: 'Cloud Assets Synced',
                        value: '${driveState.files.length} field dispatches',
                        navyPrimary: navyPrimary,
                        valueColor: const Color(0xFF16A34A),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _showDriveFilesBottomSheet(context, ref),
                              icon: const Icon(Icons.folder_open_rounded, size: 16),
                              label: const Text(
                                'View Files',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: navyPrimary,
                                side: const BorderSide(color: navyPrimary),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: driveState.isLoading
                                ? null
                                : () async {
                                    await ref
                                        .read(googleDriveStateProvider.notifier)
                                        .disconnectAccount();
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Google Drive disconnected.'),
                                        ),
                                      );
                                    }
                                  },
                            icon: const Icon(
                              Icons.link_off_rounded,
                              size: 16,
                              color: Color(0xFFDC2626),
                            ),
                            label: const Text(
                              'Disconnect',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFDC2626),
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.red.shade200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // --- Section: Account Actions (Prototypes) ---
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: navyPrimary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.lock_reset_rounded, color: navyPrimary, size: 20),
                      ),
                      title: const Text(
                        'Change Password',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: navyDark),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                      onTap: () => _showNotice(context, 'Change Password'),
                    ),
                    _buildDivider(),
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.logout_rounded, color: Color(0xFFDC2626), size: 20),
                      ),
                      title: const Text(
                        'Logout',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                      onTap: () => _showNotice(context, 'Logout'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Editorial Footer Notice
              Text(
                'Newsroom Editorial & Field Reporting Desk\nID Card Verification Portal v1.0',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade400,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDriveFilesBottomSheet(BuildContext context, WidgetRef ref) {
    const navyPrimary = Color(0xFF0D253F);
    const navyDark = Color(0xFF091B2E);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        return Consumer(
          builder: (ctx, watchRef, _) {
            final driveState = watchRef.watch(googleDriveStateProvider);

            return Container(
              height: MediaQuery.of(ctx).size.height * 0.75,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.folder_shared_rounded,
                              color: navyPrimary,
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Google Drive Dispatches',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: navyDark,
                                  ),
                                ),
                                Text(
                                  driveState.folderName,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.of(bottomSheetContext).pop(),
                        ),
                      ],
                    ),
                  ),

                  // Actions bar inside modal
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: driveState.isLoading
                              ? null
                              : () async {
                                  // Create a sample media file in temp directory to test upload
                                  final tempDir = Directory.systemTemp.createTempSync('drive_upload_');
                                  final tempFile = File('${tempDir.path}/dispatch_photo_${DateTime.now().millisecondsSinceEpoch}.jpg');
                                  tempFile.writeAsStringSync('sample-photo-data');

                                  final uploaded = await watchRef
                                      .read(googleDriveStateProvider.notifier)
                                      .uploadMedia(
                                        localFilePath: tempFile.path,
                                        mediaType: MediaType.image,
                                      );

                                  if (uploaded != null && ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Uploaded "${uploaded.fileName}" to Google Drive!',
                                        ),
                                        backgroundColor: const Color(0xFF16A34A),
                                      ),
                                    );
                                  }
                                },
                          icon: const Icon(Icons.cloud_upload_rounded, size: 16),
                          label: const Text(
                            'Upload Test Dispatch',
                            style: TextStyle(fontSize: 12),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: navyPrimary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          tooltip: 'Refresh files',
                          onPressed: () => watchRef
                              .read(googleDriveStateProvider.notifier)
                              .refreshFiles(),
                        ),
                      ],
                    ),
                  ),

                  // File List
                  Expanded(
                    child: driveState.files.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.cloud_queue_rounded,
                                  size: 48,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'No dispatches uploaded yet.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Use "Upload Test Dispatch" or attach media in Submit News.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: driveState.files.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (c, index) {
                              final file = driveState.files[index];
                              return ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: _getMediaColor(file.mediaType).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    _getMediaIcon(file.mediaType),
                                    color: _getMediaColor(file.mediaType),
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  file.fileName,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: navyDark,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${file.mediaType.toValue().toUpperCase()} • ${_formatDate(file.createdAt)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: Color(0xFFDC2626),
                                    size: 20,
                                  ),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: c,
                                      builder: (diagCtx) => AlertDialog(
                                        title: const Text('Delete from Drive?'),
                                        content: Text(
                                          'Are you sure you want to delete "${file.fileName}" from your Google Drive?',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(diagCtx).pop(false),
                                            child: const Text('Cancel'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () =>
                                                Navigator.of(diagCtx).pop(true),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFFDC2626),
                                              foregroundColor: Colors.white,
                                            ),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );

                                    if (confirm == true && file.driveFileId != null) {
                                      await watchRef
                                          .read(googleDriveStateProvider.notifier)
                                          .deleteMedia(file.driveFileId!);
                                    }
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  IconData _getMediaIcon(MediaType type) {
    switch (type) {
      case MediaType.image:
        return Icons.image_rounded;
      case MediaType.video:
        return Icons.videocam_rounded;
      case MediaType.audio:
        return Icons.mic_rounded;
      case MediaType.thumbnail:
        return Icons.photo_size_select_actual_rounded;
      case MediaType.document:
        return Icons.description_rounded;
    }
  }

  Color _getMediaColor(MediaType type) {
    switch (type) {
      case MediaType.image:
        return const Color(0xFF2563EB);
      case MediaType.video:
        return const Color(0xFF7C3AED);
      case MediaType.audio:
        return const Color(0xFFE11D48);
      case MediaType.thumbnail:
        return const Color(0xFFD97706);
      case MediaType.document:
        return const Color(0xFF0D9488);
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
    required Color navyPrimary,
    Color? valueColor,
    bool isMonospace = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: navyPrimary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: navyPrimary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: isMonospace ? 'monospace' : null,
                    color: valueColor ?? const Color(0xFF091B2E),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(
      height: 1,
      thickness: 1,
      indent: 54,
      endIndent: 16,
      color: Color(0xFFF1F5F9),
    );
  }
}
