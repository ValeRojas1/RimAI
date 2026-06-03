import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../../application/ports/local_db_port.dart';
import '../../domain/entities/actividad_local.dart';

class SqliteDbRepository implements ILocalDbPort {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('rimai_offline.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        await _createPendingSessionsTable(db);
      },
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await _createLegacyActivitiesTable(db);
    await _createPendingSessionsTable(db);
  }

  Future<void> _createLegacyActivitiesTable(Database db) async {
    await db.execute('''
    CREATE TABLE IF NOT EXISTS actividades_pendientes (
      id TEXT PRIMARY KEY,
      patient_id INTEGER,
      actividad_id TEXT,
      plan_id INTEGER,
      tiempo_empleado_segundos INTEGER,
      nivel_apoyo_requerido INTEGER,
      observaciones TEXT,
      detonantes_presentados TEXT,
      completada INTEGER,
      timestamp_local TEXT
    )
    ''');
  }

  Future<void> _createPendingSessionsTable(Database db) async {
    await db.execute('''
    CREATE TABLE IF NOT EXISTS sesiones_pendientes_sync (
      id TEXT PRIMARY KEY,
      nino_id TEXT NOT NULL,
      plan_id TEXT NOT NULL,
      actividad_id TEXT NOT NULL,
      aciertos INTEGER NOT NULL,
      repeticiones INTEGER NOT NULL,
      tiempo_respuesta_segundos INTEGER NOT NULL,
      nivel_ayuda_requerido INTEGER NOT NULL,
      nivel_dificultad_usado TEXT NOT NULL,
      observaciones TEXT,
      timestamp_local TEXT NOT NULL,
      sync_attempts INTEGER NOT NULL DEFAULT 0,
      last_error TEXT
    )
    ''');
  }

  @override
  Future<void> saveActividad(ActividadLocal actividad) async {
    final db = await database;

    await db.insert(
      'sesiones_pendientes_sync',
      actividad.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<ActividadLocal>> getActividadesPendientes() async {
    final db = await database;
    final maps = await db.query(
      'sesiones_pendientes_sync',
      orderBy: 'timestamp_local ASC',
    );

    return maps.map(ActividadLocal.fromJson).toList();
  }

  @override
  Future<void> deleteActividades(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.delete(
          'sesiones_pendientes_sync',
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    });
  }
}
