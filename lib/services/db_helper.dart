import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/transaction_model.dart';

class AccountInfo {
  final String name;
  final bool isCreditCard;
  final int closingDay;
  final int dueDay;

  AccountInfo({
    required this.name,
    this.isCreditCard = false,
    this.closingDay = 1,
    this.dueDay = 10,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'isCreditCard': isCreditCard ? 1 : 0,
      'closingDay': closingDay,
      'dueDay': dueDay,
    };
  }

  factory AccountInfo.fromMap(Map<String, dynamic> map) {
    return AccountInfo(
      name: map['name'] as String,
      isCreditCard: (map['isCreditCard'] as int? ?? 0) == 1,
      closingDay: map['closingDay'] as int? ?? 1,
      dueDay: map['dueDay'] as int? ?? 10,
    );
  }
}

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
      version: 5,
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
        groupId TEXT,
        isCompleted INTEGER NOT NULL DEFAULT 1,
        type TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE accounts_meta (
        name TEXT PRIMARY KEY,
        isCreditCard INTEGER NOT NULL DEFAULT 0,
        closingDay INTEGER NOT NULL DEFAULT 1,
        dueDay INTEGER NOT NULL DEFAULT 10
      )
    ''');

    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // Contas iniciais padrão
    await db.insert('accounts_meta', AccountInfo(name: 'Conta Principal').toMap());
    await db.insert('accounts_meta', AccountInfo(name: 'Carteira / Dinheiro').toMap());
    await db.insert('accounts_meta', AccountInfo(name: 'Cartão de Crédito', isCreditCard: true, closingDay: 25, dueDay: 5).toMap());
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute("ALTER TABLE transactions ADD COLUMN account TEXT NOT NULL DEFAULT 'Conta Principal'");
    }
    if (oldVersion < 3) {
      await db.execute("ALTER TABLE transactions ADD COLUMN groupId TEXT");
    }
    if (oldVersion < 4) {
      await db.execute("ALTER TABLE transactions ADD COLUMN isCompleted INTEGER NOT NULL DEFAULT 1");
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS accounts_meta (
          name TEXT PRIMARY KEY,
          isCreditCard INTEGER NOT NULL DEFAULT 0,
          closingDay INTEGER NOT NULL DEFAULT 1,
          dueDay INTEGER NOT NULL DEFAULT 10
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }
  }

  // Definições gerais da aplicação
  Future<void> setSetting(String key, String value) async {
    final db = await instance.database;
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    final db = await instance.database;
    final res = await db.query('app_settings', where: 'key = ?', whereArgs: [key]);
    if (res.isNotEmpty) {
      return res.first['value'] as String?;
    }
    return null;
  }

  // Gestão de Contas e Cartões
  Future<List<AccountInfo>> getAccountsMeta() async {
    final db = await instance.database;
    final res = await db.query('accounts_meta');
    return res.map((m) => AccountInfo.fromMap(m)).toList();
  }

  Future<void> saveAccountMeta(AccountInfo info) async {
    final db = await instance.database;
    await db.insert(
      'accounts_meta',
      info.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> insertTransaction(TransactionItem item) async {
    final db = await instance.database;
    return await db.insert('transactions', item.toMap());
  }

  Future<void> insertMultipleTransactions(List<TransactionItem> items) async {
    final db = await instance.database;
    final batch = db.batch();
    for (final item in items) {
      batch.insert('transactions', item.toMap());
    }
    await batch.commit(noResult: true);
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

  Future<int> toggleTransactionStatus(int id, bool isCompleted) async {
    final db = await instance.database;
    return await db.update(
      'transactions',
      {'isCompleted': isCompleted ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<TransactionItem>> getAllTransactions() async {
    final db = await instance.database;
    final result = await db.query('transactions', orderBy: 'date ASC');
    return result.map((json) => TransactionItem.fromMap(json)).toList();
  }

  Future<int> deleteTransaction(int id) async {
    final db = await instance.database;
    return await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteGroupAll(String groupId) async {
    final db = await instance.database;
    return await db.delete(
      'transactions',
      where: 'groupId = ?',
      whereArgs: [groupId],
    );
  }

  Future<int> deleteGroupFromDate(String groupId, DateTime fromDate) async {
    final db = await instance.database;
    return await db.delete(
      'transactions',
      where: 'groupId = ? AND date >= ?',
      whereArgs: [groupId, fromDate.toIso8601String()],
    );
  }

  Future<int> renameAccount(String oldName, String newName) async {
    final db = await instance.database;
    await db.rawUpdate('UPDATE accounts_meta SET name = ? WHERE name = ?', [newName, oldName]);
    return await db.rawUpdate(
      'UPDATE transactions SET account = ? WHERE account = ?',
      [newName, oldName],
    );
  }

  Future<int> deleteAccountAndTransactions(String accountName) async {
    final db = await instance.database;
    await db.delete('accounts_meta', where: 'name = ?', whereArgs: [accountName]);
    return await db.delete(
      'transactions',
      where: 'account = ?',
      whereArgs: [accountName],
    );
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
