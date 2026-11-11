import 'package:journalist_app_1/models/news.dart';
import 'package:journalist_app_1/models/news_status.dart';

/// Abstract contract for fetching submitted news records and tracking statuses.
///
/// Designed to interface with the independent MySQL app backend via REST API.
abstract class NewsRepository {
  /// Fetches a list of news submitted by the specified reporter, optionally filtered by status.
  Future<List<News>> getReporterNews({
    required String reporterId,
    NewsStatus? statusFilter,
  });

  /// Retrieves a single news story by its primary identifier.
  Future<News?> getNewsById(String newsId);

  /// Fetches aggregated count of stories by status for the reporter dashboard.
  Future<Map<NewsStatus, int>> getNewsStatusCounts({
    required String reporterId,
  });
}

