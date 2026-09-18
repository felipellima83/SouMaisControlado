enum TransactionType { income, expense }

class TransactionItem {
  final int? id;
  final String title;
  final double amount;
  final DateTime date;
  final String category;
  final String account;
  final String? groupId; // Identificador da série (parcelada ou recorrente)
  final TransactionType type;

  TransactionItem({
    this.id,
    required this.title,
    required this.amount,
    required this.date,
    required this.category,
    this.account = 'Conta Principal',
    this.groupId,
    required this.type,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'amount': amount,
      'date': date.toIso8601String(),
      'category': category,
      'account': account,
      'groupId': groupId,
      'type': type == TransactionType.income ? 'income' : 'expense',
    };
  }

  factory TransactionItem.fromMap(Map<String, dynamic> map) {
    return TransactionItem(
      id: map['id'] as int?,
      title: map['title'] as String,
      amount: (map['amount'] as num).toDouble(),
      date: DateTime.parse(map['date'] as String),
      category: map['category'] as String,
      account: (map['account'] as String?) ?? 'Conta Principal',
      groupId: map['groupId'] as String?,
      type: map['type'] == 'income' ? TransactionType.income : TransactionType.expense,
    );
  }
}
