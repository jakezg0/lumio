import 'dart:ui' show Locale;

enum AppLanguage {
  en('EN', 'English'),
  ru('RU', 'Русский'),
  kk('KK', 'Қазақша');

  const AppLanguage(this.code, this.displayName);
  final String code;
  final String displayName;

  static AppLanguage fromCode(String? code) {
    return AppLanguage.values.firstWhere(
      (lang) => lang.code.toLowerCase() == (code ?? '').toLowerCase(),
      orElse: () => AppLanguage.en,
    );
  }

  static AppLanguage fromSystemLocales(List<Locale> locales) {
    for (final locale in locales) {
      final code = locale.languageCode.toLowerCase();
      if (code == 'ru') return AppLanguage.ru;
      if (code == 'kk') return AppLanguage.kk;
      if (code == 'en') return AppLanguage.en;
    }
    return AppLanguage.en;
  }
}

enum AppCurrency {
  kzt('KZT', '₸'),
  usd('USD', '\$'),
  rub('RUB', '₽');

  const AppCurrency(this.code, this.symbol);
  final String code;
  final String symbol;

  static AppCurrency fromCode(String? code) {
    return AppCurrency.values.firstWhere(
      (c) => c.code.toLowerCase() == (code ?? '').toLowerCase(),
      orElse: () => AppCurrency.kzt,
    );
  }
}

class AppStrings {
  const AppStrings(this.language);

  final AppLanguage language;

  String _pick(String en, String ru, String kk) {
    switch (language) {
      case AppLanguage.en:
        return en;
      case AppLanguage.ru:
        return ru;
      case AppLanguage.kk:
        return kk;
    }
  }

  String get appTitle => 'Lumio';

  // Navigation
  String get navGoods => _pick('Goods', 'Товары', 'Тауарлар');
  String get navSell => _pick('Sell', 'Продажа', 'Сату');
  String get navSales => _pick('Sales', 'Продажи', 'Сатылымдар');
  String get navExpenses => _pick('Expenses', 'Расходы', 'Шығындар');

  // Settings & Export & Branding & PIN
  String get settingsTitle => _pick('Settings', 'Настройки', 'Баптаулар');
  String get languageLabel => _pick('Language', 'Язык', 'Тіл');
  String get currencyLabel => _pick('Currency', 'Валюта', 'Валюта');
  String get close => _pick('Close', 'Закрыть', 'Жабу');
  String get backupAndExport =>
      _pick('Backup & Export', 'Экспорт и бэкап', 'Экспорт және бэкап');
  String get exportProductsCsv =>
      _pick('Export Goods (CSV)', 'Экспорт товаров (CSV)', 'Тауарларды экспорттау (CSV)');
  String get exportSalesCsv =>
      _pick('Export Sales (CSV)', 'Экспорт продаж (CSV)', 'Сатылымдарды экспорттау (CSV)');
  String get exportJsonBackup =>
      _pick('Save JSON Backup', 'Сохранить JSON-бэкап', 'JSON-бэкап сақтау');
  String get restoreJsonBackup =>
      _pick('Restore from JSON', 'Восстановить из JSON', 'JSON-нан қалпына келтіру');
  String get pasteBackupJsonHint => _pick(
        'Paste JSON backup content here...',
        'Вставьте текст JSON-бэкапа...',
        'JSON-бэкап мәтінін осында қойыңыз...',
      );
  String savedToPathMsg(String path) =>
      _pick('Saved to $path', 'Сохранено в $path', '$path ішіне сақталды');
  String get copiedToClipboardMsg =>
      _pick('Copied to clipboard', 'Скопировано в буфер', 'Буферге көшірілді');
  String get backupRestoredMsg =>
      _pick('Backup restored', 'База восстановлена', 'Деректер қалпына келтірілді');
  String get invalidBackupMsg =>
      _pick('Invalid backup JSON', 'Некорректный JSON-бэкап', 'Қате JSON-бэкап');

  String get shopProfileBtn =>
      _pick('Receipt Header & Shop Info', 'Шапка чека и магазин', 'Түбіртек тақырыбы және дүкен');
  String get shopNameLabel => _pick('Shop Name', 'Название магазина', 'Дүкен атауы');
  String get shopAddressLabel => _pick('Address', 'Адрес', 'Мекенжайы');
  String get shopPhoneLabel => _pick('Phone', 'Телефон', 'Телефон');
  String get receiptFooterLabel =>
      _pick('Receipt Footer', 'Подпись в чеке', 'Түбіртек соңындағы мәтін');
  String get savedMsg => _pick('Saved', 'Сохранено', 'Сақталды');

  String get cashierModeLabel => _pick('Cashier Mode', 'Режим продавца', 'Сатушы режимі');
  String get ownerModeLabel => _pick('Owner Mode', 'Режим владельца', 'Иесі режимі');
  String get switchToCashier =>
      _pick('Switch to Cashier Mode', 'Включить режим продавца', 'Сатушы режиміне өту');
  String get unlockOwnerMode =>
      _pick('Unlock Owner Mode', 'Выйти в режим владельца', 'Иесі режимін ашу');
  String get setOwnerPinBtn =>
      _pick('Owner PIN', 'PIN-код владельца', 'Иесінің PIN-коды');
  String get enterPinHint => _pick('Enter PIN', 'Введите PIN-код', 'PIN-кодты енгізіңіз');
  String get wrongPinMsg => _pick('Incorrect PIN', 'Неверный PIN-код', 'PIN-код қате');
  String get pinUpdatedMsg => _pick('PIN updated', 'PIN-код обновлён', 'PIN-код жаңартылды');

