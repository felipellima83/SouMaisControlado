import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'models/transaction_model.dart';
import 'services/db_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR', null);
  runApp(const FinanceApp());
}

class FinanceApp extends StatelessWidget {
  const FinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sou Mais Controlado',
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
  String? _errorMessage;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  double _monthlyBudget = 3000.0; // Teto de gastos padrão do mês

  @override
  void initState() {
    super.initState();
    _refreshTransactions();
  }

  Future<void> _refreshTransactions() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await DBHelper.instance.getAllTransactions();
      setState(() {
        _allTransactions = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Erro ao carregar dados: $e';
        _isLoading = false;
      });
    }
  }

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

 void _openTransactionModal([TransactionItem? existingItem]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => TransactionFormModal(
        defaultDate: _selectedMonth,
        existingItem: existingItem,
        onSaved: _refreshTransactions,
      ),
    );
  }

  void _showSetBudgetDialog() {
    final controller = TextEditingController(text: _monthlyBudget.toStringAsFixed(2));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Definir Meta de Gastos'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Teto do Mês (R\$)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(controller.text.replaceAll(',', '.')) ?? _monthlyBudget;
              setState(() => _monthlyBudget = val);
              Navigator.of(ctx).pop();
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'alimentação':
        return Icons.restaurant;
      case 'transporte':
        return Icons.directions_car;
      case 'moradia':
      case 'casa':
        return Icons.home;
      case 'saúde':
        return Icons.local_hospital;
      case 'lazer':
        return Icons.sports_esports;
      case 'salário':
        return Icons.account_balance_wallet;
      case 'compras':
        return Icons.shopping_bag;
      case 'contas':
        return Icons.receipt_long;
      default:
        return Icons.monetization_on;
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatCurrency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final monthFormat = DateFormat('MMMM yyyy', 'pt_BR');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sou Mais Controlado'),
        actions: [
          IconButton(
            icon: const Icon(Icons.track_changes),
            onPressed: _showSetBudgetDialog,
            tooltip: 'Definir Meta de Gastos',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshTransactions,
            tooltip: 'Recarregar',
          ),
        ],
      ),
      body: _buildBody(formatCurrency, monthFormat),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openTransactionModal(),
        icon: const Icon(Icons.add),
        label: const Text('Novo'),
      ),
    );
  }

  Widget _buildBody(NumberFormat formatCurrency, DateFormat monthFormat) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 12),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _refreshTransactions,
                child: const Text('Tentar Novamente'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        _buildMonthSelector(monthFormat),
        _buildSummaryCard(formatCurrency),
        _buildBudgetProgressBar(formatCurrency),
        if (_expenseByCategory.isNotEmpty) _buildCategoryBreakdown(formatCurrency),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Lançamentos (Toque para editar)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
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
                    final categoryIcon = _getCategoryIcon(item.category);

                    return Dismissible(
                      key: Key('${item.id}_${item.title}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: Colors.redAccent.withOpacity(0.8),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (direction) => _deleteTransaction(item),
                      child: ListTile(
                        onTap: () => _openTransactionModal(item),
                        leading: CircleAvatar(
                          backgroundColor: isIncome
                              ? Colors.green.withOpacity(0.2)
                              : Colors.red.withOpacity(0.2),
                          child: Icon(
                            categoryIcon,
                            color: isIncome ? Colors.green : Colors.redAccent,
                            size: 20,
                          ),
                        ),
                        title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: Text(
                            '${item.category} • ${DateFormat('dd/MM/yyyy').format(item.date)}'),
                        trailing: Text(
                          '${isIncome ? '+' : '-'} ${formatCurrency.format(item.amount)}',
                          style: TextStyle(
                            color: isIncome ? Colors.green : Colors.redAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildMonthSelector(DateFormat monthFormat) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
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
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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
            const Divider(height: 18),
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

  Widget _buildBudgetProgressBar(NumberFormat formatter) {
    if (_monthlyBudget <= 0) return const SizedBox.shrink();
    final progress = (_totalExpense / _monthlyBudget).clamp(0.0, 1.0);
    final pctNumber = (_totalExpense / _monthlyBudget) * 100;

    Color barColor = Colors.green;
    if (pctNumber >= 100) {
      barColor = Colors.redAccent;
    } else if (pctNumber >= 75) {
      barColor = Colors.orangeAccent;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Meta: ${formatter.format(_totalExpense)} de ${formatter.format(_monthlyBudget)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              Text(
                '${pctNumber.toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: barColor),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              color: barColor,
              backgroundColor: Colors.white10,
              minHeight: 7,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBreakdown(NumberFormat formatter) {
    final total = _totalExpense;
    if (total <= 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gastos por Categoria',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _expenseByCategory.entries.map((e) {
                final pct = (e.value / total) * 100;
                return Chip(
                  avatar: Icon(_getCategoryIcon(e.key), size: 14),
                  label: Text(
                    '${e.key}: ${formatter.format(e.value)} (${pct.toStringAsFixed(0)}%)',
                    style: const TextStyle(fontSize: 10),
                  ),
                  backgroundColor: Colors.teal.withOpacity(0.12),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class TransactionFormModal extends StatefulWidget {
  final DateTime defaultDate;
  final TransactionItem? existingItem;
  final VoidCallback onSaved;

  const TransactionFormModal({
    super.key,
    required this.defaultDate,
    this.existingItem,
    required this.onSaved,
  });

@override
  Widget build(BuildContext context) {
    final isEdit = widget.existingItem != null;
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom; // Espaço do teclado
    final bottomPadding = mediaQuery.viewPadding.bottom; // Barra de navegação/gestos do Android

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: bottomInset + (bottomPadding > 0 ? bottomPadding : 16),
          left: 16,
          right: 16,
          top: 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  isEdit ? 'Editar Lançamento' : 'Novo Lançamento',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
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
              const Text('Categorias Rápidas:', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _quickCategories.map((cat) {
                  final isSelected = _categoryController.text.toLowerCase() == (cat['name'] as String).toLowerCase();
                  return ChoiceChip(
                    avatar: Icon(cat['icon'] as IconData, size: 16),
                    label: Text(cat['name'] as String, style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _categoryController.text = cat['name'] as String);
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _categoryController,
                decoration: const InputDecoration(
                  labelText: 'Categoria Selecionada / Personalizada',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
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
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(isEdit ? 'Salvar Alterações' : 'Salvar Lançamento'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final item = widget.existingItem;
    if (item != null) {
      _titleController = TextEditingController(text: item.title);
      _amountController = TextEditingController(text: item.amount.toStringAsFixed(2));
      _categoryController = TextEditingController(text: item.category);
      _type = item.type;
      _chosenDate = item.date;
    } else {
      _titleController = TextEditingController();
      _amountController = TextEditingController();
      _categoryController = TextEditingController(text: 'Alimentação');
      final now = DateTime.now();
      _chosenDate = (widget.defaultDate.year == now.year && widget.defaultDate.month == now.month)
          ? now
          : widget.defaultDate;
    }
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

    final isEdit = widget.existingItem != null;
    final item = TransactionItem(
      id: widget.existingItem?.id,
      title: title,
      amount: amount,
      date: _chosenDate,
      category: category,
      type: _type,
    );

    if (isEdit) {
      await DBHelper.instance.updateTransaction(item);
    } else {
      await DBHelper.instance.insertTransaction(item);
    }

    widget.onSaved();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingItem != null;

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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                isEdit ? 'Editar Lançamento' : 'Novo Lançamento',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
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
            const Text('Categorias Rápidas:', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _quickCategories.map((cat) {
                final isSelected = _categoryController.text.toLowerCase() == (cat['name'] as String).toLowerCase();
                return ChoiceChip(
                  avatar: Icon(cat['icon'] as IconData, size: 16),
                  label: Text(cat['name'] as String, style: const TextStyle(fontSize: 12)),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _categoryController.text = cat['name'] as String);
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _categoryController,
              decoration: const InputDecoration(
                labelText: 'Categoria Selecionada / Personalizada',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
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
              child: Text(isEdit ? 'Salvar Alterações' : 'Salvar Lançamento'),
            ),
          ],
        ),
      ),
    );
  }
}
