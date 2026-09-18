import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:local_auth/local_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
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
      home: const AuthGate(),
    );
  }
}

// Tela de proteção por Biometria/Senha
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final LocalAuthentication _auth = LocalAuthentication();
  bool _isAuthenticated = false;
  bool _canCheckBiometrics = false;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    try {
      final canCheck = await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
      setState(() => _canCheckBiometrics = canCheck);
      if (canCheck) {
        _authenticate();
      } else {
        // Se o celular não tiver biometria/senha cadastrada, libera direto
        setState(() => _isAuthenticated = true);
      }
    } catch (_) {
      setState(() => _isAuthenticated = true);
    }
  }

  Future<void> _authenticate() async {
    try {
      final authenticated = await _auth.authenticate(
        localizedReason: 'Autentique-se para acessar o Sou Mais Controlado',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      setState(() => _isAuthenticated = authenticated);
    } catch (_) {
      // Caso o usuário cancele ou ocorra falha de hardware, mantém tela de desbloqueio
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isAuthenticated) {
      return const HomeScreen();
    }

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 72, color: Colors.teal),
              const SizedBox(height: 20),
              const Text(
                'Sou Mais Controlado',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Aplicativo bloqueado para sua privacidade.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _authenticate,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Desbloquear'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(200, 48),
                ),
              ),
            ],
          ),
        ),
      ),
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
  double _monthlyBudget = 3000.0;

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

  // Lançamentos do mês selecionado
  List<TransactionItem> get _filteredTransactions {
    return _allTransactions.where((t) {
      return t.date.year == _selectedMonth.year && t.date.month == _selectedMonth.month;
    }).toList();
  }

  // Acumulado de meses anteriores ao mês selecionado
  double get _accumulatedPreviousBalance {
    final firstDayOfSelectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final previousTransactions = _allTransactions.where((t) => t.date.isBefore(firstDayOfSelectedMonth));
    
    double income = previousTransactions
        .where((t) => t.type == TransactionType.income)
        .fold(0.0, (sum, t) => sum + t.amount);
    double expense = previousTransactions
        .where((t) => t.type == TransactionType.expense)
        .fold(0.0, (sum, t) => sum + t.amount);
    return income - expense;
  }

  double get _totalIncome => _filteredTransactions
      .where((t) => t.type == TransactionType.income)
      .fold(0.0, (sum, t) => sum + t.amount);

  double get _totalExpense => _filteredTransactions
      .where((t) => t.type == TransactionType.expense)
      .fold(0.0, (sum, t) => sum + t.amount);

  double get _currentMonthBalance => _totalIncome - _totalExpense;

  // Saldo total acumulado até o fim do mês selecionado
  double get _consolidatedBalance => _accumulatedPreviousBalance + _currentMonthBalance;

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

  // Exportar backup (JSON / CSV)
  Future<void> _exportBackup(String format) async {
    if (_allTransactions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum dado para exportar.')),
      );
      return;
    }

    try {
      final nowStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      if (format == 'csv') {
        final buffer = StringBuffer();
        buffer.writeln('ID,Título,Valor,Data,Categoria,Tipo');
        for (final t in _allTransactions) {
          buffer.writeln('${t.id},"${t.title}",${t.amount},${t.date.toIso8601String()},"${t.category}",${t.type.name}');
        }
        await Share.shareXFiles(
          [XFile.fromData(utf8.encode(buffer.toString()), mimeType: 'text/csv', name: 'backup_financas_$nowStr.csv')],
          subject: 'Backup Sou Mais Controlado (CSV)',
        );
      } else {
        final list = _allTransactions.map((t) => t.toMap()).toList();
        final jsonStr = jsonEncode(list);
        await Share.shareXFiles(
          [XFile.fromData(utf8.encode(jsonStr), mimeType: 'application/json', name: 'backup_financas_$nowStr.json')],
          subject: 'Backup Sou Mais Controlado (JSON)',
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao exportar backup: $e')),
      );
    }
  }

  // Restaurar backup de arquivo JSON
  Future<void> _restoreBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        final List<dynamic> decoded = jsonDecode(content);

        final items = decoded.map((item) => TransactionItem.fromMap(Map<String, dynamic>.from(item))).toList();
        
        await DBHelper.instance.replaceAllTransactions(items);
        _refreshTransactions();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sucesso! ${items.length} lançamentos restaurados.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao restaurar backup: $e')),
      );
    }
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
          PopupMenuButton<String>(
            tooltip: 'Opções e Backup',
            onSelected: (val) {
              if (val == 'export_csv') _exportBackup('csv');
              if (val == 'export_json') _exportBackup('json');
              if (val == 'restore') _restoreBackup();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'export_csv', child: Text('Exportar Planilha (CSV)')),
              const PopupMenuItem(value: 'export_json', child: Text('Exportar Backup Completo (JSON)')),
              const PopupMenuItem(value: 'restore', child: Text('Restaurar Backup (JSON)')),
            ],
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

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _buildMonthSelector(monthFormat),
        _buildConsolidatedSummaryCard(formatCurrency),
        _buildBudgetProgressBar(formatCurrency),
        if (_expenseByCategory.isNotEmpty) ...[
          _buildPieChartSection(formatCurrency),
          _buildCategoryBreakdown(formatCurrency),
        ],
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            'Lançamentos (Toque para editar)',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
        ),
        _filteredTransactions.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(32.0),
                child: Center(
                  child: Text(
                    'Nenhum lançamento neste mês.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
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
        const SizedBox(height: 80), // Espaço para não cobrir o FAB
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

  // Card com Acumulado Anterior + Saldo do Mês + Consolidado Total
  Widget _buildConsolidatedSummaryCard(NumberFormat formatter) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Acumulado Anterior', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    Text(
                      formatter.format(_accumulatedPreviousBalance),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _accumulatedPreviousBalance >= 0 ? Colors.greenAccent : Colors.redAccent,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Saldo do Mês', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    Text(
                      formatter.format(_currentMonthBalance),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _currentMonthBalance >= 0 ? Colors.greenAccent : Colors.redAccent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 18),
            const Text('Saldo Consolidado Total', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(
              formatter.format(_consolidatedBalance),
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: _consolidatedBalance >= 0 ? Colors.white : Colors.redAccent,
              ),
            ),
            const Divider(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text('Receitas (Mês)', style: TextStyle(color: Colors.green, fontSize: 11)),
                    Text(formatter.format(_totalIncome),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                Column(
                  children: [
                    const Text('Despesas (Mês)', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                    Text(formatter.format(_totalExpense),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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

  // Gráfico de Pizza / Rosca Nativo
  Widget _buildPieChartSection(NumberFormat formatter) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Card(
        color: Colors.white.withOpacity(0.03),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Gráfico de Despesas', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 12),
              Center(
                child: SizedBox(
                  width: 140,
                  height: 140,
                  child: CustomPaint(
                    painter: DonutChartPainter(
                      categoryExpenses: _expenseByCategory,
                      total: _totalExpense,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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

// Pintor gráfico do gráfico de Rosca (Donut Chart)
class DonutChartPainter extends CustomPainter {
  final Map<String, double> categoryExpenses;
  final double total;

  DonutChartPainter({required this.categoryExpenses, required this.total});

  static final List<Color> _palette = [
    Colors.teal,
    Colors.orangeAccent,
    Colors.purpleAccent,
    Colors.blueAccent,
    Colors.redAccent,
    Colors.amber,
    Colors.cyan,
    Colors.pinkAccent,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width / 2, size.height / 2);
    const strokeWidth = 24.0;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    double startAngle = -pi / 2;
    int colorIdx = 0;

    for (final entry in categoryExpenses.entries) {
      final sweepAngle = (entry.value / total) * 2 * pi;
      paint.color = _palette[colorIdx % _palette.length];
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
      startAngle += sweepAngle;
      colorIdx++;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
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
  State<TransactionFormModal> createState() => _TransactionFormModalState();
}

class _TransactionFormModalState extends State<TransactionFormModal> {
  late TextEditingController _titleController;
  late TextEditingController _amountController;
  late TextEditingController _categoryController;
  TransactionType _type = TransactionType.expense;
  late DateTime _chosenDate;

  final List<Map<String, dynamic>> _quickCategories = [
    {'name': 'Alimentação', 'icon': Icons.restaurant},
    {'name': 'Transporte', 'icon': Icons.directions_car},
    {'name': 'Moradia', 'icon': Icons.home},
    {'name': 'Saúde', 'icon': Icons.local_hospital},
    {'name': 'Lazer', 'icon': Icons.sports_esports},
    {'name': 'Compras', 'icon': Icons.shopping_bag},
    {'name': 'Contas', 'icon': Icons.receipt_long},
    {'name': 'Salário', 'icon': Icons.account_balance_wallet},
  ];

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
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final bottomPadding = mediaQuery.viewPadding.bottom;

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
                  final isSelected =
                      _categoryController.text.toLowerCase() == (cat['name'] as String).toLowerCase();
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
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
