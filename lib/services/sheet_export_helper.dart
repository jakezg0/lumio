import '../l10n/app_strings.dart';
import '../state/shop_controller.dart';
import '../widgets/formatters.dart';
import 'google_sheets_service.dart';

enum SheetExportSection {
  restock,
  stockSnapshots,
  changes,
  sales,
  stockIns,
  customers,
  debts,
  expenses,
  defects,
}

class SheetExportHelper {
  const SheetExportHelper._();

  static String sectionTitle(SheetExportSection section, AppStrings strings) {
    switch (section) {
      case SheetExportSection.restock:
        return strings.sectionRestock;
      case SheetExportSection.stockSnapshots:
        return strings.sectionStockSnapshots;
      case SheetExportSection.changes:
        return strings.sectionChanges;
      case SheetExportSection.sales:
        return strings.sectionSales;
      case SheetExportSection.stockIns:
        return strings.sectionStockIns;
      case SheetExportSection.customers:
        return strings.sectionCustomers;
      case SheetExportSection.debts:
        return strings.sectionDebts;
      case SheetExportSection.expenses:
        return strings.sectionExpenses;
      case SheetExportSection.defects:
        return strings.sectionDefects;
    }
  }

  static String defaultTabName(SheetExportSection section, AppStrings strings) =>
      sectionTitle(section, strings);

