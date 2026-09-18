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
  List<TransactionItem> _allTransactions = [];
  bool _isLoading = true;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    _refreshTransactions();
  }

  Future<void> _refreshTransactions() async {
    setState(() => _isLoading = true);
    final data = await DBHelper.instance.getAllTransactions();
    setState(() {
      _allTransactions = data;
      _isLoading = false;
    });
  }

  // Filtra transações apenas do mês/ano selecionado
  List<TransactionItem> get _filteredTransactions {
    return _allTransactions.where((t) {
      return t.date.year == _selectedMonth.year && t.date.month == _selectedMonth.month;
    }).toList();
  }

  double get _totalIncome => _filteredTransactions
      .where((t) => t.type == TransactionType.income)
      .fold(0.0, (sum, t) => sum + t.amount);

  double get _totalExpense => _filteredTransactions
      .where((t) => t.type == TransactionType.expense)
      .fold(0.0, (sum, t) => sum + t.amount);

  double get _currentBalance => _totalIncome - _totalExpense;

  Map<String, double> get _expenseByCategory {
    final map = <String, double>{};
    for (var t in _filteredTransactions.where((item) => item.type == TransactionType.expense)) {
      map[t.category] = (map[t.category] ?? 0) + t.amount;
    }
    return map;
  }

  void _changeMonth(int offset) {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + offset);
    });
  }

  void _deleteTransaction(TransactionItem item) async {
    if (item.id != null) {
      await DBHelper.instance.deleteTransaction(item.id!);
      _refreshTransactions();

      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lançamento "${item.title}" removido.'),
          action: SnackBarAction(
            label: 'Desfazer',
            onPressed: () async {
              await DBHelper.instance.insertTransaction(item);
              _refreshTransactions();
            },
          ),
        ),
      );
    }
  }

  void _openAddTransactionModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => AddTransactionModal(
        defaultDate: _selectedMonth,
        onAdded: _refreshTransactions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formatCurrency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final monthFormat = DateFormat('MMMM yyyy', 'pt_BR');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Minhas Finanças'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshTransactions,
            tooltip: 'Recarregar',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildMonthSelector(monthFormat),
                _buildSummaryCard(formatCurrency),
                if (_expenseByCategory.isNotEmpty) _buildCategoryBreakdown(formatCurrency),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Lançamentos',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                Expanded(
                  child: _filteredTransactions.isEmpty
                      ? const Center(
                          child: Text(
                            'Nenhum lançamento neste mês.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredTransactions.length,
                          itemBuilder: (ctx, index) {
                            final item = _filteredTransactions[index];
                            final isIncome = item.type == TransactionType.income;

                            return Dismissible(
                              key: Key(item.id.toString()),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                color: Colors.redAccent.withOpacity(0.8),
                                child: const Icon(Icons.delete, color: Colors.white),
                              ),
                              onDismissed: (direction) => _deleteTransaction(item),
                              child: ListTile(
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
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddTransactionModal,
        icon: const Icon(Icons.add),
        label: const Text('Novo'),
      ),
    );
  }

  Widget _buildMonthSelector(DateFormat monthFormat) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _changeMonth(-1),
            tooltip: 'Mês anterior',
          ),
          Text(
            monthFormat.format(_selectedMonth).toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _changeMonth(1),
            tooltip: 'Próximo mês',
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(NumberFormat formatter) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text('Saldo do Mês', style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(
              formatter.format(_currentBalance),
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: _currentBalance >= 0 ? Colors.white : Colors.redAccent,
              ),
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text('Receitas', style: TextStyle(color: Colors.green, fontSize: 12)),
                    Text(formatter.format(_totalIncome),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                Column(
                  children: [
                    const Text('Despesas', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
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

  Widget _buildCategoryBreakdown(NumberFormat formatter) {
    final total = _totalExpense;
    if (total <= 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Maiores Gastos por Categoria',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _expenseByCategory.entries.map((e) {
                final pct = (e.value / total) * 100;
                return Chip(
                  label: Text(
                    '${e.key}: ${formatter.format(e.value)} (${pct.toStringAsFixed(0)}%)',
                    style: const TextStyle(fontSize: 11),
                  ),
                  backgroundColor: Colors.teal.withOpacity(0.15),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class AddTransactionModal extends StatefulWidget {
  final DateTime defaultDate;
  final VoidCallback onAdded;

  const AddTransactionModal({
    super.key,
    required this.defaultDate,
    required this.onAdded,
  });

  @override
  State<AddTransactionModal> createState() => _AddTransactionModalState();
}

class _AddTransactionModalState extends State<AddTransactionModal> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _categoryController = TextEditingController();
  TransactionType _type = TransactionType.expense;
  late DateTime _chosenDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _chosenDate = (widget.defaultDate.year == now.year && widget.defaultDate.month == now.month)
        ? now
        : widget.defaultDate;
  }

  void _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _chosenDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _chosenDate = picked);
    }
  }

  void _submit() async {
    final title = _titleController.text.trim();
    final amount = double.tryParse(_amountController.text.replaceAll(',', '.')) ?? 0.0;
    final category = _categoryController.text.trim();

    if (title.isEmpty || amount <= 0 || category.isEmpty) return;

    final item = TransactionItem(
      title: title,
      amount: amount,
      date: _chosenDate,
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<TransactionType>(
              segments: const [
                ButtonSegment(value: TransactionType.expense, label: Text('Despesa')),
                ButtonSegment(value: TransactionType.income, label: Text('Receita')),
              ],
              selected: {_type},
              onSelectionChanged: (newVal) => setState(() => _type = newVal.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Descrição (ex: Supermercado, Salário)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Valor (R\$)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _categoryController,
              decoration: const InputDecoration(
                labelText: 'Categoria (ex: Alimentação, Lazer, Casa)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: Text('Data: ${DateFormat('dd/MM/yyyy').format(_chosenDate)}'),
              trailing: TextButton(
                onPressed: _pickDate,
                child: const Text('Alterar Data'),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: const Text('Salvar Lançamento'),
            ),
          ],
        ),
      ),
    );
  }
}
