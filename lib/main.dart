import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models/transaction_model.dart';
import 'services/db_helper.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FinanceApp());
}

class FinanceApp extends StatelessWidget {
  const FinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Controle Financeiro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<TransactionItem> _transactions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshTransactions();
  }

  Future<void> _refreshTransactions() async {
    setState(() => _isLoading = true);
    final data = await DBHelper.instance.getAllTransactions();
    setState(() {
      _transactions = data;
      _isLoading = false;
    });
  }

  double get _totalIncome => _transactions
      .where((t) => t.type == TransactionType.income)
      .fold(0.0, (sum, t) => sum + t.amount);

  double get _totalExpense => _transactions
      .where((t) => t.type == TransactionType.expense)
      .fold(0.0, (sum, t) => sum + t.amount);

  double get _currentBalance => _totalIncome - _totalExpense;

  void _openAddTransactionModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => AddTransactionModal(onAdded: _refreshTransactions),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formatCurrency = NumberFormat.simpleCurrency(locale: 'pt_BR');

    return Scaffold(
      appBar: AppBar(title: const Text('Minhas Finanças')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSummaryCard(formatCurrency),
                Expanded(
                  child: _transactions.isEmpty
                      ? const Center(child: Text('Nenhuma transação registrada.'))
                      : ListView.builder(
                          itemCount: _transactions.length,
                          itemBuilder: (ctx, index) {
                            final item = _transactions[index];
                            final isIncome = item.type == TransactionType.income;
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isIncome
                                    ? Colors.green.withOpacity(0.2)
                                    : Colors.red.withOpacity(0.2),
                                child: Icon(
                                  isIncome ? Icons.arrow_upward : Icons.arrow_downward,
                                  color: isIncome ? Colors.green : Colors.red,
                                ),
                              ),
                              title: Text(item.title),
                              subtitle: Text(
                                  '${item.category} • ${DateFormat('dd/MM/yyyy').format(item.date)}'),
                              trailing: Text(
                                '${isIncome ? '+' : '-'} ${formatCurrency.format(item.amount)}',
                                style: TextStyle(
                                  color: isIncome ? Colors.green : Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddTransactionModal,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildSummaryCard(NumberFormat formatter) {
    return Card(
      margin: const EdgeInsets.all(16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text('Saldo Atual', style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(
              formatter.format(_currentBalance),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text('Receitas', style: TextStyle(color: Colors.green)),
                    Text(formatter.format(_totalIncome),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                Column(
                  children: [
                    const Text('Despesas', style: TextStyle(color: Colors.redAccent)),
                    Text(formatter.format(_totalExpense),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AddTransactionModal extends StatefulWidget {
  final VoidCallback onAdded;
  const AddTransactionModal({super.key, required this.onAdded});

  @override
  State<AddTransactionModal> createState() => _AddTransactionModalState();
}

class _AddTransactionModalState extends State<AddTransactionModal> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _categoryController = TextEditingController();
  TransactionType _type = TransactionType.expense;

  void _submit() async {
    final title = _titleController.text.trim();
    final amount = double.tryParse(_amountController.text.replaceAll(',', '.')) ?? 0.0;
    final category = _categoryController.text.trim();

    if (title.isEmpty || amount <= 0 || category.isEmpty) return;

    final item = TransactionItem(
      title: title,
      amount: amount,
      date: DateTime.now(),
      category: category,
      type: _type,
    );

    await DBHelper.instance.insertTransaction(item);
    widget.onAdded();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: 'Descrição (ex: Supermercado)'),
          ),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Valor (R\$)'),
          ),
          TextField(
            controller: _categoryController,
            decoration: const InputDecoration(labelText: 'Categoria (ex: Alimentação)'),
          ),
          const SizedBox(height: 12),
          SegmentedButton<TransactionType>(
            segments: const [
              ButtonSegment(value: TransactionType.expense, label: Text('Despesa')),
              ButtonSegment(value: TransactionType.income, label: Text('Receita')),
            ],
            selected: {_type},
            onSelectionChanged: (newVal) => setState(() => _type = newVal.first),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _submit,
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(45)),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}
