import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Database service managing SQLite instance and table creation
/// for local offline persistence.
class DatabaseService {
  static const String _databaseName = 'journalist_portal.db';
  static const int _databaseVersion = 3;

  static const String tableNewsDrafts = 'news_drafts';

  Database? _db;

  /// Custom database instance (used for dependency injection and tests)
  DatabaseService([this._db]);

  Future<Database> get database async {
    if (_db != null) {
      return _db!;
    }
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final dbPath = p.join(databasesPath, _databaseName);

    return await openDatabase(
      dbPath,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableNewsDrafts (
        id TEXT PRIMARY KEY,
        reporter_id TEXT NOT NULL,
        headline TEXT,
        category TEXT,
        location TEXT,
        incident_details TEXT,
        media_attachments TEXT,
        voice_dispatch TEXT,
        ai_assisted_headline TEXT,
        ai_assisted_body TEXT,
        is_ai_assisted INTEGER DEFAULT 0,
        last_saved_at TEXT NOT NULL,
        is_synced_with_drive INTEGER DEFAULT 0,
        drive_folder_id TEXT,
        drive_file_id TEXT,
        drive_sync_status TEXT DEFAULT 'pending',
        last_synced_at TEXT,
        sync_error_message TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute(
          'ALTER TABLE $tableNewsDrafts ADD COLUMN drive_file_id TEXT',
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE $tableNewsDrafts ADD COLUMN drive_sync_status TEXT DEFAULT 'pending'",
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE $tableNewsDrafts ADD COLUMN last_synced_at TEXT',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE $tableNewsDrafts ADD COLUMN sync_error_message TEXT',
        );
      } catch (_) {}
    }
    if (oldVersion < 3) {
      try {
        await db.execute(
          'ALTER TABLE $tableNewsDrafts ADD COLUMN drive_folder_id TEXT',
        );
      } catch (_) {}
    }
  }

  /// Closes database connection
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}
