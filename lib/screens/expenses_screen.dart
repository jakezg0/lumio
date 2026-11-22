import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/expense.dart';
import '../state/shop_controller.dart';
import '../widgets/currency_calculator_dialog.dart';
import '../widgets/defect_report_sheet.dart';
import '../widgets/formatters.dart';
import '../widgets/incoming_price_analysis_sheet.dart';
import '../widgets/invoices_history_sheet.dart';
import '../widgets/settings_button.dart';
import '../widgets/stock_in_sheet.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key, required this.controller});

  final ShopController controller;

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  SalesDateFilter _filter = SalesDateFilter.today;
  ExpenseCategory? _selectedCategory;

  String _filterLabel(AppStrings strings, SalesDateFilter filter) {
    switch (filter) {
      case SalesDateFilter.today:
        return strings.filterToday;
      case SalesDateFilter.last7Days:
        return strings.filter7Days;
      case SalesDateFilter.all:
        return strings.filterAll;
    }
  }

  Future<void> _openExpenseFormSheet({Expense? existing}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _ExpenseFormSheet(
        controller: widget.controller,
        existing: existing,
      ),
    );
  }

  Future<void> _openStockIn() async {
    widget.controller.trackFeatureUsage(FeatureUsageKeys.stockIn);
    final units = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => StockInSheet(controller: widget.controller),
    );
    if (units != null && units > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.controller.strings.stockInSavedMsg(units))),
      );
    }
  }

  void _openInvoicesSheet() {
    widget.controller.trackFeatureUsage(FeatureUsageKeys.invoicesHistory);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => InvoicesHistorySheet(
        controller: widget.controller,
        initialFilter: InvoiceHistoryFilter.stockIns,
        initialDateFilter: _filter,
      ),
    );
  }

  void _openIncomingPricesSheet() {
    widget.controller.trackFeatureUsage(FeatureUsageKeys.incomingPrices);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => IncomingPriceAnalysisSheet(
        controller: widget.controller,
        initialFilter: _filter,
      ),
    );
  }

  void _openDefectReportSheet() {
    widget.controller.trackFeatureUsage(FeatureUsageKeys.defectReport);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DefectReportSheet(
        controller: widget.controller,
        initialFilter: _filter,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final strings = widget.controller.strings;
        final currency = widget.controller.currency;
        final sales = widget.controller.filteredSales(_filter);
        final grossProfit = sales.fold(0.0, (sum, s) => sum + s.profit);
        final allPeriodExpenses = widget.controller.filteredExpenses(_filter);
        final expenses = _selectedCategory == null
            ? allPeriodExpenses
            : allPeriodExpenses
                .where((e) => e.category == _selectedCategory)
                .toList();
        final totalExpenses = widget.controller.totalExpensesFor(_filter);
        final netProfit = grossProfit - totalExpenses;
        final categoryTotals = <ExpenseCategory, double>{};
        for (final expense in allPeriodExpenses) {
          categoryTotals[expense.category] =
              (categoryTotals[expense.category] ?? 0) + expense.amount;
        }
        final sortedCategoryTotals = categoryTotals.entries
            .where((e) => e.value > 0)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return Scaffold(
          appBar: AppBar(
            title: Text(strings.expensesTitle),
            actions: [
              SettingsButton(controller: widget.controller),
              IconButton(
                tooltip: strings.stockInvoicesBtn,
                onPressed: _openInvoicesSheet,
                icon: Badge(
                  isLabelVisible: widget.controller.stockIns.isNotEmpty,
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  textColor: Theme.of(context).colorScheme.onSurfaceVariant,
                  label: Text('${widget.controller.stockIns.length}'),
                  child: const Icon(Icons.description_outlined),
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openExpenseFormSheet(),
            icon: const Icon(Icons.add),
            label: Text(strings.addExpense),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: SegmentedButton<SalesDateFilter>(
                  showSelectedIcon: false,
                  segments: [
                    for (final option in SalesDateFilter.values)
                      ButtonSegment(
                        value: option,
                        label: Text(
                          _filterLabel(strings, option),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (selection) {
                    setState(() => _filter = selection.first);
                  },
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    if (widget.controller.products.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          avatar: const Icon(
                            Icons.local_shipping_outlined,
                            size: 18,
                          ),
                          label: Text(strings.stockInBtn),
                          onPressed: _openStockIn,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        avatar: const Icon(
                          Icons.trending_up,
                          size: 18,
                        ),
                        label: Text(strings.incomingPricesBtn),
                        onPressed: _openIncomingPricesSheet,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        avatar: const Icon(
                          Icons.report_problem_outlined,
                          size: 18,
                        ),
                        label: Text(strings.defectReportBtn),
                        onPressed: _openDefectReportSheet,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(strings.allCategory),
                        selected: _selectedCategory == null,
                        onSelected: (_) =>
                            setState(() => _selectedCategory = null),
                      ),
                    ),
                    for (final cat in ExpenseCategory.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(strings.expenseCategoryLabel(cat.code)),
                          selected: _selectedCategory == cat,
                          onSelected: (_) =>
                              setState(() => _selectedCategory = cat),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _NetStat(
                                label: strings.grossProfitLabel,
                                value: formatMoney(grossProfit, currency),
                              ),
                            ),
                            Expanded(
                              child: _NetStat(
                                label: strings.totalExpensesLabel,
                                value: formatMoney(totalExpenses, currency),
                              ),
                            ),
                            Expanded(
                              child: _NetStat(
                                label: strings.netProfitLabel,
                                value: formatMoney(netProfit, currency),
                                highlightColor: netProfit >= 0
                                    ? Colors.green.shade700
                                    : Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                        if (sortedCategoryTotals.isNotEmpty) ...[
                          const Divider(height: 18),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              for (final entry in sortedCategoryTotals)
                                InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () => setState(() {
                                    _selectedCategory =
                                        _selectedCategory == entry.key
                                            ? null
                                            : entry.key;
                                  }),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _selectedCategory == entry.key
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primaryContainer
                                          : Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest
                                              .withValues(alpha: 0.6),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${strings.expenseCategoryLabel(entry.key.code)}: ${formatMoney(entry.value, currency)}'
                                      '${totalExpenses > 0 ? ' (${(entry.value / totalExpenses * 100).round()}%)' : ''}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            fontWeight:
                                                _selectedCategory == entry.key
                                                    ? FontWeight.w700
                                                    : FontWeight.w500,
                                          ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: expenses.isEmpty
                    ? Center(child: Text(strings.noExpensesMsg))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                        itemCount: expenses.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final expense = expenses[index];
                          return Card(
                            margin: EdgeInsets.zero,
                            child: ListTile(
                              onTap: () =>
                                  _openExpenseFormSheet(existing: expense),
                              title: Text(
                                expense.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                '${strings.expenseCategoryLabel(expense.category.code)} • ${formatDateTime(expense.createdAt)}'
                                '${expense.note.isNotEmpty ? '\n${expense.note}' : ''}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '-${formatMoney(expense.amount, currency)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.error,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: strings.edit,
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () =>
                                        _openExpenseFormSheet(existing: expense),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    tooltip: strings.moveToTrashAction,
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () async {
                                      await widget.controller
                                          .moveExpenseToTrash(expense.id);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content:
                                                Text(strings.movedToTrashMsg),
                                          ),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NetStat extends StatelessWidget {
  const _NetStat({
    required this.label,
    required this.value,
    this.highlightColor,
  });

  final String label;
  final String value;
  final Color? highlightColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: highlightColor,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _ExpenseFormSheet extends StatefulWidget {
  const _ExpenseFormSheet({
    required this.controller,
    this.existing,
  });

  final ShopController controller;
  final Expense? existing;

  @override
  State<_ExpenseFormSheet> createState() => _ExpenseFormSheetState();
}

class _ExpenseFormSheetState extends State<_ExpenseFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  late ExpenseCategory _category;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleController = TextEditingController(text: e?.title ?? '');
    final amtText = e != null
        ? (e.amount == e.amount.roundToDouble()
            ? e.amount.toStringAsFixed(0)
            : e.amount.toStringAsFixed(2))
        : '';
    _amountController = TextEditingController(text: amtText);
    _noteController = TextEditingController(text: e?.note ?? '');
    _category = e?.category ?? ExpenseCategory.purchase;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _openAmountCalculator() async {
    final strings = widget.controller.strings;
    final initial = double.tryParse(
      _amountController.text.trim().replaceAll(',', '.'),
    );
    final result = await showCurrencyCalculatorDialog(
      context,
      strings: strings,
      targetCurrency: widget.controller.currency,
      productName: _titleController.text.trim().isEmpty
          ? null
          : _titleController.text.trim(),
      initialValue: initial,
    );
    if (result != null && result > 0 && mounted) {
      setState(() {
        _amountController.text = result == result.roundToDouble()
            ? result.toStringAsFixed(0)
            : result.toStringAsFixed(2);
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.parse(
      _amountController.text.trim().replaceAll(',', '.'),
    );
    final existing = widget.existing;
    if (existing != null) {
      await widget.controller.updateExpense(
        expenseId: existing.id,
        title: _titleController.text,
        category: _category,
        amount: amount,
        note: _noteController.text,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.controller.strings.expenseUpdatedMsg)),
        );
      }
    } else {
      await widget.controller.addExpense(
        title: _titleController.text,
        category: _category,
        amount: amount,
        note: _noteController.text,
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.controller.strings;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isEditing = widget.existing != null;

    final templates = <({String title, ExpenseCategory category})>[
      (title: strings.tplRent, category: ExpenseCategory.rent),
      (title: strings.tplDelivery, category: ExpenseCategory.delivery),
      (title: strings.tplUtilities, category: ExpenseCategory.utilities),
      (title: strings.tplPurchase, category: ExpenseCategory.purchase),
      (title: strings.tplPackaging, category: ExpenseCategory.other),
      (title: strings.tplInternet, category: ExpenseCategory.utilities),
    ];
    final seenTitles = templates.map((t) => t.title.toLowerCase()).toSet();
    for (final exp in widget.controller.expenses) {
      final clean = exp.title.trim();
      if (clean.isEmpty || clean.startsWith('Stock-in')) continue;
      if (seenTitles.add(clean.toLowerCase())) {
        templates.add((title: clean, category: exp.category));
        if (templates.length >= 10) break;
      }
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isEditing ? strings.editExpense : strings.addExpense,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                strings.quickTemplatesLabel,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: templates.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final tpl = templates[index];
                    return ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(tpl.title),
                      onPressed: () {
                        setState(() {
                          _titleController.text = tpl.title;
                          _category = tpl.category;
                        });
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: strings.expenseTitleLabel,
                  border: const OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? strings.expenseTitleError
                    : null,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final cat in ExpenseCategory.values)
                    ChoiceChip(
                      label: Text(strings.expenseCategoryLabel(cat.code)),
                      selected: _category == cat,
                      onSelected: (_) => setState(() => _category = cat),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: strings.expenseAmountLabel,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: strings.currencyCalculatorTitle,
                    onPressed: _openAmountCalculator,
                    icon: const Icon(Icons.calculate_outlined),
                  ),
                ),
                validator: (v) {
                  final parsed = double.tryParse(
                    (v ?? '').trim().replaceAll(',', '.'),
                  );
                  if (parsed == null || parsed <= 0) {
                    return strings.invalidNumber(strings.totalExpensesLabel);
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _noteController,
                decoration: InputDecoration(
                  labelText: strings.expenseNoteLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submit,
                child: Text(
                  isEditing ? strings.saveChanges : strings.addExpense,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