  // Inventory screen
  String get shopInventory => _pick('Shop Inventory', 'Склад и товары', 'Дүкен қоймасы');
  String get addGood => _pick('Add Good', 'Добавить товар', 'Тауар қосу');
  String get stockInBtn => _pick('Stock-In', 'Приход', 'Кіріс');
  String get stocktakeBtn => _pick('Stocktake', 'Ревизия', 'Түгендеу');
  String get supplierNameHint =>
      _pick('Supplier (optional)', 'Поставщик (необязательно)', 'Жеткізуші (міндетті емес)');
  String get recordAsExpenseLabel =>
      _pick('Record purchase as expense', 'Записать закупку в расходы', 'Шығын ретінде тіркеу');
  String get receiveStockAction =>
      _pick('Receive Stock', 'Оформить приход', 'Кірісті рәсімдеу');
  String stockInSavedMsg(int units) => _pick(
        'Received $units units into stock',
        'Оприходовано $units шт. на склад',
        'Қоймаға $units дана қабылданды',
      );
  String get applyStocktakeAction =>
      _pick('Apply Stocktake', 'Применить ревизию', 'Түгендеуді сақтау');
  String stocktakeAppliedMsg(int count) => _pick(
        'Updated stock for $count item(s)',
        'Обновлены остатки по $count поз.',
        '$count тауардың қалдығы жаңартылды',
      );
  String get actualStockLabel => _pick('Actual', 'Факт', 'Нақты');
  String get searchGoodsHint => _pick(
        'Search goods by name, category, or SKU...',
        'Поиск по названию, категории или SKU...',
        'Атауы, санаты немесе SKU бойынша іздеу...',
      );
  String get scanBarcodeTitle =>
      _pick('Barcode / SKU Lookup', 'Поиск по штрихкоду / SKU', 'Штрих-код / SKU іздеу');
  String get scanBarcodeHint => _pick(
        'Scan or type SKU / barcode',
        'Отсканируйте или введите SKU / штрихкод',
        'SKU / штрих-кодты сканерлеңіз немесе жазыңыз',
      );
  String get findAction => _pick('Find', 'Найти', 'Табу');
  String skuNotFoundMsg(String sku) => _pick(
        'No product with SKU "$sku"',
        'Товар с SKU «$sku» не найден',
        'SKU «$sku» бойынша тауар табылмады',
      );
  String get allCategory => _pick('All', 'Все', 'Барлығы');
  String lowStockFilter(int count) =>
      _pick('Low Stock ($count)', 'Мало ($count)', 'Аз қалды ($count)');
  String get productsLabel => _pick('Products', 'Товары', 'Тауарлар');
  String unitsCount(int count) => _pick('$count units', '$count шт.', '$count дана');
  String get stockValueLabel => _pick('Stock Value', 'Сумма склада', 'Қор құны');
  String get costBasisLabel => _pick('Cost basis', 'По закупке', 'Өзіндік құн');
  String get todayProfitLabel => _pick('Today Profit', 'Прибыль сегодня', 'Бүгінгі пайда');
  String revSubtitle(String rev) => _pick('Rev $rev', 'Выручка $rev', 'Түсім $rev');
  String get outOfStock => _pick('Out of stock', 'Нет в наличии', 'Таусылды');
  String lowStockBadge(int count) => _pick('Low: $count', 'Мало: $count', 'Аз: $count');
  String inStockBadge(int count) =>
      _pick('In stock: $count', 'В наличии: $count', 'Қолда бар: $count');
  String get sellShort => _pick('Sell', 'Цена', 'Сату');
  String get costShort => _pick('Cost', 'Закуп', 'Өзіндік');
  String get marginShort => _pick('Margin', 'Маржа', 'Маржа');
  String get edit => _pick('Edit', 'Изменить', 'Өзгерту');
  String get delete => _pick('Delete', 'Удалить', 'Жою');
  String get deleteProductTitle =>
      _pick('Move to trash?', 'Переместить в корзину?', 'Себетке салу керек пе?');
  String deleteProductBody(String name) => _pick(
        'Move "$name" to trash? You can restore it later.',
        'Переместить "$name" в корзину? Вы сможете восстановить его позже.',
        '"$name" тауарын себетке салу керек пе? Кейін қалпына келтіруге болады.',
      );
  String get cancel => _pick('Cancel', 'Отмена', 'Бас тарту');
  String get productAdded => _pick('Product added', 'Товар добавлен', 'Тауар қосылды');
  String get productUpdated => _pick('Product updated', 'Товар обновлён', 'Тауар жаңартылды');
  String get emptyInventoryTitle =>
      _pick('Your shop inventory is empty', 'Список товаров пуст', 'Тауарлар тізімі бос');
  String get emptyInventoryBody => _pick(
        'Add your first product or load sample items to try out sales and stock tracking.',
        'Добавьте первый товар или загрузите тестовые данные для проверки учёта.',
        'Алғашқы тауарды қосыңыз немесе тексеру үшін үлгі деректерді жүктеңіз.',
      );
  String get addFirstGood => _pick('Add First Good', 'Добавить товар', 'Тауар қосу');
  String get loadSampleData =>
      _pick('Load Sample Data', 'Тестовые данные', 'Үлгі деректер');
  String get noGoodsMatch => _pick(
        'No goods match your current filter.',
        'Нет товаров по выбранному фильтру.',
        'Сүзгі бойынша тауар табылмады.',
      );

  // Product form
  String get editGood => _pick('Edit Good', 'Редактировать товар', 'Тауарды өңдеу');
  String get addNewGood => _pick('Add New Good', 'Новый товар', 'Жаңа тауар');
  String get productNameRequired =>
      _pick('Product Name *', 'Название товара *', 'Тауар атауы *');
  String get productNameError =>
      _pick('Product name is required', 'Введите название товара', 'Тауар атауын енгізіңіз');
  String get categoryLabel => _pick('Category', 'Категория', 'Санат');
  String get skuLabel => _pick('Unit Barcode (SKU)', 'Штрихкод единицы (SKU)', 'Бірлік штрих-коды (SKU)');
  String get nomenclatureLabel => _pick('Nomenclature', 'Номенклатура', 'Номенклатура');
  String get printNameLabel => _pick('Print Name', 'Наименование для печати', 'Баспа атауы');
  String get packQtyLabel => _pick('Pack Qty', 'Упаковка', 'Қаптама');
  String get boxQtyLabel => _pick('Box Qty', 'Коробка', 'Қорап');
  String get packBarcodeLabel => _pick('Pack Barcode', 'Штрихкод упаковки', 'Қаптама штрих-коды');
  String get boxBarcodeLabel => _pick('Box Barcode', 'Штрихкод коробки', 'Қорап штрих-коды');
  String get unitWeightLabel => _pick('Unit Weight', 'Вес штуки', 'Бірлік салмағы');
  String get unitMeasureLabel => _pick('Unit of Measure', 'Ед. изм.', 'Өлшем бірлігі');
  String get additionalDetailsLabel =>
      _pick('Nomenclature & Barcodes', 'Номенклатура и штрихкоды', 'Номенклатура және штрих-кодтар');
  String get costPriceRequired =>
      _pick('Cost Price *', 'Закупочная цена *', 'Сатып алу бағасы *');
  String get sellPriceRequired =>
      _pick('Sell Price *', 'Цена продажи *', 'Сату бағасы *');
  String get stockQtyRequired =>
      _pick('Stock Quantity *', 'Количество *', 'Саны *');
  String get lowStockAlertLabel =>
      _pick('Low-Stock Alert', 'Порог остатка', 'Аз қалдық шегі');
  String get saveChanges => _pick('Save Changes', 'Сохранить', 'Сақтау');
  String get addProductBtn => _pick('Add Product', 'Добавить товар', 'Тауар қосу');
  String invalidNumber(String field) =>
      _pick('Enter a valid $field', 'Некорректное значение ($field)', 'Дұрыс мән енгізіңіз ($field)');

