import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/transaction_model.dart';

class DBHelper {
  static final DBHelper instance = DBHelper._init();
  static Database? _database;

  DBHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('finance.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        category TEXT NOT NULL,
        account TEXT NOT NULL DEFAULT 'Conta Principal',
        type TEXT NOT NULL
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute("ALTER TABLE transactions ADD COLUMN account TEXT NOT NULL DEFAULT 'Conta Principal'");
    }
  }

  Future<int> insertTransaction(TransactionItem item) async {
    final db = await instance.database;
    return await db.insert('transactions', item.toMap());
  }

  Future<int> updateTransaction(TransactionItem item) async {
    final db = await instance.database;
    return await db.update(
      'transactions',
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<List<TransactionItem>> getAllTransactions() async {
    final db = await instance.database;
    final result = await db.query('transactions', orderBy: 'date DESC');
    return result.map((json) => TransactionItem.fromMap(json)).toList();
  }

  Future<int> deleteTransaction(int id) async {
    final db = await instance.database;
    return await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> replaceAllTransactions(List<TransactionItem> items) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.delete('transactions');
      for (final item in items) {
        await txn.insert('transactions', item.toMap());
      }
    });
  }
}
