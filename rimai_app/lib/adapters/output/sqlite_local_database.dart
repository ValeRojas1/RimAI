import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class SQLiteLocalDatabase {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('rimai_offline.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE patient_profiles_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        payload TEXT NOT NULL,
        is_synced INTEGER DEFAULT 0
      )
    ''');
  }

  Future<void> queuePatientProfile(String jsonPayload) async {
    final db = await database;
    await db.insert('patient_profiles_queue', {'payload': jsonPayload});
  }

  Future<List<Map<String, dynamic>>> getUnsyncedProfiles() async {
    final db = await database;
    return await db.query('patient_profiles_queue', where: 'is_synced = ?', whereArgs: [0]);
  }

  Future<void> markAsSynced(int id) async {
    final db = await database;
    await db.update('patient_profiles_queue', {'is_synced': 1}, where: 'id = ?', whereArgs: [id]);
  }
}
