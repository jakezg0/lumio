import '../l10n/app_strings.dart';
import '../state/shop_controller.dart';
import '../widgets/formatters.dart';
import 'google_sheets_service.dart';

enum SheetExportSection {
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
        ];
        final rows = <List<dynamic>>[];
        for (final s in controller.sales) {
          final itemsStr = s.items
              .map((i) => '${i.productName} ×${i.quantity}')
              .join(', ');
          final payLabel = s.isSplitPayment
              ? '${strings.paymentMethodLabel(s.paymentMethod.name)} + ${strings.paymentMethodLabel(s.secondaryPaymentMethod!.name)}'
              : strings.paymentMethodLabel(s.paymentMethod.name);
          rows.add([
            formatDateTime(s.createdAt),
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
          ]);
        }
        return (headers: headers, rows: rows);

      case SheetExportSection.stockIns:
        final headers = [
          'Дата и время',
          'Поставщик',
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