  // POS screen
  String get recordSaleTitle => _pick('Record Sale', 'Оформить продажу', 'Сатуды рәсімдеу');
  String get clearCart => _pick('Clear Cart', 'Очистить', 'Тазалау');
  String get searchPosHint =>
      _pick('Tap goods to add to sale...', 'Выберите товары для продажи...', 'Сату үшін тауар таңдаңыз...');
  String get addGoodsFirst => _pick(
        'Add goods in the Goods tab before recording sales.',
        'Сначала добавьте товары во вкладке «Товары».',
        'Алдымен «Тауарлар» бөлімінде тауар қосыңыз.',
      );
  String get noMatchingProducts =>
      _pick('No matching products.', 'Товары не найдены.', 'Сәйкес тауар табылмады.');
  String stockCountLabel(int count) => _pick('Stock: $count', 'Остаток: $count', 'Қалдық: $count');
  String inCartLabel(int count) => _pick('In cart: $count', 'В корзине: $count', 'Себетте: $count');
  String get outShort => _pick('Out', 'Нет', 'Жоқ');
  String get addShort => _pick('Add', 'Добавить', 'Қосу');
  String outOfStockMsg(String name) =>
      _pick('$name is out of stock', '$name нет в наличии', '$name қоймада жоқ');
  String onlyLeftMsg(int count) =>
      _pick('Only $count left in stock', 'В наличии только $count шт.', 'Қоймада тек $count дана қалды');
  String cartSummary(int count, String total) =>
      _pick('$count item(s) • $total', '$count шт. • $total', '$count дана • $total');
  String estProfit(String profit) =>
      _pick('Est. profit: $profit', 'Ожид. прибыль: $profit', 'Болжамды пайда: $profit');
  String get checkout => _pick('Checkout', 'Оплата', 'Төлем');
  String get customerNameOptional =>
      _pick('Customer Name (optional)', 'Имя клиента (необязательно)', 'Клиент аты (міндетті емес)');
  String get customerNameRequiredForDebt => _pick(
        'Customer Name * (for post-payment)',
        'Имя клиента * (для постоплаты)',
        'Клиент аты * (қарызға сату үшін)',
      );
  String get enterCustomerName => _pick(
        'Enter customer name for post-payment',
        'Укажите имя клиента для продажи в долг',
        'Қарызға сату үшін клиент атын жазыңыз',
      );
  String get discountAmount => _pick('Discount Amount', 'Скидка', 'Жеңілдік сомасы');
  String get paidNowOptional => _pick(
        'Paid Now (optional, default 0)',
        'Оплачено сейчас (по умолч. 0)',
        'Қазір төленгені (әдепкі 0)',
      );
  String get dueDateLabel => _pick('Due Date', 'Срок оплаты', 'Төлем мерзімі');
  String get selectDueDate => _pick('Select due date (optional)', 'Выбрать срок (необяз.)', 'Мерзімді таңдау (міндетті емес)');
  String get totalDue => _pick('Total Due', 'Итого к оплате', 'Төленетін сома');
  String get completeSale => _pick('Complete Sale', 'Завершить продажу', 'Сатуды аяқтау');
  String saleRecordedMsg(String total, int units) => _pick(
        'Sale recorded: $total ($units items)',
        'Продажа оформлена: $total ($units шт.)',
        'Сатылым тіркелді: $total ($units дана)',
      );

  // Payment methods
  String paymentMethodLabel(String name) {
    switch (name) {
      case 'cash':
        return _pick('Cash', 'Наличные', 'Қолма-қол');
      case 'kaspiQr':
        return 'Kaspi QR';
      case 'card':
        return _pick('Card', 'Карта', 'Карта');
      case 'transfer':
        return _pick('Transfer', 'Перевод', 'Аударым');
      case 'postPay':
        return _pick('Post-pay', 'В долг', 'Қарызға');
      default:
        return name;
    }
  }

