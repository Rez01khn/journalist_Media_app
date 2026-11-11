import 'package:flutter_test/flutter_test.dart';
import 'package:journalist_app_1/models/news.dart';
import 'package:journalist_app_1/models/news_draft.dart';
import 'package:journalist_app_1/models/news_media.dart';
import 'package:journalist_app_1/models/news_status.dart';
import 'package:journalist_app_1/models/reporter.dart';
import 'package:journalist_app_1/repositories/mock/mock_repositories.dart';

void main() {
  group('Domain Models & Architecture Tests', () {
    test('NewsStatus serialization and color mapping', () {
      expect(NewsStatus.fromString('published'), equals(NewsStatus.published));
      expect(NewsStatus.fromString('pending_review'), equals(NewsStatus.pending));
      expect(NewsStatus.fromString('approved'), equals(NewsStatus.approved));
      expect(NewsStatus.fromString('rejected'), equals(NewsStatus.rejected));
      expect(NewsStatus.fromString('draft'), equals(NewsStatus.draft));
      expect(NewsStatus.published.displayName, equals('Published'));
    });

    test('Reporter model serialization to and from JSON', () {
      final reporter = Reporter(
        id: 'rep-01',
        reporterCode: 'REP-2026-084',
        fullName: 'Rezwan Karim',
        email: 'rezwan.karim@newsdesk.bd',
        phoneNumber: '+880 1712-345678',
        designation: 'Senior Field Correspondent',
        assignedArea: 'Dhaka Central',
        googleAccountEmail: 'rezwan.field@gmail.com',
        createdAt: DateTime(2026, 1, 1),
      );

      final json = reporter.toJson();
      final parsed = Reporter.fromJson(json);

      expect(parsed.id, equals('rep-01'));
      expect(parsed.reporterCode, equals('REP-2026-084'));
      expect(parsed.googleAccountEmail, equals('rezwan.field@gmail.com'));
    });

    test('NewsMedia preserves Google Drive file references', () {
      final media = NewsMedia(
        id: 'media-01',
        fileName: 'spot_photo.jpg',
        driveFileId: 'drive-123456',
        driveWebViewLink: 'https://drive.google.com/file/d/drive-123456/view',
        mimeType: 'image/jpeg',
        mediaType: MediaType.image,
        isUploadedToDrive: true,
        reporterGoogleAccountEmail: 'reporter@gmail.com',
        createdAt: DateTime.now(),
      );

      final json = media.toJson();
      final parsed = NewsMedia.fromJson(json);

      expect(parsed.driveFileId, equals('drive-123456'));
      expect(parsed.isUploadedToDrive, isTrue);
      expect(parsed.reporterGoogleAccountEmail, equals('reporter@gmail.com'));
    });

    test('NewsDraft stores local offline information and AI metadata', () {
      final draft = NewsDraft(
        id: 'draft-01',
        reporterId: 'rep-01',
        headline: 'Local breaking report',
        category: 'National',
        location: 'Motijheel',
        incidentDetails: 'Incident summary from the scene',
        isAiAssisted: true,
        aiAssistedHeadline: 'Suggested AI Headline',
        lastSavedAt: DateTime.now(),
      );

      final json = draft.toJson();
      final parsed = NewsDraft.fromJson(json);

      expect(parsed.headline, equals('Local breaking report'));
      expect(parsed.isAiAssisted, isTrue);
      expect(parsed.aiAssistedHeadline, equals('Suggested AI Headline'));
    });

    test('News model handles Laravel website export flags without media copy', () {
      final news = News(
        id: 'news-01',
        trackingCode: 'REP-101',
        reporterId: 'rep-01',
        reporterName: 'Rezwan Karim',
        headline: 'Finalized story',
        category: 'Infrastructure',
        location: 'Dhaka',
        incidentDetails: 'Verified details',
        status: NewsStatus.published,
        submittedAt: DateTime.now(),
        isExportedToLaravelWebsite: true,
        laravelWebsitePostId: 'wp-post-987',
      );

      final json = news.toJson();
      final parsed = News.fromJson(json);

      expect(parsed.isExportedToLaravelWebsite, isTrue);
      expect(parsed.laravelWebsitePostId, equals('wp-post-987'));
    });

    test('Mock repositories return valid contracts', () async {
      final authRepo = MockAuthRepository();
      final newsRepo = MockNewsRepository();
      final draftRepo = MockDraftRepository();

      final reporter = await authRepo.getCurrentReporter();
      expect(reporter, isNotNull);
      expect(reporter!.reporterCode, equals('REP-2026-084'));

      final newsList = await newsRepo.getReporterNews(reporterId: reporter.id);
      expect(newsList.length, equals(4));

      final counts = await newsRepo.getNewsStatusCounts(reporterId: reporter.id);
      expect(counts[NewsStatus.published], equals(1));

      final drafts = await draftRepo.getAllDrafts(reporterId: reporter.id);
      expect(drafts.length, equals(1));
    });
  });
}

