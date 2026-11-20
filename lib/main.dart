import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/transaction_model.dart';
import 'services/db_helper.dart';

String? globalShortcutType;

const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR', null);

  String? initError;
  final cleanUrl = _supabaseUrl.trim();
  final cleanKey = _supabaseAnonKey.trim();

  if (cleanUrl.isEmpty || cleanKey.isEmpty) {
    initError =
        'Chaves do Supabase não carregadas no build (URL vazia: ${cleanUrl.isEmpty}, Key vazia: ${cleanKey.isEmpty}).';
  } else {
    try {
      await Supabase.initialize(
        url: cleanUrl,
        anonKey: cleanKey,
      );
    } catch (e) {
      initError = 'Erro ao inicializar Supabase: $e';
    }
  }

  if (!kIsWeb) {
    const quickActions = QuickActions();
    quickActions.initialize((type) {
      globalShortcutType = type;
    });

    quickActions.setShortcutItems(<ShortcutItem>[
      const ShortcutItem(
        type: 'action_new_expense',
        localizedTitle: 'Nova Despesa',
        icon: 'ic_launcher',
      ),
    ]);
  }

  runApp(FinanceApp(initError: initError));
}

class FinanceApp extends StatelessWidget {
  final String? initError;
  const FinanceApp({super.key, this.initError});

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
      home: initError != null
          ? Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: SelectableText(
                    initError!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          : const AuthGate(),
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
  bool _isBiometricPassed = kIsWeb;
  bool _biometricChecked = false;

  @override
  void initState() {
    super.initState();
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (mounted) {
        setState(() {
          if (data.session == null) {
            _isBiometricPassed = kIsWeb;
            _biometricChecked = false;
          }
        });
      }
    });
  }

  Future<void> _checkBiometrics() async {
    if (_biometricChecked || kIsWeb) return;
    _biometricChecked = true;
    try {
      final canCheck =
          await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
      if (canCheck) {
        await _authenticate();
      } else {
        if (mounted) setState(() => _isBiometricPassed = true);
      }
    } catch (_) {
      if (mounted) setState(() => _isBiometricPassed = true);
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
      if (mounted) {
        setState(() => _isBiometricPassed = authenticated);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;

    if (session == null) {
      return const LoginScreen();
    }

    if (!kIsWeb && !_isBiometricPassed) {
      if (!_biometricChecked) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _checkBiometrics());
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
                  style:
                      ElevatedButton.styleFrom(minimumSize: const Size(200, 48)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return const HomeScreen();
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMsg;

  Future<void> _signIn() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMsg = 'Preencha e-mail e senha.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } on AuthException catch (e) {
      setState(() => _errorMsg = e.message);
    } catch (e) {
      setState(() => _errorMsg = 'Erro ao conectar: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.account_balance_wallet,
                    size: 64, color: Colors.teal),
                const SizedBox(height: 16),
                const Text(
                  'Sou Mais Controlado',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Acesse sua conta para sincronizar seus dados',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  onSubmitted: (_) => _signIn(),
                  decoration: InputDecoration(
                    labelText: 'Senha',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ),
                if (_errorMsg != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMsg!,
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(color: Colors.redAccent, fontSize: 12.5),
                  ),
                ],
                const SizedBox(height: 22),
                ElevatedButton(
                  onPressed: _isLoading ? null : _signIn,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Entrar'),
                ),
              ],
            ),
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
  List<AccountInfo> _accountsMeta = [];
  bool _isLoading = true;
  String? _errorMessage;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  String _selectedAccountFilter = 'Todas';

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _refreshTransactions().then((_) {
      _checkPendingShortcut();
    });

    if (!kIsWeb) {
      const QuickActions().initialize((type) {
        if (type == 'action_new_expense') {
          _openTransactionModal();
        }
      });
    }
  }

  void _checkPendingShortcut() {
    if (!kIsWeb && globalShortcutType == 'action_new_expense') {
      globalShortcutType = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openTransactionModal();
      });
    }
  }

  Future<void> _refreshTransactions() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await DBHelper.instance.getAllTransactions();
      var meta = await DBHelper.instance.getAccountsMeta();

      final existingNames = meta.map((m) => m.name).toSet();
      for (final t in data) {
        if (!existingNames.contains(t.account)) {
          final newInfo = AccountInfo(name: t.account);
          await DBHelper.instance.saveAccountMeta(newInfo);
          meta.add(newInfo);
          existingNames.add(t.account);
        }
      }

      if (mounted) {
        setState(() {
          _allTransactions = data;
          _accountsMeta = meta;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro ao carregar dados: $e';
          _isLoading = false;
        });
      }
    }
  }

  List<TransactionItem> get _filteredTransactions {
    return _allTransactions.where((t) {
      final matchesMonth = t.date.year == _selectedMonth.year &&
          t.date.month == _selectedMonth.month;
      final matchesAccount = _selectedAccountFilter == 'Todas' ||
          t.account == _selectedAccountFilter;

      final query = _searchQuery.trim().toLowerCase();
      final matchesSearch = query.isEmpty ||
          t.title.toLowerCase().contains(query) ||
          t.category.toLowerCase().contains(query) ||
          t.account.toLowerCase().contains(query);

      return matchesMonth && matchesAccount && matchesSearch;
    }).toList();
  }

  Map<DateTime, List<TransactionItem>> get _groupedTransactions {
    final Map<DateTime, List<TransactionItem>> map = {};
    final list = [..._filteredTransactions];
    list.sort((a, b) => a.date.compareTo(b.date));

    for (var t in list) {
      final dayKey = DateTime(t.date.year, t.date.month, t.date.day);
      map.putIfAbsent(dayKey, () => []).add(t);
    }
    return map;
  }

  double get _accumulatedPreviousBalance {
    final firstDayOfSelectedMonth =
        DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final previousTransactions = _allTransactions.where((t) {
      final isBefore = t.date.isBefore(firstDayOfSelectedMonth);
      final matchesAccount = _selectedAccountFilter == 'Todas' ||
          t.account == _selectedAccountFilter;
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

  double get _consolidatedBalance =>
      _accumulatedPreviousBalance + _currentMonthBalance;

  void _changeMonth(int offset) {
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month + offset);
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
        content: Text(newStatus
            ? 'Lançamento efetivado'
            : 'Lançamento marcado como pendente'),
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
            'O lançamento "${item.title}" faz parte de uma série.\n\nComo deseja excluir?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar')),
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
              await DBHelper.instance
                  .deleteGroupFromDate(item.groupId!, item.date);
              _refreshTransactions();
            },
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
            title: const Text('Todas as repetições',
                style: TextStyle(color: Colors.redAccent)),
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
        availableAccounts: _accountsMeta,
        onAccountCreated: (newAcc) {
          _refreshTransactions();
        },
        onSaved: _refreshTransactions,
        onDeleteRequested: (itemToDelete) {
          _confirmDeleteTransaction(itemToDelete);
        },
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
                    const Text('Gerenciar Contas e Cartões',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop()),
                  ],
                ),
                const Divider(),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _accountsMeta.length,
                    itemBuilder: (context, index) {
                      final acc = _accountsMeta[index];
                      final count = _allTransactions
                          .where((t) => t.account == acc.name)
                          .length;

                      return ListTile(
                        dense: true,
                        leading: Icon(
                          acc.isCreditCard
                              ? Icons.credit_card
                              : Icons.account_balance_wallet,
                          color: Colors.teal,
                        ),
                        title: Text(acc.name),
                        subtitle: Text(
                          acc.isCreditCard
                              ? '$count lançamentos • Fecha dia ${acc.closingDay} / Vence dia ${acc.dueDay}'
                              : '$count lançamentos',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit,
                                  size: 18, color: Colors.tealAccent),
                              onPressed: () => _showEditAccountDialog(acc, () {
                                setModalState(() {});
                                _refreshTransactions();
                              }),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  size: 18, color: Colors.redAccent),
                              onPressed: () =>
                                  _showDeleteAccountDialog(acc.name, count, () {
                                setModalState(() {});
                                _refreshTransactions();
                              }),
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

  void _showEditAccountDialog(
      AccountInfo account, VoidCallback onUpdatedModal) {
    final nameCtrl = TextEditingController(text: account.name);
    bool isCreditCard = account.isCreditCard;
    int closingDay = account.closingDay;
    int dueDay = account.dueDay;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Editar Conta / Cartão'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Nome', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('É Cartão de Crédito?'),
                  value: isCreditCard,
                  onChanged: (val) => setDialogState(() => isCreditCard = val),
                ),
                if (isCreditCard) ...[
                  Row(
                    children: [
                      const Text('Dia Fechamento: '),
                      const Spacer(),
                      DropdownButton<int>(
                        value: closingDay,
                        items: List.generate(31, (i) => i + 1)
                            .map((d) =>
                                DropdownMenuItem(value: d, child: Text('$d')))
                            .toList(),
                        onChanged: (val) =>
                            setDialogState(() => closingDay = val ?? 1),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('Dia Vencimento: '),
                      const Spacer(),
                      DropdownButton<int>(
                        value: dueDay,
                        items: List.generate(31, (i) => i + 1)
                            .map((d) =>
                                DropdownMenuItem(value: d, child: Text('$d')))
                            .toList(),
                        onChanged: (val) =>
                            setDialogState(() => dueDay = val ?? 10),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                final newName = nameCtrl.text.trim();
                if (newName.isNotEmpty) {
                  if (newName != account.name) {
                    await DBHelper.instance.renameAccount(account.name, newName);
                  }
                  final updatedInfo = AccountInfo(
                    name: newName,
                    isCreditCard: isCreditCard,
                    closingDay: closingDay,
                    dueDay: dueDay,
                  );
                  await DBHelper.instance.saveAccountMeta(updatedInfo);
                  onUpdatedModal();
                  if (mounted) Navigator.of(ctx).pop();
                }
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteAccountDialog(
      String accountName, int transactionsCount, VoidCallback onUpdatedModal) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Excluir "$accountName"?'),
        content: Text(
            'A conta e todas as $transactionsCount transações vinculadas serão apagadas.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              await DBHelper.instance
                  .deleteAccountAndTransactions(accountName);
              setState(() {
                if (_selectedAccountFilter == accountName) {
                  _selectedAccountFilter = 'Todas';
                }
              });
              onUpdatedModal();
              if (mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Excluir Tudo',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _exportMonthPDF() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Exportação em PDF disponível no aplicativo Android.')),
      );
      return;
    }

    final pdf = pw.Document();
    final formatCurrency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final monthTitle =
        DateFormat('MMMM yyyy', 'pt_BR').format(_selectedMonth).toUpperCase();

    final items = [..._filteredTransactions];
    items.sort((a, b) => a.date.compareTo(b.date));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Sou Mais Controlado - Extrato Mensal',
                      style: pw.TextStyle(
                          fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  pw.Text(monthTitle,
                      style: pw.TextStyle(
                          fontSize: 14, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400)),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  pw.Text(
                      'Acumulado Anterior: ${formatCurrency.format(_accumulatedPreviousBalance)}'),
                  pw.Text('Receitas: ${formatCurrency.format(_totalIncome)}'),
                  pw.Text('Despesas: ${formatCurrency.format(_totalExpense)}'),
                  pw.Text(
                      'Saldo Final: ${formatCurrency.format(_consolidatedBalance)}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            pw.SizedBox(height: 15),
            pw.TableHelper.fromTextArray(
              headers: [
                'Data',
                'Descrição',
                'Categoria',
                'Conta',
                'Valor',
                'Status'
              ],
              data: items.map((t) {
                return [
                  DateFormat('dd/MM/yyyy').format(t.date),
                  t.title,
                  t.category,
                  t.account,
                  '${t.type == TransactionType.income ? '+' : '-'} ${t.amount.toStringAsFixed(2).replaceAll('.', ',')}',
                  t.isCompleted ? 'Efetivado' : 'Pendente',
                ];
              }).toList(),
              headerStyle:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
              cellHeight: 22,
            ),
          ];
        },
      ),
    );

    try {
      Directory targetDir;
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (downloadDir.existsSync()) {
        targetDir = downloadDir;
      } else {
        targetDir = await getExternalStorageDirectory() ??
            await getApplicationDocumentsDirectory();
      }

      final fileName =
          'Extrato_Financas_${DateFormat('yyyy_MM').format(_selectedMonth)}.pdf';
      final file = File('${targetDir.path}/$fileName');
      await file.writeAsBytes(await pdf.save());

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('PDF Gerado com Sucesso!'),
          content: Text(
              'O arquivo do extrato mensal foi salvo em:\n\n${file.path}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar PDF: $e')),
      );
    }
  }

  Future<void> _exportBackup(String format) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Seus dados já estão sincronizados na nuvem (Supabase).')),
      );
      return;
    }
    if (_allTransactions.isEmpty) return;
    try {
      final dir = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final nowStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());

      if (format == 'csv') {
        final file = File('${dir.path}/backup_financas_$nowStr.csv');
        final buffer = StringBuffer();
        buffer.writeln(
            'ID,Título,Valor,Data,Categoria,Conta_Cartao,GroupId,Efetivado,Tipo');
        for (final t in _allTransactions) {
          buffer.writeln(
              '${t.id},"${t.title}",${t.amount},${t.date.toIso8601String()},"${t.category}","${t.account}","${t.groupId ?? ''}",${t.isCompleted ? 1 : 0},${t.type.name}');
        }
        await file.writeAsString(buffer.toString());
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('CSV salvo em: ${file.path}')));
        }
      } else {
        final file = File('${dir.path}/backup_financas_$nowStr.json');
        final list = _allTransactions.map((t) => t.toMap()).toList();
        await file.writeAsString(jsonEncode(list));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('JSON salvo em: ${file.path}')));
        }
      }
    } catch (_) {}
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final formatCurrency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final monthFormat = DateFormat('MMMM yyyy', 'pt_BR');

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(
                  hintText: 'Buscar por título, categoria ou conta...',
                  border: InputBorder.none,
                ),
                onChanged: (val) {
                  setState(() => _searchQuery = val);
                },
              )
            : const Text('Sou Mais Controlado', style: TextStyle(fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, size: 20),
            tooltip: 'Sincronizar',
            onPressed: _refreshTransactions,
          ),
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search, size: 22),
            tooltip: _isSearching ? 'Fechar busca' : 'Buscar',
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                  _searchQuery = '';
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'manage_accounts') _openManageAccountsDialog();
              if (val == 'export_pdf') _exportMonthPDF();
              if (val == 'export_csv') _exportBackup('csv');
              if (val == 'export_json') _exportBackup('json');
              if (val == 'logout') _signOut();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                  value: 'manage_accounts',
                  child: Text('Gerenciar Contas/Cartões')),
              if (!kIsWeb) ...[
                const PopupMenuItem(
                    value: 'export_pdf', child: Text('Exportar Mês em PDF')),
                const PopupMenuDivider(),
                const PopupMenuItem(
                    value: 'export_csv', child: Text('Exportar Planilha (CSV)')),
                const PopupMenuItem(
                    value: 'export_json', child: Text('Exportar Backup (JSON)')),
              ],
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Text('Sair da Conta',
                    style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: _buildBody(formatCurrency, monthFormat),
        ),
      ),
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _refreshTransactions,
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    final allAccountsList = ['Todas', ..._accountsMeta.map((a) => a.name)];
    final grouped = _groupedTransactions;

    return RefreshIndicator(
      onRefresh: _refreshTransactions,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildMonthSelector(monthFormat),
          _buildAccountFilterBar(allAccountsList),
          _buildConsolidatedSummaryCard(formatCurrency),
          if (grouped.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Center(
                child: Text(
                  _searchQuery.isNotEmpty
                      ? 'Nenhum lançamento encontrado para "$_searchQuery".'
                      : 'Nenhum lançamento neste mês para o filtro selecionado.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
            )
          else
            ...grouped.entries.map((entry) {
              final date = entry.key;
              final items = entry.value;

              final dayIncome = items
                  .where((t) => t.type == TransactionType.income)
                  .fold(0.0, (sum, t) => sum + t.amount);
              final dayExpense = items
                  .where((t) => t.type == TransactionType.expense)
                  .fold(0.0, (sum, t) => sum + t.amount);
              final dayBalance = dayIncome - dayExpense;

              final dayTitle =
                  '${DateFormat('dd/MM/yyyy', 'pt_BR').format(date)}, ${toBeginningOfSentenceCase(DateFormat('EEEE', 'pt_BR').format(date))}';

              return Container(
                margin: const EdgeInsets.only(top: 8.0, bottom: 4.0),
                decoration: BoxDecoration(
                  border: Border(
                      bottom:
                          BorderSide(color: Colors.white.withOpacity(0.08))),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      color: Colors.white.withOpacity(0.04),
                      child: Text(
                        dayTitle,
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.2),
                      ),
                    ),
                    ...items.asMap().entries.map((itemEntry) {
                      final idx = itemEntry.key;
                      final item = itemEntry.value;
                      final isIncome = item.type == TransactionType.income;
                      final isEven = idx % 2 == 0;

                      return InkWell(
                        onTap: () => _openTransactionModal(item),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          color: isEven
                              ? Colors.transparent
                              : Colors.white.withOpacity(0.035),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: item.isCompleted,
                                  activeColor: Colors.teal,
                                  checkColor: Colors.black,
                                  side: BorderSide(
                                      color: Colors.grey.shade600, width: 1.2),
                                  onChanged: (val) =>
                                      _toggleTransactionEffective(item),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                flex: 4,
                                child: Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  item.category,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: Colors.grey.shade400),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  item.account,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: Colors.grey.shade400),
                                ),
                              ),
                              Text(
                                '${isIncome ? '+' : '-'} ${item.amount.toStringAsFixed(2).replaceAll('.', ',')}',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: isIncome
                                      ? Colors.greenAccent.shade400
                                      : Colors.redAccent.shade100,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    Padding(
                      padding: const EdgeInsets.only(
                          top: 4.0, bottom: 4.0, right: 12.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('Saldo do dia: ',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade400)),
                          Text(
                            'R\$ ${dayBalance.toStringAsFixed(2).replaceAll('.', ',')}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: dayBalance >= 0
                                  ? Colors.white
                                  : Colors.redAccent.shade100,
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
      ),
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
                    const Text('Acumulado Anterior',
                        style: TextStyle(fontSize: 10.5, color: Colors.grey)),
                    Text(
                      formatter.format(_accumulatedPreviousBalance),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _accumulatedPreviousBalance >= 0
                            ? Colors.greenAccent
                            : Colors.redAccent,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Saldo do Mês',
                        style: TextStyle(fontSize: 10.5, color: Colors.grey)),
                    Text(
                      formatter.format(_currentMonthBalance),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _currentMonthBalance >= 0
                            ? Colors.greenAccent
                            : Colors.redAccent,
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
                  _selectedAccountFilter == 'Todas'
                      ? 'Consolidado:'
                      : 'Saldo ($_selectedAccountFilter):',
                  style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                ),
                Text(
                  formatter.format(_consolidatedBalance),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _consolidatedBalance >= 0
                        ? Colors.white
                        : Colors.redAccent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum FormMode { expense, income, transfer }

class TransactionFormModal extends StatefulWidget {
  final DateTime defaultDate;
  final TransactionItem? existingItem;
  final List<AccountInfo> availableAccounts;
  final Function(String) onAccountCreated;
  final VoidCallback onSaved;
  final Function(TransactionItem)? onDeleteRequested;

  const TransactionFormModal({
    super.key,
    required this.defaultDate,
    this.existingItem,
    required this.availableAccounts,
    required this.onAccountCreated,
    required this.onSaved,
    this.onDeleteRequested,
  });

  @override
  State<TransactionFormModal> createState() => _TransactionFormModalState();
}

class _TransactionFormModalState extends State<TransactionFormModal> {
  late TextEditingController _titleController;
  late TextEditingController _amountController;
  late TextEditingController _categoryController;
  late String _selectedAccount;
  late String _destinationAccount;
  FormMode _formMode = FormMode.expense;
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
      _amountController =
          TextEditingController(text: item.amount.toStringAsFixed(2));
      _categoryController = TextEditingController(text: item.category);
      _selectedAccount = item.account;
      _destinationAccount = widget.availableAccounts
          .map((a) => a.name)
          .firstWhere((a) => a != item.account,
              orElse: () => 'Carteira / Dinheiro');
      _formMode =
          item.type == TransactionType.income ? FormMode.income : FormMode.expense;
      _chosenDate = item.date;
      _isCompleted = item.isCompleted;
    } else {
      _titleController = TextEditingController();
      _amountController = TextEditingController();
      _categoryController = TextEditingController(text: 'Alimentação');
      _selectedAccount = widget.availableAccounts.isNotEmpty
          ? widget.availableAccounts.first.name
          : 'Conta Principal';
      _destinationAccount = widget.availableAccounts.length > 1
          ? widget.availableAccounts[1].name
          : 'Carteira / Dinheiro';
      final now = DateTime.now();
      _chosenDate = (widget.defaultDate.year == now.year &&
              widget.defaultDate.month == now.month)
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
    return DateTime(
        destYear, destMonth, destDay, date.hour, date.minute, date.second);
  }

  DateTime _calculateCreditCardDate(DateTime purchaseDate, AccountInfo card) {
    DateTime invoiceDueDate;
    if (purchaseDate.day >= card.closingDay) {
      final nextMonth = _addMonths(purchaseDate, 1);
      final daysInMonth = DateTime(nextMonth.year, nextMonth.month + 1, 0).day;
      final dueDay = min(card.dueDay, daysInMonth);
      invoiceDueDate = DateTime(nextMonth.year, nextMonth.month, dueDay);
    } else {
      final daysInMonth =
          DateTime(purchaseDate.year, purchaseDate.month + 1, 0).day;
      final dueDay = min(card.dueDay, daysInMonth);
      invoiceDueDate = DateTime(purchaseDate.year, purchaseDate.month, dueDay);
    }
    return invoiceDueDate;
  }

  void _showNewAccountDialog() {
    final nameCtrl = TextEditingController();
    bool isCreditCard = false;
    int closingDay = 25;
    int dueDay = 5;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nova Conta ou Cartão'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                      labelText: 'Nome (ex: Nubank, Cartão XP)',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('É Cartão de Crédito?'),
                  value: isCreditCard,
                  onChanged: (val) => setDialogState(() => isCreditCard = val),
                ),
                if (isCreditCard) ...[
                  Row(
                    children: [
                      const Text('Dia Fechamento: '),
                      const Spacer(),
                      DropdownButton<int>(
                        value: closingDay,
                        items: List.generate(31, (i) => i + 1)
                            .map((d) =>
                                DropdownMenuItem(value: d, child: Text('$d')))
                            .toList(),
                        onChanged: (val) =>
                            setDialogState(() => closingDay = val ?? 1),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('Dia Vencimento: '),
                      const Spacer(),
                      DropdownButton<int>(
                        value: dueDay,
                        items: List.generate(31, (i) => i + 1)
                            .map((d) =>
                                DropdownMenuItem(value: d, child: Text('$d')))
                            .toList(),
                        onChanged: (val) =>
                            setDialogState(() => dueDay = val ?? 10),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                final text = nameCtrl.text.trim();
                if (text.isNotEmpty) {
                  final info = AccountInfo(
                      name: text,
                      isCreditCard: isCreditCard,
                      closingDay: closingDay,
                      dueDay: dueDay);
                  await DBHelper.instance.saveAccountMeta(info);
                  widget.onAccountCreated(text);
                  setState(() => _selectedAccount = text);
                  if (mounted) Navigator.of(ctx).pop();
                }
              },
              child: const Text('Adicionar'),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() async {
    final rawAmount =
        double.tryParse(_amountController.text.replaceAll(',', '.')) ?? 0.0;
    if (rawAmount <= 0) return;

    final isEdit = widget.existingItem != null;

    if (_formMode == FormMode.transfer && !isEdit) {
      if (_selectedAccount == _destinationAccount) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('A conta de origem e destino não podem ser iguais.')),
        );
        return;
      }

      final transferTitle = _titleController.text.trim().isEmpty
          ? 'Transferência: $_selectedAccount ➔ $_destinationAccount'
          : _titleController.text.trim();

      final groupId = DateTime.now().millisecondsSinceEpoch.toString();

      final outItem = TransactionItem(
        title: transferTitle,
        amount: rawAmount,
        date: _chosenDate,
        category: 'Transferência',
        account: _selectedAccount,
        groupId: groupId,
        isCompleted: _isCompleted,
        type: TransactionType.expense,
      );

      final inItem = TransactionItem(
        title: transferTitle,
        amount: rawAmount,
        date: _chosenDate,
        category: 'Transferência',
        account: _destinationAccount,
        groupId: groupId,
        isCompleted: _isCompleted,
        type: TransactionType.income,
      );

      await DBHelper.instance.insertMultipleTransactions([outItem, inItem]);
      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final title = _titleController.text.trim();
    final category = _categoryController.text.trim();
    if (title.isEmpty || category.isEmpty) return;

    final type = _formMode == FormMode.income
        ? TransactionType.income
        : TransactionType.expense;

    final currentCardMeta = widget.availableAccounts.firstWhere(
      (a) => a.name == _selectedAccount,
      orElse: () => AccountInfo(name: _selectedAccount),
    );

    DateTime effectiveDate = _chosenDate;
    if (type == TransactionType.expense &&
        currentCardMeta.isCreditCard &&
        !isEdit) {
      effectiveDate = _calculateCreditCardDate(_chosenDate, currentCardMeta);
    }

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
        type: type,
      );
      await DBHelper.instance.updateTransaction(item);
    } else {
      final generatedGroupId =
          DateTime.now().millisecondsSinceEpoch.toString();

      if (_isRecurring) {
        final items = <TransactionItem>[];
        for (int i = 0; i < 24; i++) {
          final recurDate = _addMonths(effectiveDate, i);
          items.add(
            TransactionItem(
              title: title,
              amount: rawAmount,
              date: recurDate,
              category: category,
              account: _selectedAccount,
              groupId: generatedGroupId,
              isCompleted: i == 0 ? _isCompleted : false,
              type: type,
            ),
          );
        }
        await DBHelper.instance.insertMultipleTransactions(items);
      } else if (type == TransactionType.expense &&
          _isInstallment &&
          _installmentsCount > 1) {
        final installmentAmount = _amountIsTotal
            ? double.parse((rawAmount / _installmentsCount).toStringAsFixed(2))
            : rawAmount;

        final items = <TransactionItem>[];
        for (int i = 1; i <= _installmentsCount; i++) {
          final installmentDate = _addMonths(effectiveDate, i - 1);
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
          date: effectiveDate,
          category: category,
          account: _selectedAccount,
          isCompleted: _isCompleted,
          type: type,
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
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: SegmentedButton<FormMode>(
                  segments: [
                    const ButtonSegment(
                        value: FormMode.expense,
                        label: Text('Despesa', style: TextStyle(fontSize: 12))),
                    const ButtonSegment(
                        value: FormMode.income,
                        label: Text('Receita', style: TextStyle(fontSize: 12))),
                    if (!isEdit)
                      const ButtonSegment(
                          value: FormMode.transfer,
                          label:
                              Text('Transf.', style: TextStyle(fontSize: 12))),
                  ],
                  selected: {_formMode},
                  onSelectionChanged: (newVal) {
                    setState(() {
                      _formMode = newVal.first;
                      if (_formMode != FormMode.expense) _isInstallment = false;
                      if (_formMode == FormMode.transfer) _isRecurring = false;
                    });
                  },
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: _formMode == FormMode.transfer
                      ? 'Descrição (Opcional)'
                      : 'Descrição',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: (_isInstallment && !_amountIsTotal)
                      ? 'Valor da Parcela (R\$)'
                      : 'Valor Total (R\$)',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              if (_formMode == FormMode.transfer) ...[
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: widget.availableAccounts
                                .any((a) => a.name == _selectedAccount)
                            ? _selectedAccount
                            : widget.availableAccounts.first.name,
                        decoration: const InputDecoration(
                          labelText: 'Conta Origem (Sai)',
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        items: widget.availableAccounts.map((acc) {
                          return DropdownMenuItem<String>(
                              value: acc.name,
                              child: Text(acc.name,
                                  style: const TextStyle(fontSize: 12)));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedAccount = val);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: widget.availableAccounts
                                .any((a) => a.name == _destinationAccount)
                            ? _destinationAccount
                            : widget.availableAccounts.last.name,
                        decoration: const InputDecoration(
                          labelText: 'Conta Destino (Entra)',
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        items: widget.availableAccounts.map((acc) {
                          return DropdownMenuItem<String>(
                              value: acc.name,
                              child: Text(acc.name,
                                  style: const TextStyle(fontSize: 12)));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _destinationAccount = val);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: widget.availableAccounts
                                .any((a) => a.name == _selectedAccount)
                            ? _selectedAccount
                            : widget.availableAccounts.first.name,
                        decoration: const InputDecoration(
                          labelText: 'Conta ou Cartão',
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        items: widget.availableAccounts.map((acc) {
                          return DropdownMenuItem<String>(
                              value: acc.name, child: Text(acc.name));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedAccount = val);
                          }
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
              ],
              const SizedBox(height: 6),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Lançamento Efetivado / Concluído',
                    style: TextStyle(fontSize: 13)),
                value: _isCompleted,
                activeColor: Colors.teal,
                onChanged: (val) => setState(() => _isCompleted = val ?? true),
              ),
              if (!isEdit && _formMode != FormMode.transfer) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Repetir todo mês (Fixo)',
                      style: TextStyle(fontSize: 13)),
                  value: _isRecurring,
                  onChanged: (val) {
                    setState(() {
                      _isRecurring = val;
                      if (val) _isInstallment = false;
                    });
                  },
                ),
                if (_formMode == FormMode.expense && !_isRecurring) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Compra Parcelada?',
                        style: TextStyle(fontSize: 13)),
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
                            return DropdownMenuItem<int>(
                                value: num, child: Text('${num}x'));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _installmentsCount = val);
                            }
                          },
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile<bool>(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Total',
                                style: TextStyle(fontSize: 11)),
                            value: true,
                            groupValue: _amountIsTotal,
                            onChanged: (val) =>
                                setState(() => _amountIsTotal = val!),
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<bool>(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Por Parcela',
                                style: TextStyle(fontSize: 11)),
                            value: false,
                            groupValue: _amountIsTotal,
                            onChanged: (val) =>
                                setState(() => _amountIsTotal = val!),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
              if (_formMode != FormMode.transfer) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _quickCategories.map((cat) {
                    final isSelected =
                        _categoryController.text.toLowerCase() ==
                            cat.toLowerCase();
                    return ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(cat, style: const TextStyle(fontSize: 11)),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _categoryController.text = cat);
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _categoryController,
                  decoration: const InputDecoration(
                      labelText: 'Categoria', border: OutlineInputBorder()),
                ),
              ],
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today, size: 20),
                title: Text(
                    'Data: ${DateFormat('dd/MM/yyyy').format(_chosenDate)}',
                    style: const TextStyle(fontSize: 13)),
                trailing: TextButton(
                    onPressed: _pickDate, child: const Text('Alterar')),
              ),
              const SizedBox(height: 10),
              if (isEdit)
                Row(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        minimumSize: const Size(110, 44),
                      ),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Excluir'),
                      onPressed: () {
                        Navigator.of(context).pop();
                        if (widget.onDeleteRequested != null &&
                            widget.existingItem != null) {
                          widget.onDeleteRequested!(widget.existingItem!);
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(44)),
                        child: const Text('Salvar Alterações'),
                      ),
                    ),
                  ],
                )
              else
                ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44)),
                  child: Text(
                    _formMode == FormMode.transfer
                        ? 'Realizar Transferência'
                        : (_isRecurring
                            ? 'Salvar Lançamento Recorrente'
                            : (_isInstallment
                                ? 'Gerar $_installmentsCount Parcelas'
                                : 'Salvar Lançamento')),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
