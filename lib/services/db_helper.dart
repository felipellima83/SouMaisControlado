import 'package:supabase_flutter/supabase_flutter.dart';
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

  Map<String, dynamic> toMap(String userId) {
    return {
      'user_id': userId,
      'name': name,
      'is_credit_card': isCreditCard,
      'closing_day': closingDay,
      'due_day': dueDay,
    };
  }

  factory AccountInfo.fromMap(Map<String, dynamic> map) {
    final rawCard = map['is_credit_card'] ?? map['isCreditCard'];
    final isCard = rawCard is bool ? rawCard : (rawCard == 1);

    return AccountInfo(
      name: map['name'] as String,
      isCreditCard: isCard,
      closingDay: (map['closing_day'] ?? map['closingDay'] ?? 1) as int,
      dueDay: (map['due_day'] ?? map['dueDay'] ?? 10) as int,
    );
  }
}

class DBHelper {
  static final DBHelper instance = DBHelper._init();
  DBHelper._init();

  SupabaseClient get _client => Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  // Gestão de Contas e Cartões
  Future<List<AccountInfo>> getAccountsMeta() async {
    final res = await _client
        .from('accounts_meta')
        .select()
        .order('name', ascending: true);

    final list = (res as List)
        .map((m) => AccountInfo.fromMap(Map<String, dynamic>.from(m)))
        .toList();

    // Cria contas padrão no primeiro acesso do usuário
    if (list.isEmpty) {
      final defaults = [
        AccountInfo(name: 'Conta Principal'),
        AccountInfo(name: 'Carteira / Dinheiro'),
        AccountInfo(
          name: 'Cartão de Crédito',
          isCreditCard: true,
          closingDay: 25,
          dueDay: 5,
        ),
      ];
      for (final acc in defaults) {
        await saveAccountMeta(acc);
      }
      return defaults;
    }

    return list;
  }

  Future<void> saveAccountMeta(AccountInfo info) async {
    await _client
        .from('accounts_meta')
        .upsert(info.toMap(_userId), onConflict: 'user_id,name');
  }

  // Transações
  Future<List<TransactionItem>> getAllTransactions() async {
    final res = await _client
        .from('transactions')
        .select()
        .order('date', ascending: true);

    return (res as List)
        .map((m) => TransactionItem.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<void> insertTransaction(TransactionItem item) async {
    final map = item.toMap();
    map['user_id'] = _userId;
    await _client.from('transactions').insert(map);
  }

  Future<void> insertMultipleTransactions(List<TransactionItem> items) async {
    if (items.isEmpty) return;
    final rows = items.map((item) {
      final map = item.toMap();
      map['user_id'] = _userId;
      return map;
    }).toList();
    await _client.from('transactions').insert(rows);
  }

  Future<void> updateTransaction(TransactionItem item) async {
    if (item.id == null) return;
    await _client
        .from('transactions')
        .update(item.toMap())
        .eq('id', item.id!);
  }

  Future<void> toggleTransactionStatus(int id, bool isCompleted) async {
    await _client
        .from('transactions')
        .update({'is_completed': isCompleted})
        .eq('id', id);
  }

  Future<void> deleteTransaction(int id) async {
    await _client.from('transactions').delete().eq('id', id);
  }

  Future<void> deleteGroupAll(String groupId) async {
    await _client.from('transactions').delete().eq('group_id', groupId);
  }

  Future<void> deleteGroupFromDate(String groupId, DateTime fromDate) async {
    await _client
        .from('transactions')
        .delete()
        .eq('group_id', groupId)
        .gte('date', fromDate.toIso8601String());
  }

  Future<void> renameAccount(String oldName, String newName) async {
    await _client
        .from('accounts_meta')
        .update({'name': newName})
        .eq('name', oldName);
    await _client
        .from('transactions')
        .update({'account': newName})
        .eq('account', oldName);
  }

  Future<void> deleteAccountAndTransactions(String accountName) async {
    await _client.from('accounts_meta').delete().eq('name', accountName);
    await _client.from('transactions').delete().eq('account', accountName);
  }

  Future<void> replaceAllTransactions(List<TransactionItem> items) async {
    await _client.from('transactions').delete().eq('user_id', _userId);
    await insertMultipleTransactions(items);
  }
}
