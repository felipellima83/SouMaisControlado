enum TransactionType { income, expense }

class TransactionItem {
  final int? id;
  final String title;
  final double amount;
  final DateTime date;
  final String category;
  final String account;
  final String? groupId;
  final bool isCompleted;
  final TransactionType type;

  TransactionItem({
    this.id,
    required this.title,
    required this.amount,
    required this.date,
    required this.category,
    this.account = 'Conta Principal',
    this.groupId,
    this.isCompleted = true,
    required this.type,
  });

  Map<String, dynamic> toMap({bool includeId = false}) {
    final map = <String, dynamic>{
      'title': title,
      'amount': amount,
      'date': date.toIso8601String(),
      'category': category,
      'account': account,
      'group_id': groupId,
      'is_completed': isCompleted,
      'type': type.name,
    };
    if (includeId && id != null) {
      map['id'] = id;
    }
    return map;
  }

  factory TransactionItem.fromMap(Map<String, dynamic> map) {
    final rawCompleted = map['is_completed'] ?? map['isCompleted'];
    bool completed = true;
    if (rawCompleted is bool) {
      completed = rawCompleted;
    } else if (rawCompleted is int) {
      completed = rawCompleted == 1;
    }

    return TransactionItem(
      id: map['id'] is int ? map['id'] as int : int.tryParse('${map['id']}'),
      title: map['title'] as String? ?? '',
      amount: (map['amount'] as num).toDouble(),
      date: DateTime.parse(map['date'] as String).toLocal(),
      category: map['category'] as String? ?? 'Outros',
      account: map['account'] as String? ?? 'Conta Principal',
      groupId: (map['group_id'] ?? map['groupId']) as String?,
      isCompleted: completed,
      type: (map['type'] as String) == 'income'
          ? TransactionType.income
          : TransactionType.expense,
    );
  }
}
