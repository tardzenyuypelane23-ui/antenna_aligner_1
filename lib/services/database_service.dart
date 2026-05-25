import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:antenna_aligner/models/access_point.dart';

class DatabaseService {
  DatabaseService._internal();
  static final DatabaseService instance = DatabaseService._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'antenna_aligner.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE access_points (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            altitude REAL NOT NULL
          )
        ''');
      },
    );
  }

  Future<List<AccessPoint>> getAccessPoints() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('access_points');
    return maps.map((map) => AccessPoint.fromMap(map)).toList();
  }

  Future<void> addAccessPoint(AccessPoint accessPoint) async {
    final db = await database;
    await db.insert(
      'access_points',
      accessPoint.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeAccessPoint(int id) async {
    final db = await database;
    await db.delete(
      'access_points',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateAccessPoint(AccessPoint accessPoint) async {
    final db = await database;
    await db.update(
      'access_points',
      accessPoint.toMap(),
      where: 'id = ?',
      whereArgs: [accessPoint.id],
    );
  }
}
