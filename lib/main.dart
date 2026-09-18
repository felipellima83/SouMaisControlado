import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
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

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final LocalAuthentication _auth = LocalAuthentication();
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    try {
      final canCheck = await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
      if (canCheck) {
        _authenticate();
      } else {
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
    } catch (_) {}
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
                style: ElevatedButton.styleFrom(minimumSize: const Size(200, 48)),
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
  String _selectedAccountFilter = 'Todas';

  final List<String> _customAccounts = [
    'Conta Principal',
    'Carteira / Dinheiro',
    'Cartão de Crédito',
  ];

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
      for (final item in data) {
        if (!_customAccounts.contains(item.account)) {
          _customAccounts.add(item.account);
        }
      }
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
      final matchesMonth = t.date.year == _selectedMonth.year && t.date.month == _selectedMonth.month;
      final matchesAccount = _selectedAccountFilter == 'Todas' || t.account == _selectedAccountFilter;
      return matchesMonth && matchesAccount;
    }).toList();
  }

  Map<DateTime, List<TransactionItem>> get _groupedTransactions {
    final Map<DateTime, List<TransactionItem>> map = {};
    final list = [..._filteredTransactions];
    list.sort((a, b) => b.date.compareTo(a.date));

    for (var t in list) {
      final dayKey = DateTime(t.date.year, t.date.month, t.date.day);
      map.putIfAbsent(dayKey, () => []).add(t);
    }
    return map;
  }

  double get _accumulatedPreviousBalance {
    final firstDayOfSelectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final previousTransactions = _allTransactions.where((t) {
      final isBefore = t.date.isBefore(firstDayOfSelectedMonth);
      final matchesAccount = _selectedAccountFilter == 'Todas' || t.account == _selectedAccountFilter;
      return isBefore && matchesAccount;
    });

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

  double get _consolidatedBalance => _accumulatedPreviousBalance + _currentMonthBalance;

  void _changeMonth(int offset) {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + offset);
    });
  }

  void _toggleTransactionEffective(TransactionItem item) async {
    if (item.id == null) return;
    final newStatus = !item.isCompleted;
    await DBHelper.instance.toggleTransactionStatus(item.id!, newStatus);
    _refreshTransactions();

    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(newStatus ? 'Lançamento efetivado' : 'Lançamento marcado como pendente'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _confirmDeleteTransaction(TransactionItem item) {
    if (item.id == null) return;

    if (item.groupId == null) {
      _executeSingleDelete(item);
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Repetição'),
        content: Text(
          'O lançamento "${item.title}" faz parte de uma série.\n\nComo deseja excluir?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
          ListTile(
            dense: true,
            leading: const Icon(Icons.delete_outline),
            title: const Text('Apenas este lançamento'),
            onTap: () async {
              Navigator.of(ctx).pop();
              await DBHelper.instance.deleteTransaction(item.id!);
              _refreshTransactions();
            },
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.arrow_forward),
            title: const Text('Deste em diante'),
            onTap: () async {
              Navigator.of(ctx).pop();
              await DBHelper.instance.deleteGroupFromDate(item.groupId!, item.date);
              _refreshTransactions();
            },
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
            title: const Text('Todas as repetições', style: TextStyle(color: Colors.redAccent)),
            onTap: () async {
              Navigator.of(ctx).pop();
              await DBHelper.instance.deleteGroupAll(item.groupId!);
              _refreshTransactions();
            },
          ),
        ],
      ),
    );
  }

  void _executeSingleDelete(TransactionItem item) async {
    await DBHelper.instance.deleteTransaction(item.id!);
    _refreshTransactions();

    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${item.title}" removido.'),
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

  void _openTransactionModal([TransactionItem? existingItem]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => TransactionFormModal(
        defaultDate: _selectedMonth,
        existingItem: existingItem,
        availableAccounts: _customAccounts,
        onAccountCreated: (newAcc) {
          if (!_customAccounts.contains(newAcc)) {
            setState(() => _customAccounts.add(newAcc));
          }
        },
        onSaved: _refreshTransactions,
      ),
    );
  }

  void _openManageAccountsDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Gerenciar Contas e Cartões', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
                  ],
                ),
                const Divider(),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _customAccounts.length,
                    itemBuilder: (context, index) {
                      final acc = _customAccounts[index];
                      final count = _allTransactions.where((t) => t.account == acc).length;

                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.account_balance_wallet, color: Colors.teal),
                        title: Text(acc),
                        subtitle: Text('$count lançamentos'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 18, color: Colors.tealAccent),
                              onPressed: () => _showEditAccountDialog(acc, () => setModalState(() {})),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                              onPressed: () => _showDeleteAccountDialog(acc, count, () => setModalState(() {})),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showEditAccountDialog(String oldName, VoidCallback onUpdatedModal) {
    final controller = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renomear Conta/Cartão'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != oldName) {
                await DBHelper.instance.renameAccount(oldName, newName);
                setState(() {
                  final idx = _customAccounts.indexOf(oldName);
                  if (idx != -1) _customAccounts[idx] = newName;
                  if (_selectedAccountFilter == oldName) _selectedAccountFilter = newName;
                });
                _refreshTransactions();
                onUpdatedModal();
                if (mounted) Navigator.of(ctx).pop();
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog(String accountName, int transactionsCount, VoidCallback onUpdatedModal) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Excluir "$accountName"?'),
        content: Text('A conta e todas as $transactionsCount transações vinculadas serão apagadas.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              await DBHelper.instance.deleteAccountAndTransactions(accountName);
              setState(() {
                _customAccounts.remove(accountName);
                if (_selectedAccountFilter == accountName) _selectedAccountFilter = 'Todas';
              });
              _refreshTransactions();
              onUpdatedModal();
              if (mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Excluir Tudo', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _exportBackup(String format) async {
    if (_allTransactions.isEmpty) return;
    try {
      final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      final nowStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());

      if (format == 'csv') {
        final file = File('${dir.path}/backup_financas_$nowStr.csv');
        final buffer = StringBuffer();
        buffer.writeln('ID,Título,Valor,Data,Categoria,Conta_Cartao,GroupId,Efetivado,Tipo');
        for (final t in _allTransactions) {
          buffer.writeln('${t.id},"${t.title}",${t.amount},${t.date.toIso8601String()},"${t.category}","${t.account}","${t.groupId ?? ''}",${t.isCompleted ? 1 : 0},${t.type.name}');
        }
        await file.writeAsString(buffer.toString());
      } else {
        final file = File('${dir.path}/backup_financas_$nowStr.json');
        final list = _allTransactions.map((t) => t.toMap()).toList();
        await file.writeAsString(jsonEncode(list));
      }
    } catch (_) {}
  }

  Future<void> _restoreBackup() async {
    try {
      final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList();
      if (files.isEmpty) return;

      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      final content = await files.first.readAsString();
      final List<dynamic> decoded = jsonDecode(content);
      final items = decoded.map((item) => TransactionItem.fromMap(Map<String, dynamic>.from(item))).toList();

      await DBHelper.instance.replaceAllTransactions(items);
      _refreshTransactions();
    } catch (_) {}
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
          decoration: const InputDecoration(labelText: 'Teto do Mês (R\$)', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
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

  @override
  Widget build(BuildContext context) {
    final formatCurrency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final monthFormat = DateFormat('MMMM yyyy', 'pt_BR');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sou Mais Controlado', style: TextStyle(fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.track_changes, size: 20),
            onPressed: _showSetBudgetDialog,
            tooltip: 'Meta',
          ),
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'manage_accounts') _openManageAccountsDialog();
              if (val == 'export_csv') _exportBackup('csv');
              if (val == 'export_json') _exportBackup('json');
              if (val == 'restore') _restoreBackup();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'manage_accounts', child: Text('Gerenciar Contas/Cartões')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'export_csv', child: Text('Exportar Planilha (CSV)')),
              const PopupMenuItem(value: 'export_json', child: Text('Exportar Backup (JSON)')),
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
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) {
      return Center(child: Text(_errorMessage!));
    }

    final allAccountsList = ['Todas', ..._customAccounts];
    final grouped = _groupedTransactions;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _buildMonthSelector(monthFormat),
        _buildAccountFilterBar(allAccountsList),
        _buildConsolidatedSummaryCard(formatCurrency),
        _buildBudgetProgressBar(formatCurrency),

        if (grouped.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32.0),
            child: Center(
              child: Text(
                'Nenhum lançamento neste mês para o filtro selecionado.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
          )
        else
          ...grouped.entries.map((entry) {
            final date = entry.key;
            final items = entry.value;

            final dayIncome = items.where((t) => t.type == TransactionType.income).fold(0.0, (sum, t) => sum + t.amount);
            final dayExpense = items.where((t) => t.type == TransactionType.expense).fold(0.0, (sum, t) => sum + t.amount);
            final dayBalance = dayIncome - dayExpense;

            final dayTitle = '${DateFormat('dd/MM/yyyy', 'pt_BR').format(date)}, ${toBeginningOfSentenceCase(DateFormat('EEEE', 'pt_BR').format(date))}';

            return Container(
              margin: const EdgeInsets.only(top: 8.0, bottom: 4.0),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Cabeçalho da data limpo (sem ícone de recolher)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    color: Colors.white.withOpacity(0.04),
                    child: Text(
                      dayTitle,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, letterSpacing: 0.2),
                    ),
                  ),

                  // Linhas da tabela (zebradas)
                  ...items.asMap().entries.map((itemEntry) {
                    final idx = itemEntry.key;
                    final item = itemEntry.value;
                    final isIncome = item.type == TransactionType.income;
                    final isEven = idx % 2 == 0;

                    return InkWell(
                      onTap: () => _openTransactionModal(item),
                      onLongPress: () => _confirmDeleteTransaction(item),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        color: isEven ? Colors.transparent : Colors.white.withOpacity(0.035),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: item.isCompleted,
                                activeColor: Colors.teal,
                                checkColor: Colors.black,
                                side: BorderSide(color: Colors.grey.shade600, width: 1.2),
                                onChanged: (val) => _toggleTransactionEffective(item),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              flex: 4,
                              child: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                item.category,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade400),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                item.account,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade400),
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${isIncome ? '+' : '-'} ${item.amount.toStringAsFixed(2).replaceAll('.', ',')}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color: isIncome ? Colors.greenAccent.shade400 : Colors.redAccent.shade100,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.check,
                                  size: 14,
                                  color: item.isCompleted ? Colors.tealAccent : Colors.grey.shade700,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                  // Linha pontilhada e Saldo do Dia
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0, bottom: 4.0, right: 12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('Saldo do dia: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                        Text(
                          'R\$ ${dayBalance.toStringAsFixed(2).replaceAll('.', ',')}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: dayBalance >= 0 ? Colors.white : Colors.redAccent.shade100,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),

        const SizedBox(height: 80),
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
            icon: const Icon(Icons.chevron_left, size: 20),
            onPressed: () => _changeMonth(-1),
          ),
          Text(
            monthFormat.format(_selectedMonth).toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            onPressed: () => _changeMonth(1),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountFilterBar(List<String> accounts) {
    return Container(
      height: 38,
      margin: const EdgeInsets.only(bottom: 6.0),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        itemCount: accounts.length,
        itemBuilder: (ctx, index) {
          final acc = accounts[index];
          final isSelected = _selectedAccountFilter == acc;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3.0),
            child: FilterChip(
              visualDensity: VisualDensity.compact,
              label: Text(acc, style: const TextStyle(fontSize: 11.5)),
              selected: isSelected,
              selectedColor: Colors.teal.withOpacity(0.3),
              checkmarkColor: Colors.tealAccent,
              onSelected: (selected) {
                setState(() => _selectedAccountFilter = acc);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildConsolidatedSummaryCard(NumberFormat formatter) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Acumulado Anterior', style: TextStyle(fontSize: 10.5, color: Colors.grey)),
                    Text(
                      formatter.format(_accumulatedPreviousBalance),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _accumulatedPreviousBalance >= 0 ? Colors.greenAccent : Colors.redAccent,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Saldo do Mês', style: TextStyle(fontSize: 10.5, color: Colors.grey)),
                    Text(
                      formatter.format(_currentMonthBalance),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _currentMonthBalance >= 0 ? Colors.greenAccent : Colors.redAccent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _selectedAccountFilter == 'Todas' ? 'Consolidado:' : 'Saldo ($_selectedAccountFilter):',
                  style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                ),
                Text(
                  formatter.format(_consolidatedBalance),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _consolidatedBalance >= 0 ? Colors.white : Colors.redAccent,
                  ),
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
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Teto: ${formatter.format(_totalExpense)} / ${formatter.format(_monthlyBudget)}',
                style: const TextStyle(fontSize: 10.5, color: Colors.grey),
              ),
              Text(
                '${pctNumber.toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: barColor),
              ),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              color: barColor,
              backgroundColor: Colors.white10,
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }
}

class TransactionFormModal extends StatefulWidget {
  final DateTime defaultDate;
  final TransactionItem? existingItem;
  final List<String> availableAccounts;
  final Function(String) onAccountCreated;
  final VoidCallback onSaved;

  const TransactionFormModal({
    super.key,
    required this.defaultDate,
    this.existingItem,
    required this.availableAccounts,
    required this.onAccountCreated,
    required this.onSaved,
  });

  @override
  State<TransactionFormModal> createState() => _TransactionFormModalState();
}

class _TransactionFormModalState extends State<TransactionFormModal> {
  late TextEditingController _titleController;
  late TextEditingController _amountController;
  late TextEditingController _categoryController;
  late String _selectedAccount;
  TransactionType _type = TransactionType.expense;
  late DateTime _chosenDate;
  bool _isCompleted = true;

  bool _isInstallment = false;
  int _installmentsCount = 2;
  bool _amountIsTotal = true;

  bool _isRecurring = false;

  final List<String> _quickCategories = [
    'Alimentação',
    'Transporte',
    'Moradia',
    'Saúde',
    'Lazer',
    'Compras',
    'Contas',
    'Salário',
  ];

  @override
  void initState() {
    super.initState();
    final item = widget.existingItem;
    if (item != null) {
      _titleController = TextEditingController(text: item.title);
      _amountController = TextEditingController(text: item.amount.toStringAsFixed(2));
      _categoryController = TextEditingController(text: item.category);
      _selectedAccount = item.account;
      _type = item.type;
      _chosenDate = item.date;
      _isCompleted = item.isCompleted;
    } else {
      _titleController = TextEditingController();
      _amountController = TextEditingController();
      _categoryController = TextEditingController(text: 'Alimentação');
      _selectedAccount = widget.availableAccounts.isNotEmpty ? widget.availableAccounts.first : 'Conta Principal';
      final now = DateTime.now();
      _chosenDate = (widget.defaultDate.year == now.year && widget.defaultDate.month == now.month)
          ? now
          : widget.defaultDate;
      _isCompleted = true;
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

  DateTime _addMonths(DateTime date, int months) {
    var destYear = date.year + (date.month - 1 + months) ~/ 12;
    var destMonth = (date.month - 1 + months) % 12 + 1;
    var daysInDestMonth = DateTime(destYear, destMonth + 1, 0).day;
    var destDay = min(date.day, daysInDestMonth);
    return DateTime(destYear, destMonth, destDay, date.hour, date.minute, date.second);
  }

  void _showNewAccountDialog() {
    final accController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nova Conta ou Cartão'),
        content: TextField(
          controller: accController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nome (ex: Nubank, Cartão XP)', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              final text = accController.text.trim();
              if (text.isNotEmpty) {
                widget.onAccountCreated(text);
                setState(() => _selectedAccount = text);
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
  }

  void _submit() async {
    final title = _titleController.text.trim();
    final rawAmount = double.tryParse(_amountController.text.replaceAll(',', '.')) ?? 0.0;
    final category = _categoryController.text.trim();

    if (title.isEmpty || rawAmount <= 0 || category.isEmpty) return;

    final isEdit = widget.existingItem != null;

    if (isEdit) {
      final item = TransactionItem(
        id: widget.existingItem!.id,
        title: title,
        amount: rawAmount,
        date: _chosenDate,
        category: category,
        account: _selectedAccount,
        groupId: widget.existingItem!.groupId,
        isCompleted: _isCompleted,
        type: _type,
      );
      await DBHelper.instance.updateTransaction(item);
    } else {
      final generatedGroupId = DateTime.now().millisecondsSinceEpoch.toString();

      if (_isRecurring) {
        final items = <TransactionItem>[];
        for (int i = 0; i < 24; i++) {
          final recurDate = _addMonths(_chosenDate, i);
          items.add(
            TransactionItem(
              title: title,
              amount: rawAmount,
              date: recurDate,
              category: category,
              account: _selectedAccount,
              groupId: generatedGroupId,
              isCompleted: i == 0 ? _isCompleted : false,
              type: _type,
            ),
          );
        }
        await DBHelper.instance.insertMultipleTransactions(items);
      } else if (_type == TransactionType.expense && _isInstallment && _installmentsCount > 1) {
        final installmentAmount = _amountIsTotal
            ? double.parse((rawAmount / _installmentsCount).toStringAsFixed(2))
            : rawAmount;

        final items = <TransactionItem>[];
        for (int i = 1; i <= _installmentsCount; i++) {
          final installmentDate = _addMonths(_chosenDate, i - 1);
          items.add(
            TransactionItem(
              title: '$title ($i/$_installmentsCount)',
              amount: installmentAmount,
              date: installmentDate,
              category: category,
              account: _selectedAccount,
              groupId: generatedGroupId,
              isCompleted: i == 1 ? _isCompleted : false,
              type: TransactionType.expense,
            ),
          );
        }
        await DBHelper.instance.insertMultipleTransactions(items);
      } else {
        final item = TransactionItem(
          title: title,
          amount: rawAmount,
          date: _chosenDate,
          category: category,
          account: _selectedAccount,
          isCompleted: _isCompleted,
          type: _type,
        );
        await DBHelper.instance.insertTransaction(item);
      }
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
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 10),
              SegmentedButton<TransactionType>(
                segments: const [
                  ButtonSegment(value: TransactionType.expense, label: Text('Despesa')),
                  ButtonSegment(value: TransactionType.income, label: Text('Receita')),
                ],
                selected: {_type},
                onSelectionChanged: (newVal) {
                  setState(() {
                    _type = newVal.first;
                    if (_type == TransactionType.income) _isInstallment = false;
                  });
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Descrição', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: (_isInstallment && !_amountIsTotal)
                      ? 'Valor da Parcela (R\$)'
                      : 'Valor Total (R\$)',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: widget.availableAccounts.contains(_selectedAccount)
                          ? _selectedAccount
                          : widget.availableAccounts.first,
                      decoration: const InputDecoration(
                        labelText: 'Conta ou Cartão',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      items: widget.availableAccounts.map((acc) {
                        return DropdownMenuItem<String>(value: acc, child: Text(acc));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedAccount = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: _showNewAccountDialog,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Lançamento Efetivado / Pago', style: TextStyle(fontSize: 13)),
                value: _isCompleted,
                activeColor: Colors.teal,
                onChanged: (val) => setState(() => _isCompleted = val ?? true),
              ),
              if (!isEdit) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Repetir todo mês (Fixo)', style: TextStyle(fontSize: 13)),
                  value: _isRecurring,
                  onChanged: (val) {
                    setState(() {
                      _isRecurring = val;
                      if (val) _isInstallment = false;
                    });
                  },
                ),
                if (_type == TransactionType.expense && !_isRecurring) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Compra Parcelada?', style: TextStyle(fontSize: 13)),
                    value: _isInstallment,
                    onChanged: (val) => setState(() => _isInstallment = val),
                  ),
                  if (_isInstallment) ...[
                    Row(
                      children: [
                        const Text('Parcelas: ', style: TextStyle(fontSize: 12)),
                        DropdownButton<int>(
                          value: _installmentsCount,
                          dropdownColor: Colors.grey[900],
                          items: List.generate(35, (i) => i + 2).map((num) {
                            return DropdownMenuItem<int>(value: num, child: Text('${num}x'));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _installmentsCount = val);
                          },
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile<bool>(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Total', style: TextStyle(fontSize: 11)),
                            value: true,
                            groupValue: _amountIsTotal,
                            onChanged: (val) => setState(() => _amountIsTotal = val!),
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<bool>(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Por Parcela', style: TextStyle(fontSize: 11)),
                            value: false,
                            groupValue: _amountIsTotal,
                            onChanged: (val) => setState(() => _amountIsTotal = val!),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _quickCategories.map((cat) {
                  final isSelected = _categoryController.text.toLowerCase() == cat.toLowerCase();
                  return ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(cat, style: const TextStyle(fontSize: 11)),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) setState(() => _categoryController.text = cat);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _categoryController,
                decoration: const InputDecoration(labelText: 'Categoria', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today, size: 20),
                title: Text('Data: ${DateFormat('dd/MM/yyyy').format(_chosenDate)}', style: const TextStyle(fontSize: 13)),
                trailing: TextButton(onPressed: _pickDate, child: const Text('Alterar')),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                child: Text(isEdit ? 'Salvar Alterações' : 'Salvar Lançamento'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
