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

  // Manipulador de exclusão inteligente (com suporte a séries)
  void _confirmDeleteTransaction(TransactionItem item) {
    if (item.id == null) return;

    if (item.groupId == null) {
      // Transação avulsa: exclusão direta
      _executeSingleDelete(item);
      return;
    }

    // Se tiver groupId, abre opções de exclusão de série
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Repetição'),
        content: Text(
          'O lançamento "${item.title}" faz parte de uma série (parcelada ou mensal fixa).\n\nComo deseja excluir?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.delete_outline),
            title: const Text('Apenas este lançamento'),
            subtitle: const Text('Remove somente a parcela/mês selecionado'),
            onTap: () async {
              Navigator.of(ctx).pop();
              await DBHelper.instance.deleteTransaction(item.id!);
              _refreshTransactions();
              _showSnackBar('Lançamento removido.');
            },
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.arrow_forward),
            title: const Text('Deste em diante'),
            subtitle: const Text('Mantém os meses anteriores e apaga os futuros'),
            onTap: () async {
              Navigator.of(ctx).pop();
              await DBHelper.instance.deleteGroupFromDate(item.groupId!, item.date);
              _refreshTransactions();
              _showSnackBar('Lançamentos futuros removidos.');
            },
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
            title: const Text('Todas as repetições (Desde o início)', style: TextStyle(color: Colors.redAccent)),
            subtitle: const Text('Apaga a série completa em todos os meses'),
            onTap: () async {
              Navigator.of(ctx).pop();
              await DBHelper.instance.deleteGroupAll(item.groupId!);
              _refreshTransactions();
              _showSnackBar('Série completa removida.');
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

  void _showSnackBar(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
                    const Text(
                      'Gerenciar Contas e Cartões',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Toque no lápis para renomear ou na lixeira para excluir a conta e todos os seus lançamentos vinculados.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const Divider(height: 20),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _customAccounts.length,
                    itemBuilder: (context, index) {
                      final acc = _customAccounts[index];
                      final count = _allTransactions.where((t) => t.account == acc).length;

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.teal.withOpacity(0.2),
                          child: Icon(_getAccountIcon(acc), color: Colors.teal, size: 20),
                        ),
                        title: Text(acc, style: const TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: Text('$count lançamento(s) vinculados'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20, color: Colors.tealAccent),
                              tooltip: 'Renomear',
                              onPressed: () => _showEditAccountDialog(acc, () {
                                setModalState(() {});
                              }),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                              tooltip: 'Excluir',
                              onPressed: () => _showDeleteAccountDialog(acc, count, () {
                                setModalState(() {});
                              }),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
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
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Novo Nome',
            border: OutlineInputBorder(),
          ),
        ),
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
        content: Text(
          'ATENÇÃO: A conta será excluída e TODAS as $transactionsCount transação(ões) vinculadas a ela serão APAGADAS permanentemente.\n\nDeseja continuar?',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              await DBHelper.instance.deleteAccountAndTransactions(accountName);
              setState(() {
                _customAccounts.remove(accountName);
                if (_selectedAccountFilter == accountName) {
                  _selectedAccountFilter = 'Todas';
                }
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
    if (_allTransactions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum dado para exportar.')),
      );
      return;
    }

    try {
      final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      final nowStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());

      if (format == 'csv') {
        final file = File('${dir.path}/backup_financas_$nowStr.csv');
        final buffer = StringBuffer();
        buffer.writeln('ID,Título,Valor,Data,Categoria,Conta_Cartao,GroupId,Tipo');
        for (final t in _allTransactions) {
          buffer.writeln('${t.id},"${t.title}",${t.amount},${t.date.toIso8601String()},"${t.category}","${t.account}","${t.groupId ?? ''}",${t.type.name}');
        }
        await file.writeAsString(buffer.toString());
        if (!mounted) return;
        _showFileLocationDialog('Planilha CSV salva com sucesso!', file.path);
      } else {
        final file = File('${dir.path}/backup_financas_$nowStr.json');
        final list = _allTransactions.map((t) => t.toMap()).toList();
        await file.writeAsString(jsonEncode(list));
        if (!mounted) return;
        _showFileLocationDialog('Backup JSON salvo com sucesso!', file.path);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao exportar: $e')),
      );
    }
  }

  Future<void> _restoreBackup() async {
    try {
      final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList();

      if (files.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nenhum backup .json encontrado em:\n${dir.path}')),
        );
        return;
      }

      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      final latestFile = files.first;

      final content = await latestFile.readAsString();
      final List<dynamic> decoded = jsonDecode(content);
      final items = decoded.map((item) => TransactionItem.fromMap(Map<String, dynamic>.from(item))).toList();

      await DBHelper.instance.replaceAllTransactions(items);
      _refreshTransactions();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restaurado com sucesso (${items.length} lançamentos)!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao restaurar: $e')),
      );
    }
  }

  void _showFileLocationDialog(String title, String path) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text('Arquivo gravado localmente em:\n\n$path'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
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

  IconData _getAccountIcon(String account) {
    final acc = account.toLowerCase();
    if (acc.contains('cartão') || acc.contains('cartao') || acc.contains('crédito')) {
      return Icons.credit_card;
    }
    if (acc.contains('carteira') || acc.contains('dinheiro')) {
      return Icons.wallet;
    }
    return Icons.account_balance;
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
              if (val == 'manage_accounts') _openManageAccountsDialog();
              if (val == 'export_csv') _exportBackup('csv');
              if (val == 'export_json') _exportBackup('json');
              if (val == 'restore') _restoreBackup();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'manage_accounts',
                child: Row(
                  children: [
                    Icon(Icons.credit_card, size: 18, color: Colors.teal),
                    SizedBox(width: 8),
                    Text('Gerenciar Contas/Cartões'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'export_csv', child: Text('Exportar Planilha (CSV)')),
              const PopupMenuItem(value: 'export_json', child: Text('Exportar Backup Completo (JSON)')),
              const PopupMenuItem(value: 'restore', child: Text('Restaurar Último Backup (JSON)')),
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

    final allAccountsList = ['Todas', ..._customAccounts];

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _buildMonthSelector(monthFormat),
        _buildAccountFilterBar(allAccountsList),
        _buildConsolidatedSummaryCard(formatCurrency),
        _buildBudgetProgressBar(formatCurrency),
        if (_expenseByCategory.isNotEmpty) ...[
          _buildPieChartSection(formatCurrency),
          _buildCategoryBreakdown(formatCurrency),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Lançamentos (${_selectedAccountFilter})',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              Text(
                '${_filteredTransactions.length} item(ns)',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        _filteredTransactions.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(32.0),
                child: Center(
                  child: Text(
                    'Nenhum lançamento neste mês para o filtro selecionado.',
                    textAlign: TextAlign.center,
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
                  final isRecurringOrInstallment = item.groupId != null;

                  return Dismissible(
                    key: Key('${item.id}_${item.title}_${item.date.toIso8601String()}'),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (direction) async {
                      _confirmDeleteTransaction(item);
                      return false; // O diálogo cuida da remoção
                    },
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      color: Colors.redAccent.withOpacity(0.8),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
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
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w500)),
                          ),
                          if (isRecurringOrInstallment)
                            Padding(
                              padding: const EdgeInsets.only(left: 4.0),
                              child: Icon(
                                Icons.repeat,
                                size: 14,
                                color: Colors.teal.shade200,
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                          '${item.category} • ${item.account}\n${DateFormat('dd/MM/yyyy').format(item.date)}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${isIncome ? '+' : '-'} ${formatCurrency.format(item.amount)}',
                            style: TextStyle(
                              color: isIncome ? Colors.green : Colors.redAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                            onPressed: () => _confirmDeleteTransaction(item),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
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

  Widget _buildAccountFilterBar(List<String> accounts) {
    return Container(
      height: 44,
      margin: const EdgeInsets.only(bottom: 6.0),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        itemCount: accounts.length,
        itemBuilder: (ctx, index) {
          final acc = accounts[index];
          final isSelected = _selectedAccountFilter == acc;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: FilterChip(
              avatar: acc == 'Todas'
                  ? const Icon(Icons.all_inclusive, size: 16)
                  : Icon(_getAccountIcon(acc), size: 16),
              label: Text(acc, style: const TextStyle(fontSize: 12)),
              selected: isSelected,
              selectedColor: Colors.teal.withOpacity(0.3),
              checkmarkColor: Colors.tealAccent,
              onSelected: (selected) {
                setState(() {
                  _selectedAccountFilter = acc;
                });
              },
            ),
          );
        },
      ),
    );
  }

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
            Text(
              _selectedAccountFilter == 'Todas' ? 'Saldo Consolidado Total' : 'Saldo: $_selectedAccountFilter',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
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

  // Parcelado
  bool _isInstallment = false;
  int _installmentsCount = 2;
  bool _amountIsTotal = true;

  // Recorrente Indefinido (Fixo)
  bool _isRecurring = false;

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
      _selectedAccount = item.account;
      _type = item.type;
      _chosenDate = item.date;
    } else {
      _titleController = TextEditingController();
      _amountController = TextEditingController();
      _categoryController = TextEditingController(text: 'Alimentação');
      _selectedAccount = widget.availableAccounts.isNotEmpty ? widget.availableAccounts.first : 'Conta Principal';
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
          decoration: const InputDecoration(
            labelText: 'Nome (ex: Nubank, Cartão XP)',
            border: OutlineInputBorder(),
          ),
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
        type: _type,
      );
      await DBHelper.instance.updateTransaction(item);
    } else {
      final generatedGroupId = DateTime.now().millisecondsSinceEpoch.toString();

      if (_isRecurring) {
        // Projeta repetição indefinida (24 meses com mesmo groupId)
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
              type: _type,
            ),
          );
        }
        await DBHelper.instance.insertMultipleTransactions(items);
      } else if (_type == TransactionType.expense && _isInstallment && _installmentsCount > 1) {
        // Parcelamento fixo com groupId
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
              type: TransactionType.expense,
            ),
          );
        }
        await DBHelper.instance.insertMultipleTransactions(items);
      } else {
        // Lançamento comum avulso
        final item = TransactionItem(
          title: title,
          amount: rawAmount,
          date: _chosenDate,
          category: category,
          account: _selectedAccount,
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
                onSelectionChanged: (newVal) {
                  setState(() {
                    _type = newVal.first;
                    if (_type == TransactionType.income) {
                      _isInstallment = false;
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Descrição (ex: Aluguel, Salário, Celular)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: (_isInstallment && !_amountIsTotal)
                      ? 'Valor de Cada Parcela (R\$)'
                      : 'Valor ${(_isInstallment) ? 'Total da Compra' : ''} (R\$)',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
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
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: widget.availableAccounts.map((acc) {
                        return DropdownMenuItem<String>(
                          value: acc,
                          child: Text(acc),
                        );
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
                    tooltip: 'Criar Nova Conta/Cartão',
                  ),
                ],
              ),

              if (!isEdit) ...[
                const SizedBox(height: 8),
                // Opção 1: Repetir Mensalmente (Fixo)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Repetir todo mês (Fixo)', style: TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: const Text('Projeta despesa ou receita recorrente'),
                  value: _isRecurring,
                  onChanged: (val) {
                    setState(() {
                      _isRecurring = val;
                      if (val) _isInstallment = false;
                    });
                  },
                ),

                // Opção 2: Compra Parcelada (somente para despesas)
                if (_type == TransactionType.expense && !_isRecurring) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Compra Parcelada?', style: TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text(_isInstallment ? 'Dividir em múltiplos meses' : 'Lançamento à vista'),
                    value: _isInstallment,
                    onChanged: (val) => setState(() => _isInstallment = val),
                  ),
                  if (_isInstallment) ...[
                    Row(
                      children: [
                        const Text('Número de parcelas: ', style: TextStyle(fontSize: 13)),
                        const SizedBox(width: 8),
                        DropdownButton<int>(
                          value: _installmentsCount,
                          dropdownColor: Colors.grey[900],
                          items: List.generate(35, (index) => index + 2).map((num) {
                            return DropdownMenuItem<int>(
                              value: num,
                              child: Text('${num}x', style: const TextStyle(fontWeight: FontWeight.bold)),
                            );
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
                            title: const Text('Valor Total', style: TextStyle(fontSize: 12)),
                            value: true,
                            groupValue: _amountIsTotal,
                            onChanged: (val) => setState(() => _amountIsTotal = val!),
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<bool>(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Valor da Parcela', style: TextStyle(fontSize: 12)),
                            value: false,
                            groupValue: _amountIsTotal,
                            onChanged: (val) => setState(() => _amountIsTotal = val!),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                  ],
                ],
              ],

              const SizedBox(height: 8),
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
                title: Text(
                  _isInstallment
                      ? '1ª Parcela em: ${DateFormat('dd/MM/yyyy').format(_chosenDate)}'
                      : (_isRecurring
                          ? 'Início em: ${DateFormat('dd/MM/yyyy').format(_chosenDate)}'
                          : 'Data: ${DateFormat('dd/MM/yyyy').format(_chosenDate)}'),
                ),
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
                child: Text(
                  isEdit
                      ? 'Salvar Alterações'
                      : (_isRecurring
                          ? 'Salvar Lançamento Recorrente'
                          : (_isInstallment
                              ? 'Gerar $_installmentsCount Parcelas'
                              : 'Salvar Lançamento')),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
