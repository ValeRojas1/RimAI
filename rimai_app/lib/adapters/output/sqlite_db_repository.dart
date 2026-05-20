import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/actividad_local.dart';
import '../../application/ports/local_db_port.dart';

class SqliteDbRepository implements ILocalDbPort {
  static Database? _database;
  final _uuid = const Uuid();

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
    CREATE TABLE actividades_pendientes (
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

  @override
  Future<void> saveActividad(ActividadLocal actividad) async {
    final db = await database;
    
    // SQLite no guarda listas directamente, convertimos a String (ej. CSV o JSON)
    final detonantes = actividad.detonantesPresentados.join(',');
    
    await db.insert('actividades_pendientes', {
      'id': actividad.id ?? _uuid.v4(),
      'patient_id': actividad.patientId,
      'actividad_id': actividad.actividadId,
      'plan_id': actividad.planId,
      'tiempo_empleado_segundos': actividad.tiempoEmpleadoSegundos,
      'nivel_apoyo_requerido': actividad.nivelApoyoRequerido,
      'observaciones': actividad.observaciones,
      'detonantes_presentados': detonantes,
      'completada': actividad.completada ? 1 : 0,
      'timestamp_local': actividad.timestampLocal.toIso8601String(),
    });
  }

  @override
  Future<List<ActividadLocal>> getActividadesPendientes() async {
    final db = await database;
    final maps = await db.query('actividades_pendientes', orderBy: 'timestamp_local ASC'); // FIFO

    if (maps.isNotEmpty) {
      return maps.map((map) {
        return ActividadLocal(
          id: map['id'] as String,
          patientId: map['patient_id'] as int,
          actividadId: map['actividad_id'] as String,
          planId: map['plan_id'] as int,
          tiempoEmpleadoSegundos: map['tiempo_empleado_segundos'] as int,
          nivelApoyoRequerido: map['nivel_apoyo_requerido'] as int,
          observaciones: map['observaciones'] as String,
          detonantesPresentados: (map['detonantes_presentados'] as String).isEmpty 
            ? [] 
            : (map['detonantes_presentados'] as String).split(','),
          completada: (map['completada'] as int) == 1,
          timestampLocal: DateTime.parse(map['timestamp_local'] as String),
        );
      }).toList();
    } else {
      return [];
    }
  }

  @override
  Future<void> deleteActividades(List<String> ids) async {
    final db = await database;
    for (String id in ids) {
      await db.delete(
        'actividades_pendientes',
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }
}
