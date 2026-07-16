import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/barcode_utils.dart';
import '../models/product.dart';
import '../models/return_record.dart';
import '../services/product_catalog.dart';
import '../services/return_storage.dart';
import 'scanner_page.dart';

enum WorkflowStage { order, product }

class ReturnsHomePage extends StatefulWidget {
  const ReturnsHomePage({super.key});

  @override
  State<ReturnsHomePage> createState() => _ReturnsHomePageState();
}

class _ReturnsHomePageState extends State<ReturnsHomePage> {
  final _catalog = ProductCatalog();
  final _storage = ReturnStorage();
  final _operatorController = TextEditingController();
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();

  final _marketplaces = const [
    'OZON',
    'Wildberries',
    'Яндекс Маркет',
    'СДЭК',
    'Другой',
  ];
  final _shifts = const ['День', 'Ночь', '1 смена', '2 смена'];
  final _conditions = const [
    'Принят',
    'Брак',
    'Не тот товар',
    'Некомплект',
    'Не читается код',
  ];

  List<ReturnRecord> _records = [];
  WorkflowStage _stage = WorkflowStage.order;
  String _currentOrderCode = '';
  String _marketplace = 'OZON';
  String _shift = 'День';
  String _condition = 'Принят';
  int _selectedTab = 0;
  bool _loading = true;
  bool _processing = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _operatorController.dispose();
    _inputController.dispose();
    _inputFocus.dispose();
    _catalog.close();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      await _catalog.initialize();
      final records = await _storage.loadRecords();
      final settings = await _storage.loadSettings();
      _records = records;
      _operatorController.text = settings['operatorName'] as String? ?? '';
      _marketplace = _validValue(
        settings['marketplace'] as String?,
        _marketplaces,
        _marketplace,
      );
      _shift = _validValue(
        settings['shift'] as String?,
        _shifts,
        _shift,
      );
      _condition = _validValue(
        settings['condition'] as String?,
        _conditions,
        _condition,
      );
    } catch (error) {
      _loadError = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _validValue(String? value, List<String> values, String fallback) {
    return value != null && values.contains(value) ? value : fallback;
  }

  Future<void> _saveSettings() async {
    await _storage.saveSettings({
      'operatorName': _operatorController.text.trim(),
      'marketplace': _marketplace,
      'shift': _shift,
      'condition': _condition,
    });
  }

  Future<void> _openScanner() async {
    if (_processing) return;
    final isOrder = _stage == WorkflowStage.order;
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => ScannerPage(
          title: isOrder ? 'Сканирование заказа' : 'Сканирование товара',
          hint: isOrder
              ? 'Наведите рамку на код заказа. Товар сканируется следующим шагом.'
              : 'Наведите рамку на штрихкод товара.',
        ),
      ),
    );
    if (result != null && mounted) await _processCode(result);
  }

  Future<void> _submitInput() async {
    final value = _inputController.text;
    _inputController.clear();
    await _processCode(value);
    if (mounted) _inputFocus.requestFocus();
  }

  Future<void> _processCode(String rawValue) async {
    if (_processing) return;
    final value = cleanScannedValue(rawValue);
    if (value.isEmpty) {
      _showMessage('Код не получен. Повторите сканирование.');
      return;
    }

    setState(() => _processing = true);
    try {
      if (_stage == WorkflowStage.order) {
        await _acceptOrder(value);
      } else {
        await _acceptProductCode(value);
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _acceptOrder(String value) async {
    await HapticFeedback.mediumImpact();
    await SystemSound.play(SystemSoundType.click);
    setState(() {
      _currentOrderCode = value;
      _stage = WorkflowStage.product;
    });
    _showMessage('Заказ принят. Теперь сканируйте товар.', success: true);
  }

  Future<void> _acceptProductCode(String value) async {
    if (_currentOrderCode.isEmpty) {
      setState(() => _stage = WorkflowStage.order);
      _showMessage('Сначала отсканируйте код заказа.');
      return;
    }

    final barcode = normalizeProductBarcode(value);
    final matches = await _catalog.findByBarcode(barcode);
    if (!mounted) return;

    if (matches.length == 1) {
      await _addProduct(matches.single, scannedBarcode: barcode);
      return;
    }
    if (matches.length > 1) {
      final selected = await _chooseProduct(matches, barcode);
      if (selected != null) {
        await _addProduct(selected, scannedBarcode: barcode);
      }
      return;
    }

    final resolution = await _resolveUnknownProduct(barcode);
    if (resolution != null) {
      await _addProduct(resolution, scannedBarcode: barcode);
    }
  }

  Future<Product?> _chooseProduct(List<Product> products, String barcode) {
    return showModalBottomSheet<Product>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          children: [
            Text(
              'Найдено несколько товаров',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text('ШК $barcode. Выберите наименование по этикетке.'),
            const SizedBox(height: 12),
            for (final product in products)
              Card(
                child: ListTile(
                  title: Text(product.name),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(context, product),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<Product?> _resolveUnknownProduct(String barcode) async {
    final nameController = TextEditingController();
    final action = await showDialog<_UnknownProductAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Штрихкод не найден'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('ШК $barcode отсутствует в справочнике.'),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              autofocus: true,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Наименование вручную',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(
              dialogContext,
              const _UnknownProductAction(searchCatalog: true),
            ),
            icon: const Icon(Icons.search),
            label: const Text('Поиск'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(
                  dialogContext,
                  _UnknownProductAction(manualName: name),
                );
              }
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (!mounted || action == null) return null;
    if (action.manualName != null) {
      return Product(barcode: barcode, name: action.manualName!);
    }
    if (action.searchCatalog) {
      final selected = await showSearch<Product?>(
        context: context,
        delegate: _ProductSearchDelegate(_catalog),
      );
      if (selected != null) {
        return Product(barcode: barcode, name: selected.name);
      }
    }
    return null;
  }

  Future<void> _addProduct(
    Product product, {
    required String scannedBarcode,
  }) async {
    final record = ReturnRecord(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      marketplace: _marketplace,
      operatorName: _operatorController.text.trim(),
      shift: _shift,
      orderCode: _currentOrderCode,
      itemCode: scannedBarcode,
      itemName: product.name,
      condition: _condition,
      comment: '',
    );
    setState(() => _records.insert(0, record));
    await _storage.saveRecords(_records);
    await HapticFeedback.mediumImpact();
    await SystemSound.play(SystemSoundType.click);
    _showMessage(product.name, success: true);
  }

  void _finishOrder() {
    if (_currentOrderCode.isEmpty) return;
    setState(() {
      _currentOrderCode = '';
      _stage = WorkflowStage.order;
      _inputController.clear();
    });
    _showMessage('Заказ завершён. Отсканируйте следующий заказ.', success: true);
  }

  void _replaceOrder() {
    setState(() => _stage = WorkflowStage.order);
  }

  Future<void> _deleteRecord(ReturnRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить позицию?'),
        content: Text(record.itemName),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _records.removeWhere((item) => item.id == record.id));
    await _storage.saveRecords(_records);
  }

  Future<void> _editRecord(ReturnRecord record) async {
    final nameController = TextEditingController(text: record.itemName);
    final commentController = TextEditingController(text: record.comment);
    var condition = record.condition;
    final updated = await showDialog<ReturnRecord>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Исправить позицию'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Наименование',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: condition,
                  decoration: const InputDecoration(
                    labelText: 'Состояние',
                    border: OutlineInputBorder(),
                  ),
                  items: _conditions
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => condition = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: commentController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Комментарий',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                record.copyWith(
                  itemName: nameController.text.trim(),
                  condition: condition,
                  comment: commentController.text.trim(),
                ),
              ),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    commentController.dispose();
    if (updated == null) return;
    setState(() {
      final index = _records.indexWhere((item) => item.id == record.id);
      if (index >= 0) _records[index] = updated;
    });
    await _storage.saveRecords(_records);
  }

  Future<void> _exportCsv() async {
    final rows = <List<String>>[
      [
        'Дата',
        'Сотрудник',
        'Смена',
        'Маркетплейс',
        'Код заказа',
        'ШК товара',
        'Наименование',
        'Состояние',
        'Комментарий',
      ],
      ..._records.map(
        (record) => [
          _formatDateTime(record.createdAt),
          record.operatorName,
          record.shift,
          record.marketplace,
          record.orderCode,
          record.itemCode,
          record.itemName,
          record.condition,
          record.comment,
        ],
      ),
    ];
    final content = '\uFEFF${rows.map((row) => row.map(_csv).join(';')).join('\r\n')}';
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}ascona_returns_${DateTime.now().millisecondsSinceEpoch}.csv',
    );
    await file.writeAsString(content, encoding: utf8, flush: true);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'ASCONA Scanner — возвраты',
    );
  }

  String _csv(String value) => '"${value.replaceAll('"', '""')}"';

  void _showMessage(String message, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: success ? const Color(0xFF067647) : null,
          content: Text(message),
        ),
      );
  }

  int get _currentOrderItems => _records
      .where((record) => record.orderCode == _currentOrderCode)
      .length;

  int get _problemCount => _records.where((record) => record.hasProblem).length;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('ASCONA Scanner')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 52),
                const SizedBox(height: 16),
                const Text(
                  'Не удалось открыть справочник товаров',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(_loadError!, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }

    final pages = [
      _buildWorkPage(),
      _buildPositionsPage(),
      _buildSettingsPage(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('ASCONA Scanner'),
        actions: [
          IconButton(
            tooltip: 'Экспорт CSV',
            onPressed: _records.isEmpty ? null : _exportCsv,
            icon: const Icon(Icons.ios_share_outlined),
          ),
        ],
      ),
      body: IndexedStack(index: _selectedTab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) => setState(() => _selectedTab = index),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.qr_code_scanner),
            label: 'Работа',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _records.isNotEmpty,
              label: Text('${_records.length}'),
              child: const Icon(Icons.inventory_2_outlined),
            ),
            label: 'Позиции',
          ),
          const NavigationDestination(
            icon: Icon(Icons.tune),
            label: 'Настройки',
          ),
        ],
      ),
    );
  }

  Widget _buildWorkPage() {
    final waitingForOrder = _stage == WorkflowStage.order;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text(
          'Обработка возврата',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          waitingForOrder
              ? 'Сначала отсканируйте код заказа'
              : 'Заказ принят. Сканируйте товары подряд.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        _WorkflowStep(
          number: 1,
          title: 'Код заказа',
          value: _currentOrderCode,
          active: waitingForOrder,
          complete: _currentOrderCode.isNotEmpty,
          onTap: waitingForOrder ? _openScanner : _replaceOrder,
        ),
        const SizedBox(height: 8),
        _WorkflowStep(
          number: 2,
          title: 'Штрихкод товара',
          value: _currentOrderCode.isEmpty
              ? 'Станет доступен после заказа'
              : 'Найденное название подставится автоматически',
          active: !waitingForOrder,
          complete: false,
          onTap: waitingForOrder ? null : _openScanner,
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 58,
          child: FilledButton.icon(
            onPressed: _processing ? null : _openScanner,
            icon: _processing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    waitingForOrder ? Icons.receipt_long : Icons.qr_code_scanner,
                  ),
            label: Text(
              waitingForOrder ? 'Сканировать заказ' : 'Сканировать товар',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _inputController,
          focusNode: _inputFocus,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submitInput(),
          decoration: InputDecoration(
            labelText: waitingForOrder
                ? 'Код заказа вручную / сканер ТСД'
                : 'ШК товара вручную / сканер ТСД',
            prefixIcon: const Icon(Icons.keyboard),
            suffixIcon: IconButton(
              tooltip: 'Применить код',
              onPressed: _processing ? null : _submitInput,
              icon: const Icon(Icons.arrow_forward),
            ),
            border: const OutlineInputBorder(),
          ),
        ),
        if (_currentOrderCode.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            color: const Color(0xFFF0FDF4),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Color(0xFF067647)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Текущий заказ',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          _currentOrderCode,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text('Позиций: $_currentOrderItems'),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _finishOrder,
                    child: const Text('Завершить'),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (_records.isNotEmpty) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Последние позиции',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _selectedTab = 1),
                child: const Text('Все'),
              ),
            ],
          ),
          ..._records.take(3).map(_buildRecordTile),
        ],
      ],
    );
  }

  Widget _buildPositionsPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Позиции',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            if (_records.isNotEmpty)
              OutlinedButton.icon(
                onPressed: _exportCsv,
                icon: const Icon(Icons.ios_share_outlined),
                label: const Text('CSV'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_records.isEmpty)
          const _EmptyPositions()
        else ...[
          Row(
            children: [
              Expanded(
                child: _SummaryTile(
                  label: 'Всего',
                  value: '${_records.length}',
                  icon: Icons.inventory_2_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryTile(
                  label: 'Проблем',
                  value: '$_problemCount',
                  icon: Icons.report_problem_outlined,
                  warning: _problemCount > 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._records.map(_buildRecordTile),
        ],
      ],
    );
  }

  Widget _buildRecordTile(ReturnRecord record) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        leading: CircleAvatar(
          backgroundColor: record.hasProblem
              ? const Color(0xFFFFF3E0)
              : const Color(0xFFE7F8EF),
          child: Icon(
            record.hasProblem ? Icons.priority_high : Icons.check,
            color: record.hasProblem
                ? const Color(0xFFB54708)
                : const Color(0xFF067647),
          ),
        ),
        title: Text(
          record.itemName.isEmpty ? 'Наименование не указано' : record.itemName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          'ШК ${record.itemCode}\nЗаказ ${record.orderCode} · ${record.condition}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'edit') _editRecord(record);
            if (value == 'delete') _deleteRecord(record);
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'edit', child: Text('Исправить')),
            PopupMenuItem(value: 'delete', child: Text('Удалить')),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text(
          'Настройки смены',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _operatorController,
          onChanged: (_) => _saveSettings(),
          decoration: const InputDecoration(
            labelText: 'Сотрудник',
            prefixIcon: Icon(Icons.badge_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        _SettingsDropdown(
          label: 'Маркетплейс / поставщик',
          icon: Icons.storefront_outlined,
          value: _marketplace,
          values: _marketplaces,
          onChanged: (value) {
            setState(() => _marketplace = value);
            _saveSettings();
          },
        ),
        const SizedBox(height: 12),
        _SettingsDropdown(
          label: 'Смена',
          icon: Icons.schedule,
          value: _shift,
          values: _shifts,
          onChanged: (value) {
            setState(() => _shift = value);
            _saveSettings();
          },
        ),
        const SizedBox(height: 12),
        _SettingsDropdown(
          label: 'Состояние товара по умолчанию',
          icon: Icons.fact_check_outlined,
          value: _condition,
          values: _conditions,
          onChanged: (value) {
            setState(() => _condition = value);
            _saveSettings();
          },
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.storage_outlined),
                    SizedBox(width: 10),
                    Text(
                      'Локальный справочник',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text('Товарных записей: ${_catalog.productCount}'),
                Text(
                  'Неоднозначных штрихкодов: ${_catalog.ambiguousBarcodeCount}',
                ),
                const SizedBox(height: 6),
                const Text(
                  'Справочник работает без интернета. При неоднозначном ШК приложение попросит выбрать товар.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.day)}.${two(value.month)}.${value.year} '
        '${two(value.hour)}:${two(value.minute)}';
  }
}

class _UnknownProductAction {
  const _UnknownProductAction({this.manualName, this.searchCatalog = false});

  final String? manualName;
  final bool searchCatalog;
}

class _WorkflowStep extends StatelessWidget {
  const _WorkflowStep({
    required this.number,
    required this.title,
    required this.value,
    required this.active,
    required this.complete,
    required this.onTap,
  });

  final int number;
  final String title;
  final String value;
  final bool active;
  final bool complete;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: active ? colorScheme.primaryContainer : colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: complete
                    ? const Color(0xFF067647)
                    : active
                        ? colorScheme.primary
                        : colorScheme.outlineVariant,
                foregroundColor: complete || active
                    ? Colors.white
                    : colorScheme.onSurfaceVariant,
                child: complete
                    ? const Icon(Icons.check, size: 20)
                    : Text('$number'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      value.isEmpty ? 'Ожидается сканирование' : value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (onTap != null) const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.icon,
    this.warning = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              icon,
              color: warning ? const Color(0xFFB54708) : null,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                Text(label),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPositions extends StatelessWidget {
  const _EmptyPositions();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 72),
      child: Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          const Text(
            'Пока нет позиций',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Отсканируйте заказ, затем товары.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SettingsDropdown extends StatelessWidget {
  const _SettingsDropdown({
    required this.label,
    required this.icon,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final String value;
  final List<String> values;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
      items: values
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class _ProductSearchDelegate extends SearchDelegate<Product?> {
  _ProductSearchDelegate(this.catalog);

  final ProductCatalog catalog;

  @override
  String get searchFieldLabel => 'Название товара';

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(
        tooltip: 'Очистить',
        onPressed: () => query = '',
        icon: const Icon(Icons.clear),
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      tooltip: 'Назад',
      onPressed: () => close(context, null),
      icon: const Icon(Icons.arrow_back),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildMatches();

  @override
  Widget buildSuggestions(BuildContext context) => _buildMatches();

  Widget _buildMatches() {
    if (query.trim().length < 2) {
      return const Center(child: Text('Введите минимум два символа'));
    }
    return FutureBuilder<List<Product>>(
      future: catalog.searchByName(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final products = snapshot.data ?? const [];
        if (products.isEmpty) {
          return const Center(child: Text('Совпадений не найдено'));
        }
        return ListView.separated(
          itemCount: products.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final product = products[index];
            return ListTile(
              title: Text(product.name),
              subtitle: Text(product.barcode),
              onTap: () => close(context, product),
            );
          },
        );
      },
    );
  }
}
