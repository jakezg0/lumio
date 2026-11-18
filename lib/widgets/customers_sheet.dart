import 'package:flutter/material.dart';

import '../models/customer.dart';
import '../state/shop_controller.dart';
import 'formatters.dart';

class CustomersSheet extends StatefulWidget {
  const CustomersSheet({super.key, required this.controller});

  final ShopController controller;

  @override
  State<CustomersSheet> createState() => _CustomersSheetState();
}

class _CustomersSheetState extends State<CustomersSheet> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _withDebtOnly = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesQuery(Customer customer, CustomerStats stats, String rawQuery) {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    final compactQ = q.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
    final fields = [
      customer.name,
      customer.phone,
      customer.note,
      if (stats.totalSpent > 0) stats.totalSpent.toStringAsFixed(0),
      if (stats.unpaidDebt > 0) stats.unpaidDebt.toStringAsFixed(0),
    ];
    for (final f in fields) {
      final lower = f.toLowerCase();
      if (lower.contains(q)) return true;
      if (compactQ.isNotEmpty) {
        final compactF = lower.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
        if (compactF.contains(compactQ)) return true;
      }
    }
    return false;
  }

  Future<void> _openCustomerForm({Customer? existing}) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CustomerFormDialog(
        controller: widget.controller,
        existing: existing,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final strings = widget.controller.strings;
        final currency = widget.controller.currency;
        final allCustomers = widget.controller.customers;

        final withStats = [
          for (final c in allCustomers)
            (customer: c, stats: widget.controller.statsForCustomer(c.name)),
        ];
        final debtCount =
            withStats.where((e) => e.stats.unpaidDebt > 0.009).length;

        final filtered = withStats.where((entry) {
          if (_withDebtOnly && entry.stats.unpaidDebt <= 0.009) return false;
          return _matchesQuery(entry.customer, entry.stats, _query);
        }).toList();

        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${strings.customersBtn} (${allCustomers.length})',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _openCustomerForm(),
                    icon: const Icon(Icons.person_add_alt_1, size: 18),
                    label: Text(strings.addCustomerBtn),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: strings.searchCustomersHint,
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.clear),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text('${strings.allCategory} (${allCustomers.length})'),
                    selected: !_withDebtOnly,
                    onSelected: (_) => setState(() => _withDebtOnly = false),
                  ),
                  ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text('${strings.withDebtFilter} ($debtCount)'),
                    selected: _withDebtOnly,
                    onSelected: (_) => setState(() => _withDebtOnly = true),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Text(
                      allCustomers.isEmpty
                          ? strings.noCustomersMsg
                          : strings.noCustomersMatchMsg,
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.52,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final customer = filtered[index].customer;
                      final stats = filtered[index].stats;
                      final initial = customer.name.trim().isNotEmpty
                          ? customer.name.trim()[0].toUpperCase()
                          : '?';

                      return Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          onTap: () => _openCustomerForm(existing: customer),
                          leading: CircleAvatar(
                            child: Text(initial),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  customer.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (stats.unpaidDebt > 0.009) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    strings.unpaidBadge(
                                      formatMoney(stats.unpaidDebt, currency),
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (customer.phone.isNotEmpty)
                                Text(
                                  customer.phone,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(fontWeight: FontWeight.w500),
                                ),
                              Text(
                                '${strings.ordersLabel}: ${stats.ordersCount} • ${formatMoney(stats.totalSpent, currency)}'
                                '${customer.note.isNotEmpty ? '\n${customer.note}' : ''}',
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: strings.edit,
                                visualDensity: VisualDensity.compact,
                                onPressed: () =>
                                    _openCustomerForm(existing: customer),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: strings.delete,
                                visualDensity: VisualDensity.compact,
                                onPressed: () =>
                                    widget.controller.deleteCustomer(customer.id),
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

class _CustomerFormDialog extends StatefulWidget {
  const _CustomerFormDialog({
    required this.controller,
    this.existing,
  });

  final ShopController controller;
  final Customer? existing;

  @override
  State<_CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<_CustomerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _phoneController =
        TextEditingController(text: widget.existing?.phone ?? '');
    _noteController = TextEditingController(text: widget.existing?.note ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final existing = widget.existing;
    if (existing != null) {
      await widget.controller.updateCustomer(
        customerId: existing.id,
        name: _nameController.text,
        phone: _phoneController.text,
        note: _noteController.text,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.controller.strings.customerUpdatedMsg)),
        );
      }
    } else {
      await widget.controller.addCustomer(
        name: _nameController.text,
        phone: _phoneController.text,
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
    final isEditing = widget.existing != null;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      title: Text(isEditing ? strings.editCustomerTitle : strings.addCustomerBtn),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: !isEditing,
                decoration: InputDecoration(
                  labelText: strings.customerNameOptional,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? strings.enterCustomerName
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: strings.shopPhoneLabel,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _noteController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: strings.customerNoteLabel,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(isEditing ? strings.saveChanges : strings.addCustomerBtn),
        ),
      ],
    );
  }
}
