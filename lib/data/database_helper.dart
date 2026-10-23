import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('notes_manager.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('CREATE TABLE subjects (id TEXT PRIMARY KEY, name TEXT NOT NULL, emoji TEXT NOT NULL)');
    await db.execute('CREATE TABLE documents (id TEXT PRIMARY KEY, subject_id TEXT NOT NULL, title TEXT NOT NULL, type TEXT NOT NULL, date TEXT NOT NULL)');
    await db.execute('CREATE TABLE strokes (id TEXT PRIMARY KEY, document_id TEXT NOT NULL, page_index INTEGER NOT NULL, points_json TEXT NOT NULL, color_value INTEGER NOT NULL, stroke_width REAL NOT NULL, tool_type TEXT NOT NULL)');
  }

  // --- SUBJECTS (Folders) ---
  Future<void> insertSubject(Map<String, dynamic> subject) async {
    final db = await instance.database;
    await db.insert('subjects', subject, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getSubjects() async {
    final db = await instance.database;
    return await db.query('subjects');
  }

  // --- DOCUMENTS (PDFs & Blank Notes) ---
  Future<void> insertDocument(Map<String, dynamic> doc) async {
    final db = await instance.database;
    await db.insert('documents', doc, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getDocumentsForSubject(String subjectId) async {
    final db = await instance.database;
    return await db.query('documents', where: 'subject_id = ?', whereArgs: [subjectId], orderBy: 'date DESC');
  }

  Future<void> deleteDocument(String id) async {
    final db = await instance.database;
    await db.delete('documents', where: 'id = ?', whereArgs: [id]);
    await db.delete('strokes', where: 'document_id = ?', whereArgs: [id]); // Deletes the ink too!
  }
}