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
  CustomerSegment? _segmentFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesQuery(Customer customer, CustomerStats stats, String rawQuery) {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    final compactQ = q.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
    final segLabel =
        widget.controller.strings.customerSegmentLabel(customer.segment.name);
    final fields = [
      customer.name,
      customer.phone,
      customer.note,
      segLabel,
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

  Color _segmentColor(BuildContext context, CustomerSegment segment) {
    switch (segment) {
      case CustomerSegment.wholesale:
        return Colors.deepPurple.shade100;
      case CustomerSegment.regular:
        return Colors.teal.shade100;
      case CustomerSegment.retail:
        return Theme.of(context).colorScheme.surfaceContainerHighest;
    }
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
        final segmentCounts = <CustomerSegment, int>{
          for (final s in CustomerSegment.values)
            s: allCustomers.where((c) => c.segment == s).length,
        };

        final filtered = withStats.where((entry) {
          if (_withDebtOnly && entry.stats.unpaidDebt <= 0.009) return false;
          if (_segmentFilter != null &&
              entry.customer.segment != _segmentFilter) {
            return false;
          }
          return _matchesQuery(entry.customer, entry.stats, _query);
        }).toList();

        final filteredRevenue = filtered.fold(
          0.0,
          (sum, e) => sum + e.stats.totalSpent,
        );

        return SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.85,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${strings.customersBtn} (${allCustomers.length})',
                        style: Theme.of(context).textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
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
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            '${strings.allCategory} (${allCustomers.length})',
                          ),
                          selected: !_withDebtOnly && _segmentFilter == null,
                          onSelected: (_) => setState(() {
                            _withDebtOnly = false;
                            _segmentFilter = null;
                          }),
                        ),
                      ),
                      for (final seg in CustomerSegment.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(
                              '${strings.customerSegmentLabel(seg.name)} (${segmentCounts[seg] ?? 0})',
                            ),
                            selected: _segmentFilter == seg,
                            onSelected: (selected) => setState(
                              () => _segmentFilter = selected ? seg : null,
                            ),
                          ),
                        ),
                      FilterChip(
                        visualDensity: VisualDensity.compact,
                        label: Text('${strings.withDebtFilter} ($debtCount)'),
                        selected: _withDebtOnly,
                        onSelected: (selected) =>
                            setState(() => _withDebtOnly = selected),
                      ),
                    ],
                  ),
                ),
                if (filtered.isNotEmpty &&
                    (_segmentFilter != null || _withDebtOnly)) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${filtered.length} • ${strings.revenueLabel}: ${formatMoney(filteredRevenue, currency)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
                const SizedBox(height: 8),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              allCustomers.isEmpty
                                  ? strings.noCustomersMsg
                                  : strings.noCustomersMatchMsg,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.separated(
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
                              child: ExpansionTile(
                                tilePadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                childrenPadding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  12,
                                ),
                                leading: CircleAvatar(
                                  child: Text(initial),
                                ),
                                title: Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      customer.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _segmentColor(
                                          context,
                                          customer.segment,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        strings.customerSegmentLabel(
                                          customer.segment.name,
                                        ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                    if (stats.unpaidDebt > 0.009)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.shade100,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          strings.unpaidBadge(
                                            formatMoney(
                                              stats.unpaidDebt,
                                              currency,
                                            ),
                                          ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ),
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
                                            ?.copyWith(
                                              fontWeight: FontWeight.w500,
                                            ),
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
                                      onPressed: () => _openCustomerForm(
                                        existing: customer,
                                      ),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    IconButton(
                                      tooltip: strings.delete,
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => widget.controller
                                          .deleteCustomer(customer.id),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                                children: [
                                  Builder(
                                    builder: (_) {
                                      final customerSales = widget.controller
                                          .salesForCustomer(customer.name);
                                      if (customerSales.isEmpty) {
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 6,
                                          ),
                                          child: Text(
                                            strings.noAnalyticsData,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        );
                                      }
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          for (final sale in customerSales) ...[
                                            const Divider(height: 10),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    '${formatDateTime(sale.createdAt)} • ${sale.isSplitPayment ? '${strings.paymentMethodLabel(sale.paymentMethod.name)} + ${strings.paymentMethodLabel(sale.secondaryPaymentMethod!.name)}' : strings.paymentMethodLabel(sale.paymentMethod.name)}',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .labelMedium
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                  ),
                                                ),
                                                Text(
                                                  formatMoney(
                                                    sale.total,
                                                    currency,
                                                  ),
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelMedium
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              sale.items
                                                  .map(
                                                    (i) =>
                                                        '${i.productName} × ${i.quantity}',
                                                  )
                                                  .join(', '),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                          ],
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
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
  late CustomerSegment _segment;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _phoneController =
        TextEditingController(text: widget.existing?.phone ?? '');
    _noteController = TextEditingController(text: widget.existing?.note ?? '');
    _segment = widget.existing?.segment ?? CustomerSegment.retail;
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
        segment: _segment,
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
        segment: _segment,
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              Text(
                strings.customerSegmentTitle,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final seg in CustomerSegment.values)
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(strings.customerSegmentLabel(seg.name)),
                      selected: _segment == seg,
                      onSelected: (_) => setState(() => _segment = seg),
                    ),
                ],
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