  static ({List<String> headers, List<List<dynamic>> rows}) buildTable(
    SheetExportSection section,
    ShopController controller,
  ) {
    final strings = controller.strings;
    switch (section) {
      case SheetExportSection.restock:
        final headers = [
          'Товар',
          'Категория',
          'Штрихкод (SKU)',
          'Остаток',
          'Порог остатка',
          'Дней без остатка',
          'Продано за 30 дн.',
          'Рекомендуемый заказ',
          'Последний закуп',
          'Цена продажи',
          'Последний поставщик',
          'Упаковка',
          'Коробка',
        ];
        // Strictly active products only: excludes trashed, deleted, and archived.
        final outOfStock = controller.products
            .where(
              (p) =>
                  p.isActive && !p.isTrashed && !p.isArchived && p.stock <= 0,
            )
            .toList();
        final cutoff30 = DateTime.now().subtract(const Duration(days: 30));
        final sold30 = <String, int>{};
        for (final s in controller.sales) {
          if (s.createdAt.isBefore(cutoff30)) continue;
          for (final item in s.items) {
            if (item.quantity <= 0) continue;
            sold30[item.productId] =
                (sold30[item.productId] ?? 0) + item.quantity;
          }
        }
        final lastSupplier = <String, String>{};
        for (final rec in controller.stockIns) {
          final sup = rec.supplierName.trim();
          if (sup.isEmpty) continue;
          for (final item in rec.items) {
            lastSupplier.putIfAbsent(item.productId, () => sup);
          }
        }
        outOfStock.sort((a, b) {
          final sCmp = (sold30[b.id] ?? 0).compareTo(sold30[a.id] ?? 0);
          if (sCmp != 0) return sCmp;
          final dCmp =
              b.currentOutOfStockDays.compareTo(a.currentOutOfStockDays);
          if (dCmp != 0) return dCmp;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        final rows = <List<dynamic>>[];
        for (final p in outOfStock) {
          final sold = sold30[p.id] ?? 0;
          final deficit = p.stock < 0 ? -p.stock : 0;
          final baseTarget =
              sold > p.lowStockThreshold ? sold : p.lowStockThreshold;
          final recommended = (baseTarget > 0 ? baseTarget : 1) + deficit;
          rows.add([
            p.name,
            p.category,
            p.sku,
            p.stock,
            p.lowStockThreshold,
            p.currentOutOfStockDays,
            sold,
            recommended,
            p.costPrice,
            p.sellPrice,
            lastSupplier[p.id] ?? '',
            p.packQty,
            p.boxQty,
          ]);
        }
        return (headers: headers, rows: rows);

      case SheetExportSection.stockSnapshots:
        final headers = [
          'Месяц',
          'Дата снимка',
          'Позиций',
          'Всего штук',
          'Стоимость (закуп)',
          'Стоимость (продажа)',
          'Ожид. прибыль',
          'Изменение к прошл. мес.',
          'Изменение %',
        ];
        final snaps = controller.inventorySnapshots;
        final rows = <List<dynamic>>[];
        for (var i = 0; i < snaps.length; i++) {
          final cur = snaps[i];
          final prev = i + 1 < snaps.length ? snaps[i + 1] : null;
          final delta = prev != null ? (cur.costValue - prev.costValue) : null;
          final pct = (prev != null && prev.costValue > 0.009)
              ? ((cur.costValue - prev.costValue) / prev.costValue) * 100
              : null;
          rows.add([
            '${cur.monthKey} (${strings.monthFull(cur.month)})',
            formatDateTime(cur.capturedAt),
            cur.productsCount,
            cur.totalUnits,
            cur.costValue,
            cur.sellValue,
            cur.expectedProfit,
            delta ?? '',
            pct != null ? double.parse(pct.toStringAsFixed(1)) : '',
          ]);
        }
        return (headers: headers, rows: rows);

      case SheetExportSection.changes:
        final headers = [
          'Дата и время',
          'Товар',
          'Источник',
          'Поле',
          'Было',
          'Стало',
        ];
        final rows = <List<dynamic>>[];
        for (final entry in controller.productChanges) {
          final dt = formatDateTime(entry.createdAt);
          final src = strings.changeSourceLabel(entry.source);
          for (final f in entry.fields) {
            rows.add([dt, entry.productName, src, f.label, f.oldValue, f.newValue]);
          }
        }
        return (headers: headers, rows: rows);

      case SheetExportSection.sales:
        final headers = [
          'Дата и время',
          'Чек №',
          'Клиент',
          'Телефон',
          'Товары',
          'Кол-во',
          'Способ оплаты',
          'Скидка',
          'Итого',
          'Себестоимость',
          'Прибыль',
          'Оплачено',
          'Долг',
          'Возврат / примечание',
          'Месяц',
          'День недели',
          'Час',
          'Причина скидки',
          'Причина возврата / брака',
          'Сегмент клиента',
        ];
        final rows = <List<dynamic>>[];
        String fmtNum(double v) => v == v.roundToDouble()
            ? v.toStringAsFixed(0)
            : v.toStringAsFixed(2);
        for (final s in controller.sales) {
          final itemsStr = s.items
              .map(
                (i) =>
                    '${i.productName} ×${i.quantity} (цена ${fmtNum(i.unitPrice)}, закуп ${fmtNum(i.unitCost)})',
              )
              .join(', ');
          final payLabel = s.isSplitPayment
              ? '${strings.paymentMethodLabel(s.paymentMethod.name)} + ${strings.paymentMethodLabel(s.secondaryPaymentMethod!.name)}'
              : strings.paymentMethodLabel(s.paymentMethod.name);
          final dt = s.createdAt;
          final monthLabel =
              '${dt.year}-${dt.month.toString().padLeft(2, '0')} (${strings.monthShort(dt.month)})';
          final hourLabel = '${dt.hour.toString().padLeft(2, '0')}:00';
          final segLabel = s.customerName.trim().isNotEmpty
              ? strings.customerSegmentLabel(
                  controller.customerSegmentByName(s.customerName).name,
                )
              : '';
          rows.add([
            formatDateTime(dt),
            s.receiptCode,
            s.customerName,
            s.customerPhone,
            itemsStr,
            s.totalUnits,
            payLabel,
            s.discount,
            s.total,
            s.totalCost,
            s.profit,
            s.paidAmount,
            s.remainingDebt,
            s.refundNote,
            monthLabel,
            strings.weekdayFull(dt.weekday),
            hourLabel,
            s.discountReason,
            s.returnReason,
            segLabel,
          ]);
        }
        return (headers: headers, rows: rows);

      case SheetExportSection.stockIns:
        final headers = [
          'Дата и время',
          'Поставщик',
          'Валюта',
          'Курс на дату',
          'Товар',
          'Кол-во',
          'Цена закупа',
          'Сумма',
          'Всего по накладной',
        ];
        final rows = <List<dynamic>>[];
        for (final rec in controller.stockIns) {
          final dt = formatDateTime(rec.createdAt);
          for (final item in rec.items) {
            rows.add([
              dt,
              rec.supplierName,
              rec.currencyCode,
              rec.exchangeRate ?? '',
              item.productName,
              item.quantity,
              item.unitCost,
              item.lineTotal,
              rec.totalCost,
            ]);
          }
        }
        return (headers: headers, rows: rows);

      case SheetExportSection.customers:
        final headers = [
          'Имя',
          'Телефон',
          'Сегмент',
          'Заметка',
          'Покупок',
          'Сумма покупок',
          'Текущий долг',
          'Купленные товары',
        ];
        final rows = <List<dynamic>>[];
        for (final c in controller.customers) {
          final stats = controller.statsForCustomer(c.name);
          final customerSales = controller.salesForCustomer(c.name);
          final boughtSummary = customerSales
              .take(15)
              .map((s) {
                final items = s.items
                    .map((i) => '${i.productName} ×${i.quantity}')
                    .join(', ');
                return '${formatDate(s.createdAt)} (${strings.paymentMethodLabel(s.paymentMethod.name)}): $items';
              })
              .join(' | ');
          rows.add([
            c.name,
            c.phone,
            strings.customerSegmentLabel(c.segment.name),
            c.note,
            stats.ordersCount,
            stats.totalSpent,
            stats.unpaidDebt,
            boughtSummary,
          ]);
        }
        return (headers: headers, rows: rows);

      case SheetExportSection.debts:
        final headers = [
          'Клиент',
          'Телефон',
          'Покупок в долг',
          'Активных долгов',
          'Остаток долга',
          'Ближайший срок',
          'Статус',
          'История возвратов',
        ];
        final rows = <List<dynamic>>[];
        for (final d in controller.allDebtCustomers) {
          final repaymentsStr = d.repayments
              .map((r) => '${formatDateTime(r.date)}: ${r.amount}')
              .join(' | ');
          final status = d.totalDebt <= 0.009
              ? strings.debtPaidBadge
              : (d.hasOverdue ? strings.overdueBadge : strings.activeDebtorsFilter);
          rows.add([
            d.customerName,
            d.phone,
            d.totalDebtPurchasesCount,
            d.sales.length,
            d.totalDebt,
            d.earliestDueDate != null ? formatDate(d.earliestDueDate!) : '',
            status,
            repaymentsStr,
          ]);
        }
        return (headers: headers, rows: rows);

      case SheetExportSection.expenses:
        final headers = [
          'Дата и время',
          'Категория',
          'Название',
          'Сумма',
          'Комментарий',
        ];
        final rows = <List<dynamic>>[];
        for (final e in controller.expenses) {
          rows.add([
            formatDateTime(e.createdAt),
            strings.expenseCategoryLabel(e.category.name),
            e.title,
            e.amount,
            e.note,
          ]);
        }
        return (headers: headers, rows: rows);

      case SheetExportSection.defects:
        final headers = [
          'Дата и время',
          'Чек №',
          'Товар',
          'Кол-во',
          'Цена закупа',
          'Сумма списания',
          'Причина брака',
        ];
        final rows = <List<dynamic>>[];
        for (final d in controller.defectWriteOffs(SalesDateFilter.all)) {
          rows.add([
            formatDateTime(d.item.createdAt),
            d.receiptCode,
            d.item.productName,
            d.item.quantity,
            d.item.unitCost,
            d.item.lineCost,
            d.item.reason,
          ]);
        }
        return (headers: headers, rows: rows);
    }
  }

  static String buildTsv(
    SheetExportSection section,
    ShopController controller,
  ) {
    final table = buildTable(section, controller);
    return GoogleSheetsService.buildTsv(table.headers, table.rows);
  }
}
