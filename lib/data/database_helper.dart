import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('notes_manager.db');
    await _ensureRequiredColumns(_database!);
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute(
      'CREATE TABLE subjects (id TEXT PRIMARY KEY, name TEXT NOT NULL, emoji TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE documents (id TEXT PRIMARY KEY, subject_id TEXT NOT NULL, title TEXT NOT NULL, type TEXT NOT NULL, date TEXT NOT NULL, pdf_path TEXT, content TEXT)',
    );
    await db.execute(
      'CREATE TABLE strokes (id TEXT PRIMARY KEY, document_id TEXT NOT NULL, page_index INTEGER NOT NULL, points_json TEXT NOT NULL, color_value INTEGER NOT NULL, stroke_width REAL NOT NULL, tool_type TEXT NOT NULL)',
    );
  }

  /// Ensures existing databases have `pdf_path` and `content` in `documents`
  /// and `color` in `subjects` without losing any existing data.
  Future<void> _ensureRequiredColumns(Database db) async {
    final subjectCols = await db.rawQuery('PRAGMA table_info(subjects)');
    final subjectColNames = subjectCols.map((c) => c['name'] as String).toSet();
    if (!subjectColNames.contains('color')) {
      await db.execute('ALTER TABLE subjects ADD COLUMN color INTEGER');
    }

    final docCols = await db.rawQuery('PRAGMA table_info(documents)');
    final docColNames = docCols.map((c) => c['name'] as String).toSet();
    if (!docColNames.contains('pdf_path')) {
      await db.execute('ALTER TABLE documents ADD COLUMN pdf_path TEXT');
    }
    if (!docColNames.contains('content')) {
      await db.execute('ALTER TABLE documents ADD COLUMN content TEXT');
    }
  }

  // --- SUBJECTS (Folders) ---
  Future<void> insertSubject(Map<String, dynamic> subject) async {
    final db = await instance.database;
    await db.insert('subjects', subject, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getSubjects() async {
    final db = await instance.database;
    return await db.query('subjects', orderBy: 'rowid DESC');
  }

  // --- DOCUMENTS (PDFs & Blank Notes) ---
  Future<void> insertDocument(Map<String, dynamic> doc) async {
    final db = await instance.database;
    await db.insert('documents', doc, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getDocumentsForSubject(String subjectId) async {
    final db = await instance.database;
    return await db.query(
      'documents',
      where: 'subject_id = ?',
      whereArgs: [subjectId],
      orderBy: 'date DESC',
    );
  }

  Future<void> deleteDocument(String id) async {
    final db = await instance.database;
    await db.delete('documents', where: 'id = ?', whereArgs: [id]);
    await db.delete('strokes', where: 'document_id = ?', whereArgs: [id]);
  }

  Future<int> deleteSubject(String subjectId) async {
    final db = await instance.database;
    final docs = await getDocumentsForSubject(subjectId);
    for (final doc in docs) {
      final docId = doc['id'].toString();
      await db.delete('strokes', where: 'document_id = ?', whereArgs: [docId]);
    }
    await db.delete('documents', where: 'subject_id = ?', whereArgs: [subjectId]);
    return await db.delete('subjects', where: 'id = ?', whereArgs: [subjectId]);
  }
}