  // Sales & Customers & Analytics
  String get salesAndProfit => _pick('Sales & Profit', 'Продажи и прибыль', 'Сатылымдар мен пайда');
  String get filterToday => _pick('Today', 'Сегодня', 'Бүгін');
  String get filter7Days => _pick('7 Days', '7 дней', '7 күн');
  String get filterAll => _pick('All Time', 'Всё время', 'Барлығы');
  String unpaidOnlyChip(int count, String debt) => _pick(
        'Post-pay / Unpaid ($count • $debt)',
        'Долги ($count • $debt)',
        'Қарыздар ($count • $debt)',
      );
  String get debtorsSummaryBtn => _pick('Debtors', 'Должники', 'Борышкерлер');
  String get customersBtn => _pick('Customers', 'Клиенты', 'Клиенттер');
  String get addCustomerBtn => _pick('Add Customer', 'Добавить клиента', 'Клиент қосу');
  String get noCustomersMsg =>
      _pick('No saved customers yet.', 'Список клиентов пуст.', 'Клиенттер тізімі бос.');
  String get analyticsBtn => _pick('Top Goods', 'Топ-товары', 'Үздік тауарлар');
  String get topSellingHeader =>
      _pick('Top Selling Goods', 'Топ продаж', 'Ең көп сатылғандар');
  String get slowMoversHeader =>
      _pick('No Sales in Period', 'Без движения', 'Сатылымы жоқ тауарлар');
  String get noAnalyticsData =>
      _pick('No sales data for this period.', 'Нет данных за период.', 'Бұл кезеңде дерек жоқ.');
  String get noDebtorsMsg =>
      _pick('No unpaid customer debts.', 'Нет активных должников.', 'Белсенді борышкерлер жоқ.');
  String ordersAndDue(int count, String? due) => due == null
      ? _pick('$count order(s)', '$count заказ(ов)', '$count тапсырыс')
      : _pick('$count order(s) • Due $due', '$count заказ(ов) • Срок $due', '$count тапсырыс • Мерзім $due');
  String get overdueBadge => _pick('Overdue', 'Просрочен', 'Мерзімі өткен');
  String get payAllAction => _pick('Pay All', 'Погасить всё', 'Барлығын өтеу');
  String get cashRegisterTitle => _pick('Register Breakdown', 'Итог по кассе', 'Касса бойынша есеп');
  String get ordersLabel => _pick('Orders', 'Заказы', 'Тапсырыс');
  String get revenueLabel => _pick('Revenue', 'Выручка', 'Түсім');
  String get costLabel => _pick('Cost', 'Себест.', 'Өзіндік');
  String get profitLabel => _pick('Profit', 'Прибыль', 'Пайда');
  String noSalesForFilter(String filterLabel) => _pick(
        'No sales recorded for $filterLabel.',
        'Нет продаж за период: $filterLabel.',
        '$filterLabel бойынша сатылым жоқ.',
      );
  String unitsShort(int count) => _pick('$count units', '$count шт.', '$count дана');
  String get paidBadge => _pick('Paid', 'Оплачено', 'Төленді');
  String unpaidBadge(String remaining) =>
      _pick('Due: $remaining', 'Долг: $remaining', 'Қарыз: $remaining');
  String get saleReceipt => _pick('Sale Receipt', 'Чек продажи', 'Сату түбіртегі');
  String get copyReceiptBtn =>
      _pick('Copy Receipt (WhatsApp)', 'Копировать чек (WhatsApp)', 'Түбіртекті көшіру (WhatsApp)');
  String get shareWhatsAppBtn =>
      _pick('Send to WhatsApp', 'Отправить в WhatsApp', 'WhatsApp-қа жіберу');
  String get sharePdfBtn =>
      _pick('Send PDF Receipt', 'Отправить чек PDF', 'PDF түбіртекті жіберу');
  String get copyTextBtn =>
      _pick('Copy Text', 'Копировать текст', 'Мәтінді көшіру');
  String customerLabel(String name) => _pick('Customer: $name', 'Клиент: $name', 'Клиент: $name');
  String dueDateValue(String date) => _pick('Due: $date', 'Срок: $date', 'Мерзімі: $date');
  String get discountLabel => _pick('Discount', 'Скидка', 'Жеңілдік');
  String get paidAmountLabel => _pick('Paid', 'Оплачено', 'Төленгені');
  String get remainingDebtLabel => _pick('Remaining Debt', 'Остаток долга', 'Қалған қарыз');
  String totalWithProfit(String profit) => _pick(
        'Total ($profit profit)',
        'Итого (прибыль $profit)',
        'Барлығы (пайда $profit)',
      );
  String get markAsPaid => _pick('Mark as Paid', 'Погасить долг полностью', 'Толық төленді деп белгілеу');
  String get addPayment => _pick('Record Payment', 'Внести оплату', 'Төлем енгізу');
  String get paymentAmountHint => _pick('Payment amount', 'Сумма оплаты', 'Төлем сомасы');
  String get confirm => _pick('Confirm', 'Подтвердить', 'Растау');
  String get paymentRecorded =>
      _pick('Payment recorded', 'Оплата записана', 'Төлем тіркелді');
  String get voidSaleRestore => _pick(
        'Move to Trash & Restore Stock',
        'В корзину и вернуть товар',
        'Себетке салу және тауарды қайтару',
      );
  String get saleVoidedMsg => _pick(
        'Sale moved to trash and stock restored',
        'Продажа в корзине, остаток восстановлен',
        'Сатылым себетке жіберілді, қор қалпына келтірілді',
      );

  // Expenses screen
  String get expensesTitle => _pick('Expenses & Net', 'Расходы и итог', 'Шығындар және таза пайда');
  String get addExpense => _pick('Add Expense', 'Добавить расход', 'Шығын қосу');
  String get expenseTitleLabel => _pick('Title *', 'Название *', 'Атауы *');
  String get expenseTitleError =>
      _pick('Enter expense title', 'Введите название расхода', 'Шығын атауын енгізіңіз');
  String get expenseAmountLabel => _pick('Amount *', 'Сумма *', 'Сома *');
  String get expenseNoteLabel => _pick('Note (optional)', 'Комментарий (необяз.)', 'Түсініктеме (міндетті емес)');
  String get grossProfitLabel => _pick('Gross Profit', 'Валовая прибыль', 'Жалпы пайда');
  String get totalExpensesLabel => _pick('Expenses', 'Расходы', 'Шығындар');
  String get netProfitLabel => _pick('Net Profit', 'Чистая прибыль', 'Таза пайда');
  String get noExpensesMsg => _pick(
        'No expenses recorded for this period.',
        'Нет расходов за выбранный период.',
        'Бұл кезеңде шығындар жоқ.',
      );
  String get stockInvoicesBtn =>
      _pick('Invoices', 'Накладные', 'Жүкқұжаттар');
  String get noInvoicesMsg =>
      _pick('No incoming invoices yet.', 'Приходных накладных пока нет.', 'Кіріс жүкқұжаттары жоқ.');
  String get incomingPricesBtn =>
      _pick('Incoming Prices', 'Цены прихода', 'Кіріс бағалары');
  String get incomingPricesTitle =>
      _pick('Incoming Price Analysis', 'Анализ цен прихода', 'Кіріс бағаларын талдау');
  String get priceUpFilter => _pick('Price Up', 'Подорожали', 'Қымбаттаған');
  String get priceDownFilter => _pick('Price Down', 'Подешевели', 'Арзандаған');
  String get latestCostLabel => _pick('Latest', 'Последняя', 'Соңғы');
  String get avgCostLabel => _pick('Average', 'Средняя', 'Орташа');
  String get minMaxCostLabel => _pick('Min / Max', 'Мин / Макс', 'Мин / Макс');
  String get unitCostLabel => _pick('Unit Cost', 'Цена прихода', 'Кіріс бағасы');
  String get noIncomingPricesMsg => _pick(
        'No incoming deliveries to analyze yet.',
        'Пока нет приходных поставок для анализа цен.',
        'Бағаны талдау үшін кіріс жеткізілімдері жоқ.',
      );
  String get totalSpendLabel => _pick('Total Spend', 'Сумма закупа', 'Сатып алу сомасы');
  String expenseCategoryLabel(String code) {
    switch (code) {
      case 'purchase':
        return _pick('Stock Purchase', 'Закупка товара', 'Тауар сатып алу');
      case 'rent':
        return _pick('Rent', 'Аренда', 'Жалдау ақысы');
      case 'delivery':
        return _pick('Delivery', 'Доставка', 'Жеткізу');
      case 'utilities':
        return _pick('Utilities', 'Коммунальные', 'Коммуналдық');
      default:
        return _pick('Other', 'Прочее', 'Басқа');
    }
  }

  // Archive & Trash
  String get archiveAndTrash =>
      _pick('Archive & Trash', 'Архив и корзина', 'Мұрағат және себет');
  String get archiveTab => _pick('Archive', 'Архив', 'Мұрағат');
  String get trashTab => _pick('Trash', 'Корзина', 'Себет');
  String get archiveAction => _pick('Archive', 'В архив', 'Мұрағатқа');
  String get moveToTrashAction =>
      _pick('Move to Trash', 'В корзину', 'Себетке салу');
  String get restoreAction =>
      _pick('Restore', 'Восстановить', 'Қалпына келтіру');
  String get deleteForeverAction =>
      _pick('Delete Forever', 'Удалить навсегда', 'Біржола жою');
  String get emptyTrashAction =>
      _pick('Empty Trash', 'Очистить корзину', 'Себетті тазалау');
  String get emptyTrashTitle =>
      _pick('Empty trash?', 'Очистить корзину?', 'Себетті тазалау керек пе?');
  String get emptyTrashBody => _pick(
        'Permanently delete all items in trash? This cannot be undone.',
        'Удалить все элементы из корзины навсегда? Это действие нельзя отменить.',
        'Себеттегі барлық деректі біржола жою керек пе? Бұл әрекетті қайтару мүмкін емес.',
      );
  String get archiveEmpty =>
      _pick('Archive is empty', 'Архив пуст', 'Мұрағат бос');
  String get trashEmpty =>
      _pick('Trash is empty', 'Корзина пуста', 'Себет бос');
  String get archivedProductsHeader =>
      _pick('Archived Goods', 'Архивные товары', 'Мұрағаттағы тауарлар');
  String get archivedSalesHeader =>
      _pick('Archived Sales', 'Архивные продажи', 'Мұрағаттағы сатылымдар');
  String get trashedProductsHeader =>
      _pick('Deleted Goods', 'Удалённые товары', 'Жойылған тауарлар');
  String get trashedSalesHeader =>
      _pick('Deleted Sales', 'Удалённые продажи', 'Жойылған сатылымдар');
  String get trashedExpensesHeader =>
      _pick('Deleted Expenses', 'Удалённые расходы', 'Жойылған шығындар');
  String get movedToArchiveMsg =>
      _pick('Moved to archive', 'Перемещено в архив', 'Мұрағатқа жіберілді');
  String get movedToTrashMsg =>
      _pick('Moved to trash', 'Перемещено в корзину', 'Себетке жіберілді');
  String get restoredMsg => _pick('Restored', 'Восстановлено', 'Қалпына келтірілді');
  String get selectItemsBtn => _pick('Select', 'Выбрать', 'Таңдау');
  String selectedCountLabel(int count) =>
      _pick('Selected: $count', 'Выбрано: $count', 'Таңдалды: $count');
  String get selectAllVisible =>
      _pick('Select All', 'Выбрать все', 'Барлығын таңдау');
  String get clearSelection => _pick('Clear', 'Снять', 'Тазалау');
  String get deleteSelectedAction =>
      _pick('To Trash', 'В корзину', 'Себетке');
  String get deleteGroupAction => _pick(
        'Delete Group to Trash',
        'Удалить группу в корзину',
        'Топты себетке жою',
      );
  String get deleteAllGoodsAction => _pick(
        'Delete All Goods to Trash',
        'Удалить все товары в корзину',
        'Барлық тауарды себетке жою',
      );
  String get chooseGroupToDelete => _pick(
        'Choose group to move to trash',
        'Выберите группу для удаления в корзину',
        'Себетке жою үшін топты таңдаңыз',
      );
  String deleteGroupConfirmTitle(String category) => _pick(
        'Move "$category" to trash?',
        'Удалить группу «$category» в корзину?',
        '«$category» тобын себетке салу керек пе?',
      );
  String get deleteAllGoodsConfirmTitle => _pick(
        'Move all goods to trash?',
        'Удалить все товары в корзину?',
        'Барлық тауарды себетке салу керек пе?',
      );
  String deleteBatchConfirmBody(int count) => _pick(
        'Move $count item(s) to trash? You can restore them later from Trash.',
        'Переместить $count поз. в корзину? Вы сможете восстановить их позже.',
        '$count тауарды себетке салу керек пе? Кейін себеттен қалпына келтіруге болады.',
      );
  String movedCountToTrashMsg(int count) => _pick(
        'Moved $count item(s) to trash',
        'Перемещено в корзину: $count поз.',
        'Себетке салынды: $count тауар',
      );
  String get restoreAllFromTrashAction =>
      _pick('Restore All', 'Восстановить всё', 'Барлығын қалпына келтіру');
  String get chooseDestinationTitle =>
      _pick('Where to move?', 'Куда переместить?', 'Қайда жылжыту керек?');
  String chooseDestinationBody(int count) => _pick(
        'Choose whether to move $count item(s) to Archive or Trash.',
        'Выберите, куда переместить $count поз.: в Архив или в Корзину.',
        '$count тауарды Мұрағатқа немесе Себетке жылжытуды таңдаңыз.',
      );
  String get groupArchiveOrTrashAction => _pick(
        'Group to Archive / Trash',
        'Группу в архив / корзину',
        'Топты мұрағатқа / себетке',
      );
  String get allArchiveOrTrashAction => _pick(
        'All Goods to Archive / Trash',
        'Все товары в архив / корзину',
        'Барлық тауарды мұрағатқа / себетке',
      );
  String movedCountToArchiveMsg(int count) => _pick(
        'Archived $count item(s)',
        'Перемещено в архив: $count поз.',
        'Мұрағатқа салынды: $count тауар',
      );
  String get moveToGroupAction => _pick(
        'Move to Group',
        'Переместить в группу',
        'Топқа жылжыту',
      );
  String get moveGroupAction => _pick(
        'Move Group to Another Group',
        'Переместить группу в другую',
        'Топты басқа топқа жылжыту',
      );
  String get chooseTargetGroupTitle => _pick(
        'Choose target group',
        'Выберите целевую группу',
        'Мақсатты топты таңдаңыз',
      );
  String get newGroupHint => _pick(
        'Or enter new group name',
        'Или введите новую группу',
        'Немесе жаңа топ атауын жазыңыз',
      );
  String movedCountToGroupMsg(int count, String group) => _pick(
        'Moved $count item(s) to "$group"',
        'Перемещено в «$group»: $count поз.',
        '«$group» тобына жылжытылды: $count тауар',
      );
  String scannedAddedToStockInMsg(int added, String name, int totalQty) => _pick(
        '+$added: $name (in stock-in: $totalQty)',
        '+$added: $name (в приходе: $totalQty)',
        '+$added: $name (кірісте: $totalQty)',
      );
  String inStockFilter(int count) =>
      _pick('In Stock ($count)', 'В наличии ($count)', 'Қолда бар ($count)');
  String outOfStockFilter(int count) => _pick(
        'Out of Stock ($count)',
        'Нет в наличии ($count)',
        'Таусылды ($count)',
      );
  String get sellValueLabel =>
      _pick('At Sell Price', 'По ценам продажи', 'Сату бағасымен');
  String get newGroupBtn =>
      _pick('New Group', 'Новая группа', 'Жаңа топ');
  String get createGroupTitle =>
      _pick('Create New Group', 'Создать новую группу', 'Жаңа топ құру');
  String get groupNameLabel =>
      _pick('Group Name', 'Название группы', 'Топ атауы');
  String get newGroupExampleHint => _pick(
        'e.g. Sale, Clearance',
        'Например: Распродажа',
        'Мысалы: Жеңілдік',
      );
  String groupCreatedMsg(String name) => _pick(
        'Group "$name" created',
        'Группа «$name» создана',
        '«$name» тобы құрылды',
      );
  String get createAndMoveAction => _pick(
        'Create & Move',
        'Создать и переместить',
        'Құру және жылжыту',
      );
  String get currencyCalculatorTitle => _pick(
        'Currency Calculator',
        'Калькулятор валюты',
        'Валюта калькуляторы',
      );
  String foreignPriceLabel(String code) =>
      _pick('Price in $code', 'Цена в $code', '$code бағасы');
  String get exchangeRateLabel => _pick('Exchange Rate', 'Курс', 'Бағам');
  String get extraPerUnitLabel => _pick(
        'Delivery / Extra per unit (optional)',
        'Доставка / доп. на 1 шт. (необяз.)',
        '1 данаға жеткізу / қосымша',
      );
  String calculatedUnitCostLabel(String value) => _pick(
        'Unit cost: $value',
        'Цена прихода: $value',
        'Кіріс бағасы: $value',
      );
  String get applyAction => _pick('Apply', 'Применить', 'Қолдану');
  String get clearDraftAction =>
      _pick('Clear Draft', 'Очистить черновик', 'Жобаны тазалау');
  String get doneAction => _pick('Done', 'Готово', 'Дайын');
  String scannedCountLabel(int count) => _pick(
        'Scanned: $count',
        'Отсканировано: $count',
        'Сканерленді: $count',
      );
  String get distributeDeliveryTitle => _pick(
        'Distribute Delivery Cost',
        'Распределить доставку',
        'Жеткізуді бөлу',
      );
  String get deliveryTotalAmountLabel => _pick(
        'Total Delivery / Customs Amount',
        'Общая сумма доставки / таможни',
        'Жеткізу / кеден жалпы сомасы',
      );
  String get splitPerUnit =>
      _pick('Per Unit', 'Поровну на штуку', 'Данасына тең');
  String get splitByValue =>
      _pick('By Amount', 'Пропорционально сумме', 'Сомаға пропорционал');
  String get splitByWeight =>
      _pick('By Weight', 'По весу', 'Салмақ бойынша');
  String deliveryAppliedMsg(String amount) => _pick(
        'Distributed $amount across invoice items',
        'Доставка $amount распределена по товарам',
        'Жеткізу ($amount) тауарларға бөлінді',
      );
  String get newSellPriceLabel =>
      _pick('Sell Price', 'Цена продажи', 'Сату бағасы');
  String keepMarkupAction(String price) =>
      _pick('Keep % → $price', 'Сохранить % → $price', '% сақтау → $price');
  String addedOnlyFilter(int count) => _pick(
        'Added Only ($count)',
        'Только добавленные ($count)',
        'Тек қосылғандар ($count)',
      );
  String get stockInInvoiceTitle =>
      _pick('Stock-In Invoice', 'Приходная накладная', 'Кіріс жүкқұжаты');
  String get holdSaleBtn => _pick('Hold', 'Отложить', 'Кейінге қалдыру');
  String get holdSaleTitle =>
      _pick('Hold Sale', 'Отложить продажу', 'Сатуды кейінге қалдыру');
  String get holdSaleLabelHint => _pick(
        'Customer name or note (optional)',
        'Имя клиента или заметка (необяз.)',
        'Клиент аты немесе ескертпе',
      );
  String get heldSalesTitle =>
      _pick('Held Sales', 'Отложенные продажи', 'Кейінге қалдырылғандар');
  String get saleHeldMsg => _pick(
        'Sale put on hold. Ready for next customer.',
        'Продажа отложена. Можно обслуживать нового клиента.',
        'Сатылым кейінге қалдырылды. Жаңа клиентке қызмет көрсетуге болады.',
      );
  String get resumeSaleAction =>
      _pick('Resume', 'Продолжить', 'Жалғастыру');
  String scannedAddedToStocktakeMsg(int added, String name, int actualQty) =>
      _pick(
        '+$added: $name (actual: $actualQty)',
        '+$added: $name (факт: $actualQty)',
        '+$added: $name (нақты: $actualQty)',
      );
  String get countFromZeroLabel =>
      _pick('From 0', 'Считать с нуля', 'Нөлден санау');
  String uncountedOnlyFilter(int count) => _pick(
        'Uncounted ($count)',
        'Не сверено ($count)',
        'Тексерілмеген ($count)',
      );
  String get countedBadge => _pick('Counted', 'Сверено', 'Тексерілді');
  String get uncountedBadge =>
      _pick('Not counted', 'Не сверено', 'Тексерілмеген');
  String discrepanciesOnlyFilter(int count) => _pick(
        'Discrepancies ($count)',
        'Только расхождения ($count)',
        'Айырмашылықтар ($count)',
      );
  String discrepancySummaryLabel(int count) => _pick(
        'Discrepancy total ($count)',
        'Итого расхождений ($count)',
        'Айырмашылық қорытындысы ($count)',
      );
  String scannedAddedToCartMsg(int added, String name, int totalQty) => _pick(
        '+$added: $name (in cart: $totalQty)',
        '+$added: $name (в корзине: $totalQty)',
        '+$added: $name (себетте: $totalQty)',
      );
  String get cashReceivedLabel => _pick(
        'Received from customer',
        'Получено от клиента',
        'Клиенттен алынған сома',
      );
  String get changeDueLabel => _pick('Change', 'Сдача', 'Қайтарым');
  String get shortAmountLabel => _pick('Short by', 'Не хватает', 'Жетпейді');
  String get customPriceLabel =>
      _pick('Receipt Price', 'Цена в чеке', 'Чектегі баға');
  String get resetAction => _pick('Reset', 'Сбросить', 'Қалпына келтіру');
  String roundTotalAction(String target) =>
      _pick('Round → $target', 'Округлить → $target', 'Дөңгелектеу → $target');
  String get splitPaymentLabel =>
      _pick('Split Payment', 'Смешанная оплата', 'Аралас төлем');
  String get secondPaymentMethodLabel =>
      _pick('Second method', 'Второй способ', 'Екінші тәсіл');
  String firstMethodAmountLabel(String method) =>
      _pick('$method amount', 'Сумма ($method)', 'Сома ($method)');
  String remainingMethodAmountLabel(String method, String amount) => _pick(
        'Remainder ($method): $amount',
        'Остаток ($method): $amount',
        'Қалдық ($method): $amount',
      );
  String get changePaymentMethodAction => _pick(
        'Change Payment',
        'Изменить способ оплаты',
        'Төлем тәсілін өзгерту',
      );
  String get paymentMethodUpdatedMsg => _pick(
        'Payment method updated',
        'Способ оплаты обновлён',
        'Төлем тәсілі жаңартылды',
      );
  String get quickEditTitle =>
      _pick('Quick Edit', 'Быстрое редактирование', 'Жылдам өңдеу');
  String get allFieldsAction =>
      _pick('All Fields', 'Все поля', 'Барлық өрістер');
  String get productHistoryAction => _pick('History', 'История', 'Тарих');
  String get stockInsHeader =>
      _pick('Incoming Deliveries', 'Приходы от поставщиков', 'Жеткізілімдер');
  String get salesHistoryHeader =>
      _pick('Sales', 'Продажи', 'Сатылымдар');
  String get noProductHistoryMsg => _pick(
        'No deliveries or sales for this product yet.',
        'По этому товару пока нет приходов и продаж.',
        'Бұл тауар бойынша кірістер мен сатылымдар жоқ.',
      );
  String get duplicateAction =>
      _pick('Duplicate', 'Дублировать', 'Көшірме жасау');
  String get addToStockInAction =>
      _pick('Add to Stock-In', 'В приход', 'Кіріске қосу');
  String get addToCartAction =>
      _pick('Add to Cart', 'В корзину', 'Себетке қосу');
  String addedToCartMsg(String name, int qty) => _pick(
        '$name added to cart ($qty)',
        '$name добавлен в корзину ($qty)',
        '$name себетке қосылды ($qty)',
      );
  String get autoLanguageLabel =>
      _pick('Auto (Device)', 'Авто (телефон)', 'Авто (құрылғы)');
  String get editExpense =>
      _pick('Edit Expense', 'Редактировать расход', 'Шығынды өңдеу');
  String get expenseUpdatedMsg =>
      _pick('Expense updated', 'Расход обновлён', 'Шығын жаңартылды');
  String get quickTemplatesLabel =>
      _pick('Quick Templates', 'Быстрые шаблоны', 'Жылдам үлгілер');
  String get tplRent => _pick('Rent', 'Аренда', 'Жалдау ақысы');
  String get tplDelivery => _pick('Delivery', 'Доставка', 'Жеткізу');
  String get tplUtilities =>
      _pick('Electricity & Utilities', 'Свет и коммунальные', 'Жарық және коммуналдық');
  String get tplPurchase =>
      _pick('Stock Purchase', 'Закупка товара', 'Тауар сатып алу');
  String get tplPackaging =>
      _pick('Bags & Packaging', 'Пакеты и упаковка', 'Пакеттер мен қаптама');
  String get tplInternet =>
      _pick('Internet & Phone', 'Интернет и связь', 'Интернет және байланыс');
  String get invoiceHistoryTitle =>
      _pick('Invoice History', 'История накладных', 'Жүкқұжаттар тарихы');
  String get searchInvoicesHint => _pick(
        'Search by name, phone, amount, item...',
        'Поиск по имени, телефону, сумме, товару...',
        'Аты, телефоны, сомасы, тауары бойынша іздеу...',
      );
  String get saleInvoicesTab => _pick('Sales', 'Продажи', 'Сатылымдар');
  String get stockInInvoicesTab => _pick('Stock-In', 'Приход', 'Кіріс');
  String get noInvoicesMatchMsg => _pick(
        'No invoices match your search.',
        'Накладные по запросу не найдены.',
        'Сұрау бойынша жүкқұжаттар табылмады.',
      );
  String get searchCustomersHint => _pick(
        'Search by name, phone, note...',
        'Поиск по имени, телефону, заметке...',
        'Аты, телефоны, ескертпе бойынша іздеу...',
      );
  String get editCustomerTitle =>
      _pick('Edit Customer', 'Редактировать клиента', 'Клиентті өңдеу');
  String get customerNoteLabel => _pick(
        'Note / Address (optional)',
        'Заметка / адрес (необяз.)',
        'Ескертпе / мекенжай (міндетті емес)',
      );
  String get customerUpdatedMsg => _pick(
        'Customer updated',
        'Данные клиента обновлены',
        'Клиент деректері жаңартылды',
      );
  String get withDebtFilter =>
      _pick('With Debt', 'С долгом', 'Қарызы бар');
  String get noCustomersMatchMsg => _pick(
        'No customers match your search.',
        'Клиенты по запросу не найдены.',
        'Сұрау бойынша клиенттер табылмады.',
      );
  String get returnOrExchangeAction =>
      _pick('Return / Exchange', 'Возврат / Обмен', 'Қайтару / Айырбастау');
  String get returnTab => _pick('Return', 'Возврат', 'Қайтару');
  String get exchangeTab => _pick('Exchange', 'Обмен', 'Айырбастау');
  String get itemsToReturnLabel => _pick(
        'Items to return',
        'Товары к возврату',
        'Қайтарылатын тауарлар',
      );
  String get returnAllBtn =>
      _pick('Return All', 'Вернуть всё', 'Барлығын қайтару');
  String get refundAmountLabel =>
      _pick('Refund Amount', 'Сумма возврата', 'Қайтару сомасы');
  String get replacementProductLabel => _pick(
        'Exchange for product',
        'Обменять на товар',
        'Басқа тауарға айырбастау',
      );
  String exchangeDiffPayLabel(String amount) => _pick(
        'Customer pays extra: $amount',
        'Доплата от клиента: $amount',
        'Клиенттің қосымша төлемі: $amount',
      );
  String exchangeDiffRefundLabel(String amount) => _pick(
        'Refund to customer: $amount',
        'Возврат клиенту: $amount',
        'Клиентке қайтарылады: $amount',
      );
  String get exchangeEvenLabel => _pick(
        'Even exchange (0 difference)',
        'Равноценный обмен (без доплаты)',
        'Тең айырбастау (қосымша төлемсіз)',
      );
  String get returnSavedMsg => _pick(
        'Return / exchange recorded',
        'Возврат / обмен оформлен',
        'Қайтару / айырбастау рәсімделді',
      );
  String get returnedBadge => _pick('Return', 'Возврат', 'Қайтару');
  String receiptNumberLabel(String code) =>
      _pick('Receipt #$code', 'Чек №$code', 'Түбіртек №$code');
  String get scanReceiptBarcodeTooltip => _pick(
        'Scan receipt barcode',
        'Сканировать штрихкод чека',
        'Чек штрих-кодын сканерлеу',
      );
  String get returnConditionLabel => _pick(
        'Returned goods',
        'Куда вернуть товар',
        'Тауарды қайда жіберу',
      );
  String get returnToStockOption =>
      _pick('Back to Stock', 'На склад', 'Қоймаға');
  String get returnAsDefectOption =>
      _pick('Defect / Write-off', 'В брак / списание', 'Ақау / есептен шығару');
  String get defectTag => _pick('defect', 'брак', 'ақау');
  String get refundMethodLabel =>
      _pick('Refund Method', 'Способ возврата денег', 'Қайтару тәсілі');
  String get extraPaymentMethodLabel =>
      _pick('Extra Payment Method', 'Способ доплаты', 'Қосымша төлем тәсілі');
  String maxRefundLimitLabel(String amount) => _pick(
        'Max refund (paid): $amount',
        'Макс. возврат (оплачено): $amount',
        'Ең көп қайтару (төленген): $amount',
      );
  String get discountAppliedNote => _pick(
        'Adjusted for receipt discount',
        'С учётом скидки по чеку',
        'Чек жеңілдігі ескерілді',
      );
  String refundExceedsPaidError(String amount) => _pick(
        'Cannot refund more than paid ($amount)',
        'Нельзя вернуть больше оплаченного ($amount)',
        'Төленген сомадан ($amount) артық қайтаруға болмайды',
      );
  String returnsFilterChip(int count, String amount) => _pick(
        'Returns ($count • $amount)',
        'Возвраты ($count • $amount)',
        'Қайтарулар ($count • $amount)',
      );
  String get returnsSummaryLabel =>
      _pick('Returns', 'Возвраты', 'Қайтарулар');
  String get returnReceiptTitle => _pick(
        'Return / Exchange Receipt',
        'Чек возврата / обмена',
        'Қайтару / айырбастау түбіртегі',
      );
  String get returnHistoryHeader => _pick(
        'Return / Exchange Details',
        'История возврата / обмена',
        'Қайтару / айырбастау тарихы',
      );
  String get returnedAmountSummaryLabel => _pick(
        'Refunded to Customer',
        'Возвращено клиенту',
        'Клиентке қайтарылды',
      );
  String get updatedSaleTotalLabel => _pick(
        'Updated Total',
        'Новый итог чека',
        'Түбіртектің жаңа сомасы',
      );
  String defectWriteOffTitle(String code) => _pick(
        'Defect write-off (#$code)',
        'Списание брака (№$code)',
        'Ақауды есептен шығару (№$code)',
      );
  String get defectReportBtn => _pick('Defects', 'Брак', 'Ақау');
  String get defectReportTitle => _pick(
        'Defect Write-Off Report',
        'Отчёт по списанному браку',
        'Есептен шығарылған ақау есебі',
      );
  String get noDefectsMsg => _pick(
        'No defective write-offs for this period.',
        'За выбранный период списаний брака нет.',
        'Бұл кезеңде ақау бойынша есептен шығару жоқ.',
      );
  String get totalDefectCostLabel =>
      _pick('Total Cost', 'Закупочная сумма', 'Өзіндік құны');
  String get shareDefectReportBtn => _pick(
        'Share Report (Supplier Claim)',
        'Отправить отчёт поставщику',
        'Жеткізушіге есеп жіберу',
      );
}
