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
  static String _q(num v) {
    if ((v - v.roundToDouble()).abs() < 0.0005) return v.round().toString();
    var s = v.toStringAsFixed(3);
    while (s.contains('.') && (s.endsWith('0') || s.endsWith('.'))) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  String stockInSavedMsg(num units) => _pick(
        'Received ${_q(units)} units into stock',
        'Оприходовано ${_q(units)} шт. на склад',
        'Қоймаға ${_q(units)} дана қабылданды',
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
  String unitsCount(num count) => _pick('${_q(count)} units', '${_q(count)} шт.', '${_q(count)} дана');
  String get stockValueLabel => _pick('Stock Value', 'Сумма склада', 'Қор құны');
  String get costBasisLabel => _pick('Cost basis', 'По закупке', 'Өзіндік құн');
  String get todayProfitLabel => _pick('Today Profit', 'Прибыль сегодня', 'Бүгінгі пайда');
  String revSubtitle(String rev) => _pick('Rev $rev', 'Выручка $rev', 'Түсім $rev');
  String get outOfStock => _pick('Out of stock', 'Нет в наличии', 'Таусылды');
  String lowStockBadge(num count) => _pick('Low: ${_q(count)}', 'Мало: ${_q(count)}', 'Аз: ${_q(count)}');
  String inStockBadge(num count) =>
      _pick('In stock: ${_q(count)}', 'В наличии: ${_q(count)}', 'Қолда бар: ${_q(count)}');
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
  String stockCountLabel(num count) => _pick('Stock: ${_q(count)}', 'Остаток: ${_q(count)}', 'Қалдық: ${_q(count)}');
  String inCartLabel(num count) => _pick('In cart: ${_q(count)}', 'В корзине: ${_q(count)}', 'Себетте: ${_q(count)}');
  String get outShort => _pick('Out', 'Нет', 'Жоқ');
  String get addShort => _pick('Add', 'Добавить', 'Қосу');
  String outOfStockMsg(String name) =>
      _pick('$name is out of stock', '$name нет в наличии', '$name қоймада жоқ');
  String onlyLeftMsg(num count) =>
      _pick('Only ${_q(count)} left in stock', 'В наличии только ${_q(count)} шт.', 'Қоймада тек ${_q(count)} дана қалды');
  String cartSummary(num count, String total) =>
      _pick('${_q(count)} item(s) • $total', '${_q(count)} шт. • $total', '${_q(count)} дана • $total');
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
  String saleRecordedMsg(String total, num units) => _pick(
        'Sale recorded: $total (${_q(units)} items)',
        'Продажа оформлена: $total (${_q(units)} шт.)',
        'Сатылым тіркелді: $total (${_q(units)} дана)',
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
  String unitsShort(num count) => _pick('${_q(count)} units', '${_q(count)} шт.', '${_q(count)} дана');
  String itemsShort(int count) => _pick('$count items', '$count поз.', '$count тауар');
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
  String scannedAddedToStockInMsg(num added, String name, num totalQty) => _pick(
        '+${_q(added)}: $name (in stock-in: ${_q(totalQty)})',
        '+${_q(added)}: $name (в приходе: ${_q(totalQty)})',
        '+${_q(added)}: $name (кірісте: ${_q(totalQty)})',
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
  String scannedAddedToStocktakeMsg(num added, String name, num actualQty) =>
      _pick(
        '+${_q(added)}: $name (actual: ${_q(actualQty)})',
        '+${_q(added)}: $name (факт: ${_q(actualQty)})',
        '+${_q(added)}: $name (нақты: ${_q(actualQty)})',
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
  String scannedAddedToCartMsg(num added, String name, num totalQty) => _pick(
        '+${_q(added)}: $name (in cart: ${_q(totalQty)})',
        '+${_q(added)}: $name (в корзине: ${_q(totalQty)})',
        '+${_q(added)}: $name (себетте: ${_q(totalQty)})',
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
  String addedToCartMsg(String name, num qty) => _pick(
        '$name added to cart (${_q(qty)})',
        '$name добавлен в корзину (${_q(qty)})',
        '$name себетке қосылды (${_q(qty)})',
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
  String get addProductToReceiptBtn => _pick(
        'Add Item to Receipt',
        'Добавить товар в чек',
        'Чекке тауар қосу',
      );
  String get googleSheetsBtn => _pick(
        'Google Sheets Sync',
        'Синхронизация с Google Таблицей',
        'Google Кестемен синхрондау',
      );
  String get sheetsWebAppUrlLabel => _pick(
        'Apps Script Web App URL *',
        'URL веб-приложения Apps Script *',
        'Apps Script веб-қосымшасының URL-і *',
      );
  String get sheetsSecretLabel => _pick(
        'Secret Key (optional)',
        'Секретный ключ (необязательно)',
        'Құпия кілт (міндетті емес)',
      );
  String get copyAppsScriptBtn => _pick(
        'Copy Apps Script',
        'Копировать скрипт для таблицы',
        'Кестеге арналған скриптті көшіру',
      );
  String get checkAndSyncBtn => _pick(
        'Check & Compare',
        'Проверить и сравнить',
        'Тексеру және салыстыру',
      );
  String get pushAllToSheetsBtn => _pick(
        'Upload All to Sheets',
        'Выгрузить всё в таблицу',
        'Барлығын кестеге жүктеу',
      );
  String get applySyncBtn => _pick(
        'Apply Sync',
        'Применить синхронизацию',
        'Синхрондауды қолдану',
      );
  String get syncNoDifferencesMsg => _pick(
        'Everything is in sync. No differences found.',
        'Всё совпадает. Расхождений и конфликтов не найдено.',
        'Барлығы сәйкес келеді. Айырмашылық табылмады.',
      );
  String syncConflictsCount(int count) => _pick(
        'Conflicts: $count',
        'Конфликты: $count',
        'Қайшылықтар: $count',
      );
  String syncNewFromSheetCount(int count) => _pick(
        'New in Sheet: $count',
        'Новые из таблицы: $count',
        'Кестедегі жаңа: $count',
      );
  String syncNewOnPhoneCount(int count) => _pick(
        'New on Phone: $count',
        'Новые с телефона: $count',
        'Телефондағы жаңа: $count',
      );
  String get useSheetValueBtn => _pick(
        'From Sheet',
        'Из таблицы',
        'Кестеден',
      );
  String get keepPhoneValueBtn => _pick(
        'Keep Phone',
        'С телефона',
        'Телефоннан',
      );
  String get allFromSheetBtn => _pick(
        'All from Sheet',
        'Все из таблицы',
        'Барлығын кестеден',
      );
  String get allFromPhoneBtn => _pick(
        'All from Phone',
        'Все с телефона',
        'Барлығын телефоннан',
      );
  String get phoneLabel => _pick('Phone', 'Телефон', 'Телефон');
  String get sheetLabel => _pick('Sheet', 'Таблица', 'Кесте');
  String get syncCompletedMsg => _pick(
        'Google Sheets sync completed',
        'Синхронизация с Google Таблицей завершена',
        'Google Кестемен синхрондау аяқталды',
      );
  String get enterSheetsUrlMsg => _pick(
        'Enter your Apps Script Web App URL first',
        'Сначала укажите URL веб-приложения Apps Script',
        'Алдымен Apps Script URL мекенжайын енгізіңіз',
      );
  String get copyForGoogleSheetsBtn => _pick(
        'Copy for Google Sheets (Paste to A1)',
        'Копировать для Google Таблицы (в A1)',
        'Google Кесте үшін көшіру (A1-ге қою)',
      );
  String get shareReadableCsvBtn => _pick(
        'Share Readable Table (CSV)',
        'Отправить читаемую таблицу (CSV)',
        'Оқылатын кестені жіберу (CSV)',
      );
  String get copyImportTemplateBtn => _pick(
        'Copy Import Template',
        'Скопировать шаблон импорта',
        'Импорт үлгісін көшіру',
      );
  String get importFromTableBtn => _pick(
        'Import Goods (Paste Table / CSV)',
        'Импорт товаров (из таблицы / CSV)',
        'Тауарларды импорттау (кесте / CSV)',
      );
  String get pasteTableHint => _pick(
        'Paste rows copied from Google Sheets, Excel, or CSV...',
        'Вставьте строки из Google Таблицы, Excel или CSV...',
        'Google Кесте, Excel немесе CSV жолдарын осында қойыңыз...',
      );
  String get checkImportBtn => _pick(
        'Check & Preview',
        'Проверить',
        'Тексеру',
      );
  String get importNoRowsMsg => _pick(
        'No valid product rows found. Check column headers or use the template.',
        'Не найдено товаров. Проверьте заголовки столбцов или используйте шаблон.',
        'Тауар жолдары табылмады. Баған атауларын тексеріңіз немесе үлгіні қолданыңыз.',
      );
  String importCompletedMsg(int updated, int added) => _pick(
        'Imported: updated $updated, added $added',
        'Импорт завершён: обновлено $updated, добавлено $added',
        'Импорт аяқталды: жаңартылды $updated, қосылды $added',
      );
  String get copiedForSheetsMsg => _pick(
        'Copied! Open Google Sheets and paste into cell A1.',
        'Скопировано! Откройте Google Таблицу и вставьте в ячейку A1.',
        'Көшірілді! Google Кестені ашып, A1 ұяшығына қойыңыз.',
      );
  String get copiedTemplateMsg => _pick(
        'Template copied! Paste into Google Sheets/Notes, edit, and import back.',
        'Шаблон скопирован! Вставьте в таблицу или заметки, заполните и импортируйте.',
        'Үлгі көшірілді! Кестеге қойып, толтырып, қайта импорттаңыз.',
      );
  String get totalPurchasesForPeriodLabel => _pick(
        'Purchases for period',
        'Закупки за период',
        'Кезеңдегі сатып алу',
      );
  String get repeatStockInBtn => _pick(
        'Repeat Stock-In',
        'Повторить приход',
        'Кірісті қайталау',
      );
  String get deleteStockInTitle => _pick(
        'Delete invoice?',
        'Удалить накладную?',
        'Жүкқұжатты жою керек пе?',
      );
  String deleteStockInBody(num units) => _pick(
        'Delete this stock-in invoice and roll back stock (-${_q(units)} units)?',
        'Удалить приходную накладную и откатить остатки на складе (−${_q(units)} шт.)?',
        'Бұл кіріс жүкқұжатын жойып, қойма қалдығын қайтару керек пе (−${_q(units)} дана)?',
      );
  String get stockInDeletedMsg => _pick(
        'Invoice deleted, stock rolled back',
        'Накладная удалена, остатки откатаны',
        'Жүкқұжат жойылды, қалдық қайтарылды',
      );
  String get changeHistoryBtn => _pick(
        'Change History',
        'История изменений',
        'Өзгерістер тарихы',
      );
  String get noChangesYetMsg => _pick(
        'No product changes recorded yet.',
        'Изменений по товарам пока не зафиксировано.',
        'Тауарлар бойынша өзгерістер әлі тіркелмеген.',
      );
  String get filterPrice => _pick('Price', 'Цена', 'Баға');
  String get filterStock => _pick('Stock', 'Количество', 'Саны');
  String get filterWeight => _pick('Weight', 'Вес', 'Салмақ');
  String get filterOther => _pick('Other', 'Прочее', 'Басқа');
  String changeSourceLabel(String source) {
    switch (source) {
      case 'create':
        return _pick('New Item', 'Новый товар', 'Жаңа тауар');
      case 'stock_in':
        return _pick('Stock-In', 'Приход', 'Кіріс');
      case 'stock_in_delete':
        return _pick('Stock-In Deleted', 'Отмена прихода', 'Кірісті жою');
      case 'stocktake':
        return _pick('Stocktake', 'Ревизия', 'Түгендеу');
      case 'sync':
        return _pick('Sync / Import', 'Таблица / Импорт', 'Кесте / Импорт');
      case 'archive':
        return _pick('Archive', 'Архив', 'Мұрағат');
      case 'trash':
        return _pick('Trash', 'Корзина', 'Себет');
      case 'restore':
        return _pick('Restore', 'Восстановление', 'Қалпына келтіру');
      case 'revert':
        return _pick('Revert', 'Откат', 'Қайтару');
      default:
        return _pick('Edit', 'Редактирование', 'Өңдеу');
    }
  }
  String get yesterdayLabel => _pick('Yesterday', 'Вчера', 'Кеше');
  String get thisWeekLabel =>
      _pick('This Week', 'На этой неделе', 'Осы аптада');
  String get earlierLabel => _pick('Earlier', 'Ранее', 'Бұрын');
  String get productUnavailableMsg => _pick(
        'Product is no longer in the active catalog.',
        'Товара уже нет в активном каталоге.',
        'Тауар белсенді каталогта жоқ.',
      );
  String get allSourcesLabel =>
      _pick('All Sources', 'Все источники', 'Барлық көздер');
  String get revertAction => _pick('Revert', 'Откатить', 'Қайтару');
  String get revertedMsg =>
      _pick('Change reverted', 'Изменение откачено', 'Өзгеріс қайтарылды');
  String get revertConfirmTitle => _pick(
        'Revert change?',
        'Откатить изменение?',
        'Өзгерісті қайтару керек пе?',
      );
  String revertConfirmBody(String name) => _pick(
        'Restore previous values for "$name"?',
        'Вернуть прежние значения для «$name»?',
        '«$name» тауарының бұрынғы мәндерін қайтару керек пе?',
      );
  String get statusFieldLabel => _pick('Status', 'Статус', 'Мәртебе');
  String get statusActiveLabel => _pick('Active', 'Активен', 'Белсенді');
  String get statusArchivedLabel =>
      _pick('Archived', 'В архиве', 'Мұрағатта');
  String get statusTrashedLabel =>
      _pick('In Trash', 'В корзине', 'Себетте');
  String get clearHistoryBtn => _pick(
        'Clear History',
        'Очистить историю',
        'Тарихты тазалау',
      );
  String get clearHistoryTitle => _pick(
        'Clear change history?',
        'Очистить историю изменений?',
        'Өзгерістер тарихын тазалау керек пе?',
      );
  String get clearOlder30DaysAction => _pick(
        'Older than 30 days',
        'Старше 30 дней',
        '30 күннен ескілерін',
      );
  String get clearAllAction =>
      _pick('Clear All', 'Очистить всё', 'Барлығын тазалау');
  String clearedHistoryCountMsg(int count) => _pick(
        'Removed $count entries',
        'Удалено записей: $count',
        'Жойылған жазбалар: $count',
      );
  String revertPreviewHeader(String source, String time) => _pick(
        'Reverting: $source • $time',
        'Откат правки: $source • $time',
        'Қайтарылатын өзгеріс: $source • $time',
      );
  String get revertAlreadyMatchesMsg => _pick(
        'Current values already match.',
        'Текущие значения уже совпадают с прежними.',
        'Ағымдағы мәндер бұрынғы мәндермен сәйкес келеді.',
      );
  String get accessSectionLabel => _pick('Access', 'Доступ', 'Қолжетімділік');
  String get shopAndDataSectionLabel =>
      _pick('Shop & Data', 'Магазин и данные', 'Дүкен және деректер');
  String get pinIsSetStatus => _pick('Set', 'Задан', 'Орнатылған');
  String get pinNotSetStatus =>
      _pick('Not set', 'Не задан', 'Орнатылмаған');
  String get connectedStatus =>
      _pick('Connected', 'Подключена', 'Қосылған');
  String get notConfiguredStatus =>
      _pick('Not configured', 'Не настроена', 'Бапталмаған');
  String get cashierModeActiveStatus => _pick(
        'Active — restricted access',
        'Включён — ограниченный доступ',
        'Қосулы — шектеулі қолжетімділік',
      );
  String get ownerModeActiveStatus => _pick(
        'Owner access unlocked',
        'Полный доступ владельца',
        'Иесінің толық қолжетімділігі',
      );
  String get downloadHistoryBtn => _pick(
        'Download History',
        'Скачать историю',
        'Тарихты жүктеу',
      );
  String get downloadHistoryTitle => _pick(
        'Download Change History',
        'Скачать историю изменений',
        'Өзгерістер тарихын жүктеу',
      );
  String get period30Days => _pick('30 Days', '30 дней', '30 күн');
  String get period1Year => _pick('1 Year', '1 год', '1 жыл');
  String get period2Years => _pick('2 Years', '2 года', '2 жыл');
  String get period5Years =>
      _pick('5 Years (All)', '5 лет (Всё)', '5 жыл (Барлығы)');
  String get priceHistory5YearsHeader => _pick(
        'Price History (5 Years)',
        'История цен (за 5 лет)',
        'Баға тарихы (5 жыл)',
      );
  String get stockInRateHint => _pick(
        'Rate on date (optional)',
        'Курс на дату (необяз.)',
        'Кіріс күніндегі бағам',
      );
  String get noChangesForPeriodMsg => _pick(
        'No changes for selected period.',
        'За выбранный период изменений нет.',
        'Таңдалған кезеңде өзгерістер жоқ.',
      );
  String get customerPhoneRequiredForDebt => _pick(
        'Customer Phone * (for post-payment)',
        'Телефон клиента * (для постоплаты)',
        'Клиент телефоны * (қарызға сату үшін)',
      );
  String get enterCustomerPhone => _pick(
        'Enter debtor phone number',
        'Укажите номер телефона должника',
        'Борышкердің телефон нөмірін енгізіңіз',
      );
  String debtPurchasesCountLabel(int total, int active) => _pick(
        'Debt purchases: $total ($active active)',
        'Покупок в долг: $total (активных: $active)',
        'Қарызға сатып алу: $total (белсенді: $active)',
      );
  String get debtRepaymentsHeader => _pick(
        'Debt Repayments',
        'История возвратов долга',
        'Қарызды қайтару тарихы',
      );
  String get activeDebtorsFilter =>
      _pick('Active', 'Активные', 'Белсенді');
  String get allDebtCustomersFilter => _pick(
        'All Debt History',
        'Вся история долгов',
        'Барлық қарыз тарихы',
      );
  String get debtPaidBadge => _pick('Settled', 'Погашен', 'Өтелді');
  String get negativeStockReminderTitle => _pick(
        'Restore Negative Stock',
        'Восстановите минусовой товар',
        'Минус қалдықты қалпына келтіріңіз',
      );
  String get negativeStockReminderBody => _pick(
        'These products were sold out of stock. Restock or return them to clear the minus:',
        'Эти товары были проданы без остатка (в минус). Оформите приход или поправьте остаток:',
        'Бұл тауарлар қалдықсыз (минусқа) сатылды. Кіріс рәсімдеңіз немесе қалдықты түзетіңіз:',
      );
  String reminderCountOfFive(int shown, int total) => _pick(
        'Reminder $shown of $total',
        'Напоминание $shown из $total',
        'Еске салу $shown / $total',
      );
  String get remindLaterBtn =>
      _pick('Remind Later', 'Напомнить позже', 'Кейінірек еске салу');
  String get restoreStockNowBtn => _pick(
        'Close via Stock-In',
        'Закрыть через Приход',
        'Кіріс арқылы жабу',
      );
  String get allowNegativeStockLabel => _pick(
        'Allow Negative Stock Sales',
        'Разрешать продажу в минус',
        'Минусқа сатуға рұқсат ету',
      );
  String get allowNegativeStockHint => _pick(
        'Automatically disabled in Cashier Mode',
        'Отключается в режиме продавца',
        'Сатушы режимінде автоматты түрде өшеді',
      );
  String inMinusFilter(int count) =>
      _pick('In Minus ($count)', 'В минусе ($count)', 'Минуста ($count)');
  String get exportSectionsHeader => _pick(
        'Export Sections to Separate Tabs',
        'Выгрузка разделов в отдельные листы',
        'Бөлімдерді бөлек парақтарға жүктеу',
      );
  String get sheetTabNameLabel =>
      _pick('Sheet Tab Name', 'Название листа', 'Парақ атауы');
  String get uploadToSheetBtn =>
      _pick('Upload to Tab', 'В лист', 'Параққа');
  String get uploadAllSectionsBtn => _pick(
        'Upload All 9 Sections',
        'Выгрузить все 9 разделов',
        'Барлық 9 бөлімді жүктеу',
      );
  String get copyTsvShortBtn =>
      _pick('Copy (A1)', 'Копировать (A1)', 'Көшіру (A1)');
  String sectionUploadedMsg(String sheetName, int count) => _pick(
        'Uploaded $count rows to "$sheetName"',
        'Выгружено в лист «$sheetName»: $count строк',
        '«$sheetName» парағына $count жол жүктелді',
      );
  String get allSectionsUploadedMsg => _pick(
        'All sections uploaded to Google Sheets',
        'Все разделы выгружены в Google Таблицу',
        'Барлық бөлімдер Google Кестеге жүктелді',
      );
  String get syncAllCatalogAndSectionsBtn => _pick(
        'Sync All (Catalog + 9 Tabs)',
        'Выгрузить всё (Каталог + 9 разделов)',
        'Барлығын жүктеу (Каталог + 9 бөлім)',
      );
  String get allCatalogAndSectionsSyncedMsg => _pick(
        'Catalog and all 9 sections synced to Google Sheets',
        'Каталог и все 9 разделов выгружены в Google Таблицу',
        'Каталог пен барлық 9 бөлім Google Кестеге жүктелді',
      );
  String get sectionRestock => _pick('To Restock', 'К закупке', 'Сатып алуға');
  String get sectionStockSnapshots =>
      _pick('Stock Snapshots', 'Снимки склада', 'Қойма суреттері');
  String get sectionChanges => _pick('Change History', 'История изменений', 'Өзгерістер тарихы');
  String get sectionSales => _pick('Sales', 'Продажи', 'Сатылымдар');
  String get sectionStockIns => _pick('Stock-In', 'Приходы', 'Кірістер');
  String get sectionCustomers => _pick('Customers', 'Клиенты', 'Клиенттер');
  String get sectionDebts => _pick('Debts & Repayments', 'Долги', 'Қарыздар');
  String get sectionExpenses => _pick('Expenses', 'Расходы', 'Шығындар');
  String get sectionDefects => _pick('Defect Write-Offs', 'Брак', 'Ақау');
  String get restoreAllFromSheetsBtn => _pick(
        'Restore All from Google Sheets',
        'Восстановить всё из Google Таблицы',
        'Google Кестеден бәрін қалпына келтіру',
      );
  String get restoreAllConfirmTitle => _pick(
        'Restore full backup?',
        'Восстановить всю базу?',
        'Барлық деректі қалпына келтіру керек пе?',
      );
  String restoreAllConfirmBody(String? updatedAt) => _pick(
        'Replace current app data with the backup from Google Sheets${updatedAt != null && updatedAt.isNotEmpty ? ' ($updatedAt)' : ''}?',
        'Заменить текущие данные на телефоне полной резервной копией из Google Таблицы${updatedAt != null && updatedAt.isNotEmpty ? ' ($updatedAt)' : ''}?',
        'Телефондағы деректерді Google Кестедегі толық көшірмемен${updatedAt != null && updatedAt.isNotEmpty ? ' ($updatedAt)' : ''} алмастыру керек пе?',
      );
  String get noCloudBackupMsg => _pick(
        'No full backup found in Google Sheets yet. Run "Sync All" first.',
        'В Google Таблице ещё нет полного бэкапа. Сначала нажмите «Выгрузить всё».',
        'Google Кестеде толық сақтық көшірме жоқ. Алдымен «Барлығын жүктеу» түймесін басыңыз.',
      );
  String get restorePrevFromSheetsBtn => _pick(
        'Restore Yesterday\'s Backup (_Backup_Prev)',
        'Восстановить вчерашнюю копию (_Backup_Prev)',
        'Кешегі көшірмені қалпына келтіру (_Backup_Prev)',
      );
  String get noPrevCloudBackupMsg => _pick(
        'No yesterday\'s backup (_Backup_Prev) yet. It is created automatically before the next day\'s overwrite.',
        'Вчерашней копии (_Backup_Prev) ещё нет — она создаётся автоматически перед перезаписью на следующий день.',
        'Кешегі көшірме (_Backup_Prev) әлі жоқ — ол келесі күні қайта жазу алдында автоматты жасалады.',
      );
  String get autoBackupLabel => _pick(
        'Auto-Sync Changes to Sheets',
        'Автосинхронизация в Google Таблицу',
        'Google Кестеге автосинхрондау',
      );
  String get autoBackupHint => _pick(
        'Instantly syncs Catalog, Sales & _Backup; heavy tabs (History, Snapshots, etc.) sync once a day or manually',
        'Мгновенно обновляет Каталог, Продажи и _Backup; тяжёлые листы (История, Снимки и др.) — раз в день или по кнопке',
        'Каталог, Сатылымдар және _Backup-ты лезде жаңартады; ауыр парақтар (Тарих, Суреттер т.б.) — күніне 1 рет немесе батырмамен',
      );
  String lastAutoBackupStatus(String time) => _pick(
        'Last auto-backup: $time',
        'Последний автобэкап: $time',
        'Соңғы автобэкап: $time',
      );
  String get changePinTitle => _pick(
        'Change Owner PIN',
        'Изменить PIN-код владельца',
        'Иесінің PIN-кодын өзгерту',
      );
  String get currentPinLabel => _pick(
        'Current PIN',
        'Текущий PIN-код',
        'Қазіргі PIN-код',
      );
  String get newPinLabel => _pick(
        'New PIN',
        'Новый PIN-код',
        'Жаңа PIN-код',
      );
  String get confirmPinLabel => _pick(
        'Confirm PIN',
        'Повторите PIN-код',
        'PIN-кодты қайталаңыз',
      );
  String get pinsDoNotMatchMsg => _pick(
        'PIN codes do not match',
        'PIN-коды не совпадают',
        'PIN-кодтар сәйкес келмейді',
      );
  String get removePinAction => _pick(
        'Remove PIN',
        'Удалить PIN',
        'PIN-кодты жою',
      );
  String get pinRemovedMsg => _pick(
        'PIN removed',
        'PIN-код удалён',
        'PIN-код жойылды',
      );
  String get biometricUnlockLabel => _pick(
        'Fingerprint / Face / Device Lock',
        'Отпечаток / Лицо / Пароль телефона',
        'Саусақ ізі / Бет / Телефон құпия сөзі',
      );
  String get biometricUnlockHint => _pick(
        'Unlock Owner Mode with fingerprint, face, pattern, or phone PIN',
        'Вход в режим владельца по отпечатку, лицу, графическому ключу или паролю экрана',
        'Иесі режиміне саусақ ізі, бет, өрнек немесе экран құпия сөзімен кіру',
      );
  String get biometricPromptReason => _pick(
        'Verify your identity to unlock Owner Mode',
        'Подтвердите личность для входа в режим владельца',
        'Иесі режиміне кіру үшін жеке басыңызды растаңыз',
      );
  String get biometricUnavailableMsg => _pick(
        'Set up a fingerprint, face unlock, or screen lock in phone Settings first',
        'Сначала настройте отпечаток, лицо или блокировку экрана в настройках телефона',
        'Алдымен телефон баптауларында саусақ ізін, бетті немесе экран құлпын қосыңыз',
      );
  String get biometricFailedMsg => _pick(
        'Verification failed or cancelled',
        'Проверка не пройдена или отменена',
        'Тексеру өтпеді немесе тоқтатылды',
      );
  String get useBiometricBtn => _pick(
        'Use Fingerprint / Device Lock',
        'Отпечаток / пароль телефона',
        'Саусақ ізі / телефон құпия сөзі',
      );
  String get discountPercentLabel =>
      _pick('Discount %', 'Скидка %', 'Жеңілдік %');
  String get deleteCustomerRecommendationTitle => _pick(
        'Remove from suggestions?',
        'Удалить из рекомендаций?',
        'Ұсыныстардан жою керек пе?',
      );
  String deleteCustomerRecommendationBody(String name) => _pick(
        'Remove "$name" from customer suggestions and list? Past sales history will be kept.',
        'Удалить «$name» из рекомендаций и списка клиентов? История продаж сохранится.',
        '«$name» клиентін ұсыныстар мен тізімнен жою керек пе? Сатылым тарихы сақталады.',
      );
  String get customerRemovedMsg => _pick(
        'Customer removed',
        'Клиент удалён',
        'Клиент жойылды',
      );
  String get syncingWithSheetsStatus => _pick(
        'Syncing with Google Sheets...',
        'Синхронизация с Google Таблицей...',
        'Google Кестемен синхрондалуда...',
      );
  String sheetSyncUpdatedNotice(int updated, int added) {
    final partsEn = <String>[
      if (updated > 0) 'updated $updated',
      if (added > 0) 'added $added',
    ];
    final partsRu = <String>[
      if (updated > 0) 'обновлено $updated',
      if (added > 0) 'добавлено $added',
    ];
    final partsKk = <String>[
      if (updated > 0) 'жаңартылды $updated',
      if (added > 0) 'қосылды $added',
    ];
    return _pick(
      'Google Sheets synced: ${partsEn.join(', ')}',
      'Из Google Таблицы: ${partsRu.join(', ')}',
      'Google Кестеден: ${partsKk.join(', ')}',
    );
  }
  String get sheetSyncUpToDateNotice => _pick(
        'Google Sheets: up to date',
        'Google Таблица: данные актуальны',
        'Google Кесте: деректер өзекті',
      );
  String sheetSyncErrorNotice(String error) => _pick(
        'Google Sheets sync error: $error',
        'Ошибка синхронизации с таблицей: $error',
        'Кестемен синхрондау қатесі: $error',
      );
  String get duplicateCheckBtn => _pick(
        'Check Duplicates',
        'Проверить дубликаты',
        'Қайталанғандарды тексеру',
      );
  String get duplicateFoundTitle => _pick(
        'Duplicate Product Found',
        'Найден дубликат товара',
        'Тауардың көшірмесі табылды',
      );
  String get duplicateFoundBody => _pick(
        'A similar product already exists in your catalog:',
        'В каталоге уже есть похожий товар:',
        'Каталогта осыған ұқсас тауар бар:',
      );
  String get saveAnywayAction => _pick(
        'Save Anyway',
        'Всё равно сохранить',
        'Бәрібір сақтау',
      );
  String get duplicateMatchName => _pick(
        'Same name',
        'Совпадает название',
        'Атауы бірдей',
      );
  String get duplicateMatchBarcode => _pick(
        'Same barcode',
        'Совпадает штрихкод',
        'Штрих-коды бірдей',
      );
  String get duplicateMatchId => _pick(
        'Same ID',
        'Совпадает ID',
        'ID бірдей',
      );
  String get noDuplicatesFoundMsg => _pick(
        'No duplicate products found.',
        'Дубликаты товаров не найдены.',
        'Қайталанған тауарлар табылмады.',
      );
  String phoneDuplicatesCount(int count) => _pick(
        'Phone Duplicates: $count',
        'Дубликаты на телефоне: $count',
        'Телефондағы дубликаттар: $count',
      );
  String sheetDuplicatesCount(int count) => _pick(
        'Sheet Duplicates: $count',
        'Дубликаты в таблице: $count',
        'Кестедегі дубликаттар: $count',
      );
  String get sheetDuplicatesCleanedNote => _pick(
        'Duplicate rows in Google Sheets will be cleaned when you apply sync.',
        'Дубликаты строк в Google Таблице будут очищены при применении синхронизации.',
        'Синхрондауды қолданғанда Google Кестедегі қайталанған жолдар тазаланады.',
      );
  String rowNumberLabel(int row) => _pick(
        'Row $row',
        'Строка $row',
        '$row-жол',
      );
  String get sortLabel => _pick('Sort', 'Сортировка', 'Сұрыптау');
  String get sortNewest => _pick(
        'Latest Added',
        'Последние добавленные',
        'Соңғы қосылғандар',
      );
  String get sortPriceDesc => _pick(
        'Price: High → Low',
        'Цена: дорогие сверху',
        'Баға: қымбаттан',
      );
  String get sortPriceAsc => _pick(
        'Price: Low → High',
        'Цена: дешёвые сверху',
        'Баға: арзаннан',
      );
  String get sortStockDesc => _pick(
        'Stock: Most first',
        'Количество: больше всего',
        'Қалдық: ең көбі',
      );
  String get sortStockAsc => _pick(
        'Stock: Least first',
        'Количество: меньше всего',
        'Қалдық: ең азы',
      );
  String get sortMostSold => _pick(
        'Most Sold',
        'Самые продаваемые',
        'Ең көп сатылған',
      );
  String get sortNameAsc => _pick(
        'Name (A–Z)',
        'По названию (А–Я)',
        'Атауы бойынша (А–Я)',
      );
  String get sortMarginDesc => _pick(
        'Highest Margin',
        'Самая высокая маржа',
        'Ең жоғары маржа',
      );
  String get highlightLatestAdded => _pick(
        'Latest Added',
        'Последний добавленный',
        'Соңғы қосылған',
      );
  String get highlightMostExpensive => _pick(
        'Most Expensive',
        'Самый дорогой',
        'Ең қымбат',
      );
  String get highlightCheapest => _pick(
        'Cheapest',
        'Самый дешёвый',
        'Ең арзан',
      );
  String get highlightMostStock => _pick(
        'Most in Stock',
        'Больше всего',
        'Ең көп қалдық',
      );
  String get highlightBestSeller => _pick(
        'Best Seller',
        'Хит продаж',
        'Ең көп сатылған',
      );
  String get highlightHighestMargin => _pick(
        'Top Margin',
        'Макс. маржа',
        'Ең жоғары маржа',
      );
  String soldUnitsBadge(num count) => _pick(
        'Sold: ${_q(count)}',
        'Продано: ${_q(count)}',
        'Сатылды: ${_q(count)}',
      );
  String get analyticsTopTab => _pick('Goods', 'Товары', 'Тауарлар');
  String get analyticsTimeTab =>
      _pick('Days & Hours', 'Дни и часы', 'Күн мен сағат');
  String get analyticsSeasonTab =>
      _pick('Seasonality', 'Сезонность', 'Маусымдылық');
  String get salesByWeekdayHeader => _pick(
        'Sales by Day of Week',
        'Продажи по дням недели',
        'Апта күндері бойынша сатылым',
      );
  String get salesByHourHeader => _pick(
        'Sales by Hour',
        'Продажи по часам',
        'Сағаттар бойынша сатылым',
      );
  String get salesByMonthHeader => _pick(
        'Monthly Seasonality',
        'Сезонность по месяцам',
        'Айлар бойынша маусымдылық',
      );
  String get peakWeekdayLabel =>
      _pick('Peak Day', 'Пиковый день', 'Ең белсенді күн');
  String get peakHourLabel =>
      _pick('Peak Hour', 'Пиковый час', 'Ең белсенді сағат');
  String get peakMonthLabel =>
      _pick('Peak Month', 'Пиковый месяц', 'Ең белсенді ай');
  String get avgMonthLabel =>
      _pick('Monthly Avg', 'Среднее в месяц', 'Айлық орташа');
  String get allYearsLabel =>
      _pick('All Years', 'Все годы', 'Барлық жыл');
  String ordersShort(int count) =>
      _pick('$count ord.', '$count чек.', '$count чек');
  String weekdayShort(int weekday) {
    switch (weekday) {
      case 1:
        return _pick('Mon', 'Пн', 'Дс');
      case 2:
        return _pick('Tue', 'Вт', 'Сс');
      case 3:
        return _pick('Wed', 'Ср', 'Ср');
      case 4:
        return _pick('Thu', 'Чт', 'Бс');
      case 5:
        return _pick('Fri', 'Пт', 'Жм');
      case 6:
        return _pick('Sat', 'Сб', 'Сб');
      case 7:
        return _pick('Sun', 'Вс', 'Жс');
      default:
        return '';
    }
  }
  String weekdayFull(int weekday) {
    switch (weekday) {
      case 1:
        return _pick('Monday', 'Понедельник', 'Дүйсенбі');
      case 2:
        return _pick('Tuesday', 'Вторник', 'Сейсенбі');
      case 3:
        return _pick('Wednesday', 'Среда', 'Сәрсенбі');
      case 4:
        return _pick('Thursday', 'Четверг', 'Бейсенбі');
      case 5:
        return _pick('Friday', 'Пятница', 'Жұма');
      case 6:
        return _pick('Saturday', 'Суббота', 'Сенбі');
      case 7:
        return _pick('Sunday', 'Воскресенье', 'Жексенбі');
      default:
        return '';
    }
  }
  String monthShort(int month) {
    switch (month) {
      case 1:
        return _pick('Jan', 'Янв', 'Қаң');
      case 2:
        return _pick('Feb', 'Фев', 'Ақп');
      case 3:
        return _pick('Mar', 'Мар', 'Нау');
      case 4:
        return _pick('Apr', 'Апр', 'Сәу');
      case 5:
        return _pick('May', 'Май', 'Мам');
      case 6:
        return _pick('Jun', 'Июн', 'Мау');
      case 7:
        return _pick('Jul', 'Июл', 'Шіл');
      case 8:
        return _pick('Aug', 'Авг', 'Там');
      case 9:
        return _pick('Sep', 'Сен', 'Қыр');
      case 10:
        return _pick('Oct', 'Окт', 'Қаз');
      case 11:
        return _pick('Nov', 'Ноя', 'Қар');
      case 12:
        return _pick('Dec', 'Дек', 'Жел');
      default:
        return '';
    }
  }
  String monthFull(int month) {
    switch (month) {
      case 1:
        return _pick('January', 'Январь', 'Қаңтар');
      case 2:
        return _pick('February', 'Февраль', 'Ақпан');
      case 3:
        return _pick('March', 'Март', 'Наурыз');
      case 4:
        return _pick('April', 'Апрель', 'Сәуір');
      case 5:
        return _pick('May', 'Май', 'Мамыр');
      case 6:
        return _pick('June', 'Июнь', 'Маусым');
      case 7:
        return _pick('July', 'Июль', 'Шілде');
      case 8:
        return _pick('August', 'Август', 'Тамыз');
      case 9:
        return _pick('September', 'Сентябрь', 'Қыркүйек');
      case 10:
        return _pick('October', 'Октябрь', 'Қазан');
      case 11:
        return _pick('November', 'Ноябрь', 'Қараша');
      case 12:
        return _pick('December', 'Декабрь', 'Желтоқсан');
      default:
        return '';
    }
  }
  String get analyticsOosTab => _pick('Out of Stock', 'Простой', 'Бос тұру');
  String get outOfStockNowLabel =>
      _pick('Out of Stock Now', 'Сейчас нет в наличии', 'Қазір қоймада жоқ');
  String get estimatedLostRevLabel => _pick(
        'Est. Lost Revenue',
        'Упущенная выручка',
        'Жоғалған түсім (болжам)',
      );
  String get outOfStockHeader => _pick(
        'Out-of-Stock Idle Days',
        'Дни простоя без остатка',
        'Қалдықсыз бос тұрған күндер',
      );
  String get noOutOfStockMsg => _pick(
        'No out-of-stock idle periods recorded.',
        'Простоев без остатка пока нет.',
        'Қалдықсыз бос тұру тіркелмеген.',
      );
  String daysShort(int days) => _pick('${days}d', '$days дн.', '$days күн');
  String oosSummaryLine(int currentDays, int totalDays) => currentDays > 0
      ? _pick(
          'Out of stock: ${currentDays}d now • ${totalDays}d total',
          'Без остатка: сейчас $currentDays дн. • всего $totalDays дн.',
          'Қалдықсыз: қазір $currentDays күн • барлығы $totalDays күн',
        )
      : _pick(
          'Past out-of-stock total: ${totalDays}d',
          'Всего без остатка ранее: $totalDays дн.',
          'Бұрын қалдықсыз тұрғаны: $totalDays күн',
        );
  String oosTotalIdleShort(int days) =>
      _pick('Total idle: ${days}d', 'Всего простой: $days дн.', 'Барлығы: $days күн');
  String oosEstLossLine(String rev, String? profit) => profit == null
      ? _pick('Est. loss: $rev', 'Потери (оценка): $rev', 'Болжамды шығын: $rev')
      : _pick(
          'Est. loss: $rev (profit $profit)',
          'Потери (оценка): $rev (прибыль $profit)',
          'Болжамды шығын: $rev (пайда $profit)',
        );
  String get discountReasonLabel => _pick(
        'Discount reason (optional)',
        'Причина скидки (необязательно)',
        'Жеңілдік себебі (міндетті емес)',
      );
  String get returnReasonLabel => _pick(
        'Reason for return / defect (optional)',
        'Причина возврата / брака (необязательно)',
        'Қайтару / ақау себебі (міндетті емес)',
      );
  String get returnReasonPrefix =>
      _pick('Reason', 'Причина', 'Себебі');
  List<String> get discountReasonPresets => [
        _pick('Regular customer', 'Постоянный клиент', 'Тұрақты клиент'),
        _pick('Wholesale', 'Опт', 'Көтерме'),
        _pick('Promo / Sale', 'Акция', 'Акция'),
        _pick('Negotiated', 'Торг', 'Саудаласу'),
        _pick('Display / Minor flaw', 'Витрина / уценка', 'Витрина / арзандату'),
      ];
  List<String> get returnReasonPresets => [
        _pick('Wrong size / model', 'Не подошёл', 'Сәйкес келмеді'),
        _pick('Changed mind', 'Передумал', 'Айнып қалды'),
        _pick('Cashier mistake', 'Ошибка кассира', 'Кассир қатесі'),
        _pick('Exchange', 'Обмен', 'Айырбастау'),
      ];
  List<String> get defectReasonPresets => [
        _pick('Factory defect', 'Заводской брак', 'Зауыттық ақау'),
        _pick('Damaged', 'Повреждение', 'Зақымдалған'),
        _pick('Incomplete set', 'Некомплект', 'Толық емес'),
        _pick('Expired', 'Истёк срок', 'Мерзімі өткен'),
      ];
  String get customerSegmentTitle => _pick(
        'Customer Segment',
        'Сегмент клиента',
        'Клиент санаты',
      );
  String customerSegmentLabel(String name) {
    switch (name) {
      case 'wholesale':
        return _pick('Wholesale', 'Опт', 'Көтерме');
      case 'regular':
        return _pick('Regular', 'Постоянный', 'Тұрақты');
      default:
        return _pick('Retail', 'Розница', 'Бөлшек');
    }
  }
  String get generateBarcodeAction => _pick(
        'Generate EAN-13',
        'Сгенерировать EAN-13',
        'EAN-13 жасау',
      );
  String get barcodeLabelAction => _pick(
        'Barcode & Price Tag',
        'Штрих-код и ценник',
        'Штрих-код және баға белгісі',
      );
  String get barcodeLabelTitle => _pick(
        'Barcode & Label Print',
        'Штрих-код и печать этикеток',
        'Штрих-код және затбелгі басып шығару',
      );
  String barcodeGeneratedMsg(String code) => _pick(
        'Generated barcode: $code',
        'Сгенерирован штрих-код: $code',
        'Штрих-код жасалды: $code',
      );
  String get noBarcodeYetMsg => _pick(
        'This product has no barcode yet. Generate a unique EAN-13 below.',
        'У товара пока нет штрих-кода. Нажмите ниже, чтобы сгенерировать уникальный EAN-13.',
        'Бұл тауарда штрих-код жоқ. Төмендегі батырмамен бірегей EAN-13 жасаңыз.',
      );
  String get generateAndSaveBarcodeBtn => _pick(
        'Generate & Save EAN-13',
        'Сгенерировать и сохранить EAN-13',
        'EAN-13 жасау және сақтау',
      );
  String get labelFormatThermal => _pick(
        'Thermal 58×40 mm',
        'Этикетка 58×40 мм',
        'Затбелгі 58×40 мм',
      );
  String get labelFormatA4 => _pick(
        'A4 Sheet (24/page)',
        'Лист A4 (24 шт.)',
        'A4 парағы (24 дана)',
      );
  String get labelCountLabel => _pick(
        'Number of labels',
        'Количество наклеек',
        'Жапсырма саны',
      );
  String get showPriceOnLabel => _pick(
        'Show price',
        'Показывать цену',
        'Бағаны көрсету',
      );
  String get showShopNameOnLabel => _pick(
        'Show shop name',
        'Название магазина',
        'Дүкен атауын көрсету',
      );
  String get shareBarcodePdfBtn => _pick(
        'Export / Print PDF',
        'Сохранить / Печать PDF',
        'PDF сақтау / Басып шығару',
      );
  String get barcodeTypeSku => _pick('Unit (SKU)', 'Штука (SKU)', 'Дана (SKU)');
  String get barcodeTypePack => _pick('Pack', 'Упаковка', 'Қаптама');
  String get barcodeTypeBox => _pick('Box', 'Коробка', 'Қорап');
  String get ean13ValidBadge => _pick('EAN-13', 'EAN-13', 'EAN-13');
  String get customCodeBadge => _pick('Code 128', 'Code 128', 'Code 128');

  // Daily product advice
  String get dailyAdviceTitle => _pick(
        'Daily Product Advice',
        'Советы дня по товарам',
        'Тауарлар бойынша күн кеңесі',
      );
  String get dailyAdviceBadge => _pick(
        'Tip of the Day',
        'Совет дня',
        'Күн кеңесі',
      );
  String dailyAdviceMoreLabel(int extra) => _pick(
        '+$extra more',
        'ещё $extra',
        'тағы $extra',
      );
  String get dailyAdviceAllGoodTitle => _pick(
        'Catalog looks healthy today',
        'Сегодня с товарами всё в порядке',
        'Бүгін тауарларда мәселе жоқ',
      );
  String get dailyAdviceAllGoodBody => _pick(
        'No urgent stockouts, margin drops, or dead-stock alerts right now.',
        'Срочных простоев, падения маржи или проблемных остатков сейчас не найдено.',
        'Шұғыл таусылу, маржа төмендеуі немесе проблемалық қалдықтар табылмады.',
      );
  String get adviceSeverityUrgent => _pick('Urgent', 'Срочно', 'Шұғыл');
  String get adviceSeverityWarning => _pick('Attention', 'Внимание', 'Назар аударыңыз');
  String get adviceSeverityOpportunity =>
      _pick('Opportunity', 'Возможность', 'Мүмкіндік');
  String get adviceSeverityInfo => _pick('Tip', 'Совет', 'Кеңес');

  String adviceRestockHitTitle(String name) => _pick(
        'Restock best-seller: $name',
        'Срочно дозакажите: $name',
        'Шұғыл толықтырыңыз: $name',
      );
  String adviceRestockHitBody(int days, String lostRev) => _pick(
        'Out of stock for ${days}d. Estimated missed sales: ~$lostRev. Add to your next stock-in.',
        'Нет в наличии уже $days дн. Оценка упущенной выручки: ~$lostRev. Добавьте в приход.',
        '$days күннен бері қоймада жоқ. Жоғалған түсім болжамы: ~$lostRev. Кіріске қосыңыз.',
      );
  String adviceLowStockHitTitle(String name) => _pick(
        'Running low: $name',
        'Скоро закончится: $name',
        'Таусылуға жақын: $name',
      );
  String adviceLowStockHitBody(num stock, int estDays) => _pick(
        'Only ${_q(stock)} left (~$estDays d of sales at current pace). Order ahead to avoid stockout.',
        'Осталось ${_q(stock)} шт. (примерно на $estDays дн. продаж). Закажите заранее, чтобы не уйти в простой.',
        'Тек ${_q(stock)} дана қалды (шамамен $estDays күнге жетеді). Алдын ала тапсырыс беріңіз.',
      );
  String adviceMarginDropTitle(String name) => _pick(
        'Cost went up: $name',
        'Вырос закуп: $name',
        'Сатып алу бағасы өсті: $name',
      );
  String adviceMarginDropBody(
    String oldCost,
    String newCost,
    String marginPct,
  ) =>
      _pick(
        'Incoming cost rose from $oldCost to $newCost. Current margin is $marginPct% — review your sell price.',
        'Цена прихода выросла с $oldCost до $newCost. Текущая маржа — $marginPct%. Проверьте цену продажи.',
        'Кіріс бағасы $oldCost → $newCost болды. Қазіргі маржа — $marginPct%. Сату бағасын тексеріңіз.',
      );
  String adviceLowMarginTitle(String name) => _pick(
        'Low margin on $name',
        'Низкая маржа: $name',
        'Төмен маржа: $name',
      );
  String adviceLowMarginBody(String cost, String sell, String marginPct) =>
      _pick(
        'Cost $cost vs sell $sell ($marginPct% margin). Consider raising price or renegotiating with supplier.',
        'Закуп $cost, продажа $sell (маржа $marginPct%). Проверьте, не продаёте ли товар почти в ноль.',
        'Өзіндік құны $cost, сату бағасы $sell (маржа $marginPct%). Бағаны қайта қараңыз.',
      );
  String adviceDeadStockTitle(String name) => _pick(
        'Slow mover: $name',
        'Залежался товар: $name',
        'Өтпей тұрған тауар: $name',
      );
  String adviceDeadStockBody(num stock, String frozenAmount) => _pick(
        '${_q(stock)} in stock ($frozenAmount frozen) with 0 sales in 30 days. Try a promo discount or bundle.',
        'На складе ${_q(stock)} шт. (заморожено $frozenAmount), за 30 дней не было продаж. Сделайте акцию или комплект.',
        'Қоймада ${_q(stock)} дана ($frozenAmount тоқтап тұр), 30 күнде сатылым жоқ. Акция немесе жеңілдік жасап көріңіз.',
      );
  String advicePeakDayTitle(String weekdayName) => _pick(
        'Peak sales day ahead: $weekdayName',
        'Впереди пиковый день: $weekdayName',
        'Алда ең белсенді күн: $weekdayName',
      );
  String advicePeakDayBody(String topNames) => _pick(
        'Historically your busiest day. Double-check stock on top sellers: $topNames.',
        'По вашей статистике это самый сильный день. Проверьте наличие хитов: $topNames.',
        'Статистика бойынша бұл ең белсенді күн. Хит тауарлардың қалдығын тексеріңіз: $topNames.',
      );
  String adviceMissingBarcodeTitle(int count) => _pick(
        '$count product(s) without barcode',
        'Товаров без штрих-кода: $count',
        'Штрих-коды жоқ тауарлар: $count',
      );
  String adviceMissingBarcodeBody(String sampleName) => _pick(
        'Generate EAN-13 labels (e.g. for "$sampleName") to speed up checkout and stocktakes.',
        'Сгенерируйте EAN-13 (например, для «$sampleName»), чтобы ускорить продажи и ревизию.',
        'Сату мен түгендеуді жылдамдату үшін EAN-13 жасаңыз (мысалы, «$sampleName»).',
      );
  String get adviceUpdatePriceBtn =>
      _pick('Update Price', 'Изменить цену', 'Бағаны өзгерту');
  String get adviceOpenProductBtn =>
      _pick('Open', 'Открыть', 'Ашу');
  String get adviceGenerateBarcodeBtn =>
      _pick('Barcode', 'Штрих-код', 'Штрих-код');

  // Wholesale prices
  String get wholesalePriceLabel => _pick(
        'Wholesale Price (optional)',
        'Оптовая цена (необяз.)',
        'Көтерме баға (міндетті емес)',
      );
  String get wholesaleMinQtyLabel => _pick(
        'Wholesale from (qty)',
        'Опт от (шт.)',
        'Көтерме (данадан)',
      );
  String get wholesaleShort => _pick('Wholesale', 'Опт', 'Көтерме');
  String get wholesaleModeChip =>
      _pick('Wholesale', 'Оптовые цены', 'Көтерме баға');
  String get wholesaleAppliedBadge => _pick('Wholesale', 'Опт', 'Көтерме');
  String wholesaleFromQtyBadge(int qty) =>
      _pick('from $qty pcs', 'от $qty шт.', '$qty данадан');
  String addMoreForWholesaleBtn(num remaining, String price) => _pick(
        '+${_q(remaining)} for $price',
        '+${_q(remaining)} шт. → опт по $price',
        '+${_q(remaining)} дана → $price',
      );
  String autoWholesaleActiveBadge(int qty) => _pick(
        'Auto-wholesale (≥$qty)',
        'Авто-опт (от $qty шт.)',
        'Авто-көтерме ($qty+)',
      );

  // Monthly inventory value snapshots
  String get byCategoriesTab =>
      _pick('By Categories', 'По категориям', 'Санаттар бойынша');
  String get byMonthsTab =>
      _pick('By Months', 'По месяцам', 'Айлар бойынша');
  String get updateCurrentMonthSnapshotBtn => _pick(
        'Update This Month',
        'Обновить за этот месяц',
        'Осы айды жаңарту',
      );
  String get snapshotUpdatedMsg => _pick(
        'Monthly stock snapshot updated',
        'Снимок стоимости склада за этот месяц обновлён',
        'Осы айдың қойма құны жаңартылды',
      );
  String get noMonthlySnapshotsMsg => _pick(
        'Monthly snapshots are saved automatically once per month when you have active products.',
        'Снимки стоимости склада сохраняются автоматически раз в месяц при наличии активных товаров.',
        'Қойма құнының суреттері белсенді тауарлар болған кезде айына бір рет автоматты сақталады.',
      );
  String get snapshotAutoNote => _pick(
        'Saved automatically once a month. Tap above to refresh the current month.',
        'Сохраняется автоматически раз в месяц. Нажмите выше, чтобы обновить текущий месяц.',
        'Айына бір рет автоматты сақталады. Ағымдағы айды жаңарту үшін жоғарыдағы батырманы басыңыз.',
      );
  String snapshotCapturedLabel(String date) =>
      _pick('Captured: $date', 'Снимок: $date', 'Уақыты: $date');
  String snapshotItemsUnits(int items, num units) => _pick(
        '$items items • ${_q(units)} units',
        '$items поз. • ${_q(units)} шт.',
        '$items тауар • ${_q(units)} дана',
      );

  // Built-in feature usage statistics
  String get featureUsageBtn => _pick(
        'Feature Usage Stats',
        'Статистика функций',
        'Функциялар статистикасы',
      );
  String get featureUsageTitle => _pick(
        'Feature Usage',
        'Использование функций',
        'Функцияларды пайдалану',
      );
  String featureUsageSubtitle(int totalTaps, int usedCount, int totalCount) =>
      _pick(
        '$totalTaps taps • $usedCount/$totalCount used',
        'Нажатий: $totalTaps • используется $usedCount из $totalCount',
        'Басулар: $totalTaps • $usedCount/$totalCount қолданылды',
      );
  String get featureUsageTotalLabel =>
      _pick('Total Taps', 'Всего нажатий', 'Барлық басу');
  String get featureUsageUsedLabel =>
      _pick('Active', 'Используется', 'Қолданылады');
  String get featureUsageUnusedLabel =>
      _pick('Unused (0)', 'Не открывались', 'Ашылмаған');
  String get featureUsageFilterAll => _pick('All', 'Все', 'Барлығы');
  String get featureUsageFilterUsed =>
      _pick('Most Used', 'Частые', 'Жиі');
  String get featureUsageFilterUnused =>
      _pick('Unused', 'Нулевые', 'Нөлдік');
  String get featureUsageNeverUsed =>
      _pick('Never opened yet', 'Ещё не открывалось', 'Әлі ашылмаған');
  String featureUsageLastUsed(String date) =>
      _pick('Last: $date', 'Последний раз: $date', 'Соңғы рет: $date');
  String get featureUsageHintNote => _pick(
        'Counts are saved locally on this phone. Top features belong on the main screen; 0-count features can be moved to menus.',
        'Счётчик хранится локально на телефоне и не нагружает синхронизацию. Частые функции стоит держать на первом экране, а редкие и нулевые — убирать в меню.',
        'Санауыш тек телефонда сақталады. Жиі қолданылатындарды басты экранда қалдырып, нөлдіктерін мәзірге ауыстыруға болады.',
      );
  String get featureUsageResetTitle => _pick(
        'Reset usage stats?',
        'Сбросить статистику?',
        'Статистиканы нөлдеу керек пе?',
      );
  String get featureUsageResetBody => _pick(
        'All local screen and button tap counters will be cleared to zero.',
        'Все локальные счётчики открытий экранов и кнопок будут обнулены.',
        'Экрандар мен батырмаларды ашу санауыштары нөлге түсіріледі.',
      );
  String get featureUsageResetDoneMsg => _pick(
        'Feature usage stats reset',
        'Статистика функций сброшена',
        'Функциялар статистикасы нөлденді',
      );
  String get featureUsageEmptyFilterMsg => _pick(
        'No features match this filter yet.',
        'По этому фильтру пока нет записей.',
        'Бұл сүзгі бойынша жазба жоқ.',
      );

  String featureUsageGroupLabel(String group) {
    switch (group) {
      case 'tabs':
        return _pick('Tab', 'Вкладка', 'Қойынды');
      case 'goods':
        return _pick('Goods', 'Склад', 'Қойма');
      case 'pos':
        return _pick('Sell', 'Касса', 'Касса');
      case 'sales':
        return _pick('Sales', 'Продажи', 'Сатылымдар');
      case 'expenses':
        return _pick('Expenses', 'Расходы', 'Шығындар');
      case 'settings':
        return _pick('Settings', 'Настройки', 'Баптаулар');
      default:
        return group;
    }
  }

  String featureUsageName(String key) {
    switch (key) {
      case 'tab_goods':
        return _pick('Tab: Goods', 'Вкладка: Товары', 'Қойынды: Тауарлар');
      case 'tab_sell':
        return _pick('Tab: Sell (POS)', 'Вкладка: Продажа', 'Қойынды: Сату');
      case 'tab_sales':
        return _pick('Tab: Sales', 'Вкладка: Продажи', 'Қойынды: Сатылымдар');
      case 'tab_expenses':
        return _pick('Tab: Expenses', 'Вкладка: Расходы', 'Қойынды: Шығындар');
      case 'barcode_scan':
        return _pick('Barcode Scanner', 'Сканер штрих-кода', 'Штрих-код сканері');
      case 'barcode_label':
        return _pick('Barcode & Labels', 'Штрих-код и этикетки', 'Штрих-код және затбелгі');
      case 'stock_in':
        return _pick('Stock-In', 'Приход товара', 'Тауар кірісі');
      case 'stocktake':
        return _pick('Stocktake', 'Ревизия склада', 'Қойманы түгендеу');
      case 'product_add':
        return _pick('Add Product', 'Добавление товара', 'Тауар қосу');
      case 'product_edit':
        return _pick('Edit Product', 'Редактирование товара', 'Тауарды өңдеу');
      case 'change_history':
        return _pick('Change History', 'История изменений', 'Өзгерістер тарихы');
      case 'daily_advice':
        return _pick('Daily Advice', 'Советы дня', 'Күн кеңестері');
      case 'stock_value':
        return _pick('Stock Value & Snapshots', 'Сумма склада и снимки', 'Қор құны және суреттер');
      case 'duplicate_check':
        return _pick('Duplicate Check', 'Проверка дубликатов', 'Дубликаттарды тексеру');
      case 'sale_complete':
        return _pick('Complete Sale', 'Оформление продажи', 'Сатуды аяқтау');
      case 'hold_sale':
        return _pick('Hold / Held Sales', 'Отложенные чеки', 'Кейінге қалдырылған чектер');
      case 'wholesale_mode':
        return _pick('Wholesale Mode', 'Оптовые цены', 'Көтерме баға режимі');
      case 'return_exchange':
        return _pick('Return / Exchange', 'Возврат / Обмен', 'Қайтару / Айырбастау');
      case 'debtors':
        return _pick('Debtors', 'Должники', 'Борышкерлер');
      case 'customers':
        return _pick('Customers', 'Клиенты', 'Клиенттер');
      case 'analytics':
        return _pick('Top Goods & Analytics', 'Аналитика / Топ-товары', 'Талдау / Үздік тауарлар');
      case 'invoices_history':
        return _pick('Invoices History', 'История накладных', 'Жүкқұжаттар тарихы');
      case 'defect_report':
        return _pick('Defect Report', 'Отчёт по браку', 'Ақау есебі');
      case 'expense_add':
        return _pick('Add Expense', 'Добавление расхода', 'Шығын қосу');
      case 'incoming_prices':
        return _pick('Incoming Prices', 'Анализ цен прихода', 'Кіріс бағаларын талдау');
      case 'google_sheets':
        return _pick('Google Sheets Sync', 'Google Таблица', 'Google Кесте');
      case 'backup_export':
        return _pick('Backup & Export', 'Экспорт и бэкап', 'Экспорт және бэкап');
      case 'archive_trash':
        return _pick('Archive & Trash', 'Архив и корзина', 'Мұрағат және себет');
      default:
        return key;
    }
  }

  // PIN recovery
  String get forgotPinBtn => _pick(
        'Forgot PIN?',
        'Забыли PIN-код?',
        'PIN-кодты ұмыттыңыз ба?',
      );
  String get resetPinTitle => _pick(
        'Reset Owner PIN',
        'Сброс PIN-кода',
        'PIN-кодты қалпына келтіру',
      );
  String get resetPinConfirmBody => _pick(
        'Verify your identity using your phone\'s fingerprint, face, or screen lock to reset the Owner PIN and unlock Owner Mode.',
        'Подтвердите личность отпечатком, лицом или паролем экрана телефона, чтобы сбросить PIN-код и открыть режим владельца.',
        'PIN-кодты өшіріп, иесі режимін ашу үшін телефонның саусақ ізі, бет немесе экран құпия сөзімен растаңыз.',
      );
  String get resetPinPromptReason => _pick(
        'Verify your identity to reset the Owner PIN',
        'Подтвердите личность для сброса PIN-кода владельца',
        'Иесінің PIN-кодын өшіру үшін жеке басыңызды растаңыз',
      );
  String get pinResetSuccessMsg => _pick(
        'PIN reset. Owner Mode unlocked.',
        'PIN-код сброшен. Режим владельца открыт.',
        'PIN-код өшірілді. Иесі режимі ашылды.',
      );

  // Daily advice export, copy & gestures
  String get shareAdviceBtn => _pick(
        'Share Advice',
        'Поделиться советом',
        'Кеңеспен бөлісу',
      );
  String get exportAllAdvicesBtn => _pick(
        'Export Advice',
        'Выгрузить советы',
        'Кеңестерді жүктеу',
      );
  String get shareAdviceTextAction => _pick(
        'Share as Text',
        'Отправить текстом',
        'Мәтін ретінде жіберу',
      );
  String get exportAdviceFileAction => _pick(
        'Export File (.txt)',
        'Выгрузить файл (.txt)',
        'Файл ретінде жүктеу (.txt)',
      );
  String get copyAllAdvicesAction => _pick(
        'Copy All',
        'Копировать все',
        'Барлығын көшіру',
      );
  String get adviceCopiedMsg => _pick(
        'Advice copied',
        'Совет скопирован',
        'Кеңес көшірілді',
      );
  String get noOtherAdviceMsg => _pick(
        'No other advice right now',
        'Других советов сейчас нет',
        'Қазір басқа кеңес жоқ',
      );
  String get adviceGesturesHint => _pick(
        'Hold to copy • Double-tap for another tip',
        'Удержание — копировать • 2× нажатие — новый совет',
        'Ұстап тұру — көшіру • 2× басу — жаңа кеңес',
      );
  String get nextAdviceBtn => _pick(
        'Next Advice',
        'Другой совет',
        'Басқа кеңес',
      );

  // WhatsApp debtor reminder
  String get remindWhatsAppBtn => _pick(
        'Remind in WhatsApp',
        'Напомнить в WhatsApp',
        'WhatsApp-қа еске салу',
      );
  String get debtReminderSubject => _pick(
        'Payment Reminder',
        'Напоминание об оплате',
        'Төлем туралы еске салу',
      );
  String debtReminderMessage({
    required String customerName,
    required String amount,
    String? dueDate,
    bool isOverdue = false,
    String shopName = '',
  }) {
    final cleanName = customerName.trim();
    final hasName = cleanName.isNotEmpty && cleanName.toLowerCase() != 'unknown';
    final cleanShop = shopName.trim();
    final dueEn = dueDate != null
        ? (isOverdue ? ' (overdue since $dueDate)' : ' (due date: $dueDate)')
        : '';
    final dueRu = dueDate != null
        ? (isOverdue
            ? ' (просрочено с $dueDate)'
            : ' (срок оплаты: $dueDate)')
        : '';
    final dueKk = dueDate != null
        ? (isOverdue
            ? ' ($dueDate мерзімі өтіп кеткен)'
            : ' (төлем мерзімі: $dueDate)')
        : '';
    final shopEn = cleanShop.isNotEmpty ? ' at $cleanShop' : '';
    final shopRu = cleanShop.isNotEmpty ? ' в магазине «$cleanShop»' : '';
    final shopKk = cleanShop.isNotEmpty ? ' «$cleanShop» дүкеніндегі' : '';

    return _pick(
      '${hasName ? 'Hello, $cleanName!' : 'Hello!'} This is a friendly reminder regarding your remaining balance of $amount$shopEn$dueEn. Thank you!',
      '${hasName ? 'Здравствуйте, $cleanName!' : 'Здравствуйте!'} Напоминаем об остатке оплаты$shopRu на сумму $amount$dueRu. Будем благодарны за оплату. Спасибо!',
      '${hasName ? 'Сәлеметсіз бе, $cleanName!' : 'Сәлеметсіз бе!'} $shopKk $amount сомасындағы қалған төлем туралы еске саламыз$dueKk. Төлем жасағаныңыз үшін рахмет!',
    );
  }

  // Missing regular/wholesale customer advice
  String adviceMissingCustomerTitle(String name) => _pick(
        'Check in with $name',
        'Пропал постоянный клиент: $name',
        'Тұрақты клиент көрінбей кетті: $name',
      );
  String adviceMissingCustomerBody(
    int daysSince,
    int usualDays,
    String totalSpent,
  ) =>
      _pick(
        'Usually buys every ~$usualDays d, but no orders for $daysSince d (total: $totalSpent). Message them on WhatsApp.',
        'Обычно покупает раз в ~$usualDays дн., но не заходил уже $daysSince дн. (всего покупок: $totalSpent). Напишите в WhatsApp.',
        'Әдетте шамамен $usualDays күн сайын келетін, бірақ $daysSince күннен бері тапсырыс жоқ (барлығы: $totalSpent). WhatsApp-қа жазыңыз.',
      );
  String get adviceWriteWhatsAppBtn => _pick(
        'Write in WhatsApp',
        'Написать в WhatsApp',
        'WhatsApp-қа жазу',
      );
  String missingCustomerWhatsAppMsg({
    required String customerName,
    String shopName = '',
  }) {
    final cleanName = customerName.trim();
    final cleanShop = shopName.trim();
    final shopEn = cleanShop.isNotEmpty ? ' at $cleanShop' : '';
    final shopRu = cleanShop.isNotEmpty ? ' в «$cleanShop»' : '';
    final shopKk = cleanShop.isNotEmpty ? '«$cleanShop» дүкеніне ' : '';
    return _pick(
      'Hello, $cleanName! We haven\'t seen you in a while$shopEn. Let us know if you need anything or would like our latest prices!',
      'Здравствуйте, $cleanName! Давно вас не было видно$shopRu. Если что-то нужно или прислать актуальные цены и новинки — напишите нам!',
      'Сәлеметсіз бе, $cleanName! $shopKkкөптен бері көрінбей кеттіңіз. Егер тауар керек болса немесе жаңа бағалар тізімін жіберу керек болса, хабарласыңыз!',
    );
  }

  // Shift Closing
  String get shiftClosingBtn => _pick(
        'Close Shift',
        'Закрытие смены',
        'Ауысымды жабу',
      );
  String get shiftClosingTitle => _pick(
        'Shift Closing',
        'Закрытие смены',
        'Ауысымды жабу',
      );
  String get shiftPaymentBreakdownHeader => _pick(
        'By Payment Method',
        'По способам оплаты',
        'Төлем тәсілдері бойынша',
      );
  String get shiftCashReconciliationHeader => _pick(
        'Cash Drawer Check',
        'Сверка наличных в кассе',
        'Кассадағы қолма-қол ақшаны тексеру',
      );
  String get shiftOpeningFloatLabel => _pick(
        'Opening float (optional)',
        'Размен на начало смены (необяз.)',
        'Ауысым басындағы қалдық (міндетті емес)',
      );
  String get shiftExpectedCashLabel => _pick(
        'Expected in drawer',
        'Ожидается в кассе',
        'Кассада күтілетін сома',
      );
  String get shiftCashFormulaHint => _pick(
        'Opening float + Cash sales − Today expenses',
        'Размен + Наличные продажи − Расходы за день',
        'Бастапқы қалдық + Қолма-қол сатылым − Бүгінгі шығындар',
      );
  String get shiftActualCashLabel => _pick(
        'Actual cash in drawer',
        'Фактически наличных в кассе',
        'Кассадағы нақты қолма-қол ақша',
      );
  String get shiftActualCashHint => _pick(
        'Count cash and enter amount',
        'Пересчитайте и введите сумму',
        'Санап, соманы енгізіңіз',
      );
  String shiftSurplusLabel(String amount) => _pick(
        'Surplus: +$amount',
        'Излишек: +$amount',
        'Артық: +$amount',
      );
  String shiftShortageLabel(String amount) => _pick(
        'Shortage: -$amount',
        'Недостача: -$amount',
        'Жетіспеушілік: -$amount',
      );
  String get shiftExactMatchLabel => _pick(
        'Exact match (0)',
        'Сошлось ровно (0)',
        'Дәл сәйкес келді (0)',
      );
  String get shiftCashierHiddenNote => _pick(
        'Cashier Mode: cost & profit are hidden in the report',
        'Режим продавца: закупка и прибыль скрыты в отчёте',
        'Сатушы режимі: өзіндік құн мен пайда есепте көрсетілмейді',
      );
  String get shiftNoSalesTodayNote => _pick(
        'No sales recorded today yet.',
        'За сегодня продаж пока нет.',
        'Бүгінге сатылымдар әлі жоқ.',
      );

  // Cashier receipt immutability
  String get cashierReceiptImmutableNote => _pick(
        'Cashier Mode: deleting receipts is disabled without Owner PIN. Only Return / Exchange is allowed.',
        'В режиме продавца удаление чеков запрещено без PIN-кода владельца — доступен только «Возврат / Обмен».',
        'Сатушы режимінде иесінің PIN-кодынсыз чектерді жоюға тыйым салынған — тек «Қайтару / Айырбастау» қолжетімді.',
      );
  String get ownerPinRequiredTitle => _pick(
        'Owner PIN Required',
        'Требуется PIN-код владельца',
        'Иесінің PIN-коды қажет',
      );
  String get ownerPinNotSetForDeleteMsg => _pick(
        'Owner PIN is not set. Unlock Owner Mode in Settings to delete or archive receipts.',
        'PIN-код владельца не задан. Перейдите в режим владельца в Настройках, чтобы удалить или архивировать чек.',
        'Иесінің PIN-коды орнатылмаған. Чекті жою немесе мұрағаттау үшін Баптауларда иесі режиміне өтіңіз.',
      );

  // Split data vs settings restore
  String get restoreScopeTitle => _pick(
        'What to restore?',
        'Что восстановить?',
        'Нені қалпына келтіру керек?',
      );
  String get restoreDataOnlyOption => _pick(
        'Goods, sales & debts only',
        'Только товары, продажи и долги',
        'Тек тауарлар, сатылымдар және қарыздар',
      );
  String get restoreDataOnlyHint => _pick(
        'Keeps your current app settings, language, currency, and PIN on this phone',
        'Сохранит текущие настройки, язык, валюту и PIN-код на этом телефоне',
        'Осы телефондағы ағымдағы баптауларды, тілді, валютаны және PIN-кодты сақтайды',
      );
  String get restoreAllWithSettingsOption => _pick(
        'Everything including settings & PIN',
        'Всё вместе с настройками и PIN-кодом',
        'Баптаулар және PIN-кодпен бірге бәрін',
      );
  String get restoreAllWithSettingsHint => _pick(
        'Also replaces shop info, language, currency, mode, and Owner PIN',
        'Заменит также данные магазина, язык, валюту, режим и PIN-код владельца',
        'Дүкен деректерін, тілді, валютаны, режимді және иесінің PIN-кодын да алмастырады',
      );

  // External backup reminder (Google Drive / Telegram)
  String get saveBackupOutsidePhoneBtn => _pick(
        'Save Backup Outside Phone',
        'Сохранить копию вне телефона',
        'Көшірмені телефоннан тыс сақтау',
      );
  String get externalBackupReminderTitle => _pick(
        'Back Up Outside This Phone',
        'Сохраните копию вне телефона',
        'Көшірмені телефоннан тыс сақтаңыз',
      );
  String get externalBackupReminderBody => _pick(
        'If this phone is lost or the app is uninstalled, local data is erased. Send a .json copy to Google Drive or Telegram Saved Messages so your shop data is always safe.',
        'При удалении приложения или поломке телефона внутренняя база стирается. Отправьте .json-копию в Google Диск или Telegram «Избранное», чтобы данные всегда были в безопасности.',
        'Қолданбаны өшіргенде немесе телефон бұзылғанда ішкі дерекқор жойылады. Деректерді сақтау үшін .json көшірмесін Google Drive немесе Telegram-дағы «Сақталғандар» бөліміне жіберіңіз.',
      );
  String lastExternalBackupLabel(String date) => _pick(
        'Last external backup: $date',
        'Последняя выгрузка вне телефона: $date',
        'Соңғы сыртқы көшірме: $date',
      );
  String get externalBackupOpenedMsg => _pick(
        'Choose Google Drive or Telegram to save your backup',
        'Выберите Google Диск или Telegram «Избранное» для сохранения копии',
        'Көшірмені сақтау үшін Google Drive немесе Telegram-ды таңдаңыз',
      );

  // Cloud backup shrink / rollback protection
  String get cloudBackupShrinkWarningTitle => _pick(
        'Cloud Backup Blocked',
        'Автобэкап заблокирован',
        'Автобэкап бұғатталды',
      );
  String cloudBackupShrinkBlockedMsg(
    int prevProducts,
    int curProducts,
    int prevSales,
    int curSales,
  ) =>
      _pick(
        'Sharp drop detected before uploading _Backup (goods: $prevProducts → $curProducts, sales: $prevSales → $curSales). Auto-overwrite was blocked to protect your cloud data.',
        'Обнаружено резкое падение количества перед отправкой _Backup (товары: $prevProducts → $curProducts, продажи: $prevSales → $curSales). Авто-перезапись заблокирована, чтобы не потерять облачную копию.',
        '_Backup жіберу алдында деректер саны күрт азайғаны анықталды (тауарлар: $prevProducts → $curProducts, сатылымдар: $prevSales → $curSales). Бұлттық көшірмені қорғау үшін авто-қайта жазу бұғатталды.',
      );
  String get cloudBackupOverrideBtn => _pick(
        'Overwrite _Backup Anyway',
        'Всё равно перезаписать _Backup',
        'Бәрібір _Backup-ты қайта жазу',
      );
  String get pendingSyncStatus => _pick(
        'Pending changes waiting to sync',
        'Есть неотправленные изменения (ждут сети)',
        'Жіберілмеген өзгерістер бар (желіні күтуде)',
      );
  String get deleteForeverConfirmTitle => _pick(
        'Delete forever?',
        'Удалить навсегда?',
        'Біржола жою керек пе?',
      );
  String deleteForeverItemBody(String name) => _pick(
        'Permanently delete "$name"? This cannot be undone.',
        'Удалить «$name» навсегда? Это действие нельзя отменить.',
        '«$name» біржола жойылсын ба? Бұл әрекетті қайтару мүмкін емес.',
      );
  String deleteForeverSelectedBody(int count) => _pick(
        'Permanently delete $count selected item(s)? This cannot be undone.',
        'Удалить навсегда выбранные позиции ($count)? Это действие нельзя отменить.',
        'Таңдалған $count элементті біржола жою керек пе? Бұл әрекетті қайтару мүмкін емес.',
      );
  String get enterOwnerPinToConfirm => _pick(
        'Enter Owner PIN to confirm',
        'Введите PIN-код владельца',
        'Растау үшін иесінің PIN-кодын енгізіңіз',
      );
  String remoteCatalogOverwriteBlockedMsg(
    int remoteProducts,
    int localProducts,
  ) =>
      _pick(
        'Google Sheet already has $remoteProducts products, while this phone only has $localProducts. Upload was blocked to avoid wiping your cloud catalog. Restore from Google Sheets or confirm overwrite.',
        'В Google Таблице уже есть $remoteProducts товаров, а на этом телефоне только $localProducts. Выгрузка заблокирована, чтобы не затереть облачный каталог. Восстановите базу из таблицы или подтвердите перезапись.',
        'Google Кестеде $remoteProducts тауар бар, ал бұл телефонда тек $localProducts тауар. Бұлттық каталогты өшіріп алмау үшін жүктеу бұғатталды. Кестеден қалпына келтіріңіз немесе қайта жазуды растаңыз.',
      );
  String get rollbackLastRestoreBtn => _pick(
        'Rollback Last Restore',
        'Откатить последнее восстановление',
        'Соңғы қалпына келтіруді қайтару',
      );
  String get rollbackRestoreTitle => _pick(
        'Rollback to pre-restore state?',
        'Откатить восстановление?',
        'Қалпына келтіруді болдырмау керек пе?',
      );
  String rollbackRestoreBody(String? savedAt) => _pick(
        'Restore the automatic snapshot saved right before the last restore${savedAt != null && savedAt.isNotEmpty ? ' ($savedAt)' : ''}?',
        'Вернуть автоматический слепок базы, сохранённый прямо перед последним восстановлением${savedAt != null && savedAt.isNotEmpty ? ' ($savedAt)' : ''}?',
        'Соңғы қалпына келтіру алдында автоматты сақталған дерекқор күйіне${savedAt != null && savedAt.isNotEmpty ? ' ($savedAt)' : ''} оралу керек пе?',
      );
  String get rollbackRestoredMsg => _pick(
        'Rolled back to pre-restore snapshot',
        'База откатана к состоянию до восстановления',
        'Дерекқор қалпына келтіруге дейінгі күйге оралды',
      );
  String get noPreRestoreBackupMsg => _pick(
        'No pre-restore snapshot found.',
        'Резервный слепок до восстановления не найден.',
        'Қалпына келтіруге дейінгі резервтік көшірме табылмады.',
      );
  String get preRestoreBackupSavedNote => _pick(
        'Previous data was saved automatically (you can roll back).',
        'Предыдущие данные сохранены автоматически (можно откатить).',
        'Алдыңғы деректер автоматты сақталды (кері қайтаруға болады).',
      );

  // Year-End Archiving
  String get yearEndArchiveBtn => _pick(
        'Year-End Archive (Close Year)',
        'Закрытие года (архивация)',
        'Жылды жабу (мұрағаттау)',
      );
  String get yearEndArchiveTitle => _pick(
        'Year-End Archive',
        'Закрытие года',
        'Жылды жабу',
      );
  String get yearEndArchiveDesc => _pick(
        'Export past-year sales and stock-in invoices to CSV/JSON files, then compress them to monthly totals so the app stays fast for years.',
        'Выгрузите продажи и накладные за прошлый год в отдельные файлы CSV/JSON и сожмите их до месячных итогов, чтобы база оставалась быстрой.',
        'Өткен жылғы сатылымдар мен жүкқұжаттарды CSV/JSON файлдарына жүктеп, қолданба жылдам жұмыс істеуі үшін айлық қорытындыға сығыңыз.',
      );
  String get noPastYearsToArchiveMsg => _pick(
        'No past-year sales or invoices to archive yet.',
        'Нет продаж или накладных за прошлые годы для архивации.',
        'Мұрағаттау үшін өткен жылдардағы сатылымдар немесе жүкқұжаттар жоқ.',
      );
  String yearSummaryLine(int year, int salesCount, int stockInsCount) => _pick(
        '$year: $salesCount sale(s), $stockInsCount invoice(s)',
        '$year г.: $salesCount прод., $stockInsCount накл.',
        '$year ж.: $salesCount сат., $stockInsCount жүкқ.',
      );
  String get exportArchiveOnlyBtn => _pick(
        'Export Archive (JSON + CSV)',
        'Только выгрузить (JSON + CSV)',
        'Тек жүктеу (JSON + CSV)',
      );
  String get exportAndCompressYearBtn => _pick(
        'Export & Compress to Monthly',
        'Выгрузить и сжать в итоги',
        'Жүктеу және айлыққа сығу',
      );
  String yearCompressedMsg(int year, int salesCount, int stockInsCount) =>
      _pick(
        'Year $year archived: compressed $salesCount sales and $stockInsCount invoices into monthly totals.',
        'Год $year закрыт: сжато $salesCount продаж и $stockInsCount накладных в месячные итоги.',
        '$year жыл жабылды: $salesCount сатылым және $stockInsCount жүкқұжат айлық қорытындыға сығылды.',
      );
  String unpaidDebtsKeptNote(int count) => _pick(
        '$count unpaid debt receipt(s) kept active.',
        'Непогашенных долгов оставлено без сжатия: $count.',
        'Өтелмеген қарыздар сығылмай сақталды: $count.',
      );
  String barcodeSelfConflictError(String fieldA, String fieldB, String code) =>
      _pick(
        'Barcode "$code" cannot be the same in "$fieldA" and "$fieldB".',
        'Штрихкод «$code» не может совпадать у полей «$fieldA» и «$fieldB».',
        '«$code» штрих-коды «$fieldA» және «$fieldB» өрістерінде бірдей болмауы керек.',
      );
  String get catalogHealthBtn => _pick(
        'Catalog Health Check',
        'Здоровье каталога',
        'Каталог денсаулығы',
      );
  String catalogHealthIssuesCount(int count) => _pick(
        'Catalog Health ($count issues)',
        'Здоровье каталога ($count пробл.)',
        'Каталог денсаулығы ($count мәселе)',
      );
  String get catalogHealthOkMsg => _pick(
        'Catalog looks healthy! No anomalies found.',
        'Аномалий в каталоге не найдено!',
        'Каталогта қате табылмады!',
      );
  String get healthEmptyName => _pick(
        'Empty name',
        'Пустое название',
        'Атауы бос',
      );
  String get healthZeroPrice => _pick(
        'Zero sell price',
        'Нулевая цена продажи',
        'Сату бағасы нөл',
      );
  String get healthSellBelowCost => _pick(
        'Sell price below cost',
        'Цена продажи ниже закупа',
        'Сату бағасы өзіндік құннан төмен',
      );
  String get healthDuplicateBarcode => _pick(
        'Duplicate barcode',
        'Одинаковый штрихкод',
        'Бірдей штрих-код',
      );
  String get healthNegativeStock => _pick(
        'Negative stock',
        'Зависший минус остатка',
        'Минус қалдық',
      );
  String importHealthWarningTitle(int count) => _pick(
        'Data anomalies in import: $count',
        'Найдены аномалии в импорте: $count',
        'Импортта қателер табылды: $count',
      );
  String get dailyLocalBackupsBtn => _pick(
        'Daily Local Backups (7 days)',
        'Автобэкапы по дням (7 копий)',
        'Күнделікті жергілікті бэкап (7 күн)',
      );
  String get dailyLocalBackupsTitle => _pick(
        'Daily Local Backups',
        'Локальные копии по дням',
        'Күнделікті жергілікті көшірмелер',
      );
  String get dailyLocalBackupsDesc => _pick(
        'Saved automatically once a day as compressed .json.gz files on this phone (last 7 days). Works offline.',
        'Сохраняются автоматически раз в сутки в сжатом виде (.json.gz) в памяти телефона (последние 7 дней). Работает без интернета.',
        'Күніне бір рет телефон жадында сығылған (.json.gz) түрде автоматты сақталады (соңғы 7 күн). Интернетсіз жұмыс істейді.',
      );
  String get noDailyLocalBackupsMsg => _pick(
        'No daily local backups yet.',
        'Ещё нет сохранённых ежедневных копий.',
        'Сақталған күнделікті көшірмелер жоқ.',
      );
  String get saveDailyBackupNowBtn => _pick(
        'Save Today\'s Copy Now',
        'Сохранить копию за сегодня',
        'Бүгінгі көшірмені сақтау',
      );
  String get dailyBackupSavedMsg => _pick(
        'Daily local backup saved',
        'Локальная копия за сегодня сохранена',
        'Бүгінгі жергілікті көшірме сақталды',
      );
  String get cloudNewerWarningTitle => _pick(
        'Cloud Copy Is Newer',
        'В облаке более свежая копия',
        'Бұлттағы көшірме жаңарақ',
      );
  String cloudNewerOverwriteBlockedMsg(String cloudDate, String localDate) =>
      _pick(
        'Google Sheets has a newer update ($cloudDate) than this phone\'s last sync ($localDate). Uploading now could overwrite recent sales or price edits from another device or computer.',
        'Облачная копия в Google Таблице новее ($cloudDate), чем последняя синхронизация этого телефона ($localDate). Полная выгрузка может затереть свежие продажи или цены с другого устройства или компьютера.',
        'Google Кестедегі көшірме ($cloudDate) осы телефонның соңғы синхрондауынан ($localDate) жаңарақ. Қазір жүктеу басқа құрылғыдағы немесе компьютердегі жаңа сатылымдар мен бағаларды өшіруі мүмкін.',
      );
  String get localNewerWarningTitle => _pick(
        'Phone Data Is Newer',
        'На телефоне более свежие данные',
        'Телефондағы деректер жаңарақ',
      );
  String localNewerRestoreWarningMsg(String localDate, String cloudDate) =>
      _pick(
        'This phone has newer changes ($localDate) than the cloud backup ($cloudDate). Restoring from Google Sheets will roll back your latest sales or price edits.',
        'На этом телефоне есть более свежие изменения ($localDate), чем в облачной копии ($cloudDate). Восстановление из Google Таблицы откатит последние продажи или цены.',
        'Бұл телефонда бұлттық көшірмеден ($cloudDate) жаңарақ өзгерістер ($localDate) бар. Google Кестеден қалпына келтіру соңғы сатылымдар мен бағаларды кері қайтарады.',
      );
  String get overwriteCloudAnywayBtn => _pick(
        'Overwrite Cloud Anyway',
        'Всё равно перезаписать облако',
        'Бәрібір бұлтты қайта жазу',
      );
  String get restoreOlderCloudAnywayBtn => _pick(
        'Restore Older Copy Anyway',
        'Всё равно восстановить',
        'Бәрібір қалпына келтіру',
      );
  String get neverSyncedLabel => _pick(
        'never synced',
        'ещё не синхронизировался',
        'әлі синхрондалмаған',
      );
  String trashAutoPurgeNotice(int days) => _pick(
        'Items in trash are automatically deleted after $days days.',
        'Элементы в корзине автоматически удаляются через $days дн.',
        'Себеттегі жазбалар $days күннен кейін автоматты түрде жойылады.',
      );
  String get trashAutoPurgeOffNotice => _pick(
        'Trash auto-cleanup is off.',
        'Автоочистка корзины отключена.',
        'Себетті автотазалау өшірулі.',
      );
  String get trashRetentionLabel => _pick(
        'Auto-clean',
        'Автоочистка',
        'Автотазалау',
      );
  String trashRetentionDaysOption(int days) => _pick(
        '$days days',
        '$days дн.',
        '$days күн',
      );
  String get trashRetentionOffOption => _pick(
        'Keep forever',
        'Отключена',
        'Өшірулі',
      );
  String autoPurgeInDays(int days) => _pick(
        'Auto-delete in ${days}d',
        'Удалится через $days дн.',
        '$days күннен кейін жойылады',
      );
  String get attachBarcodeToExistingBtn => _pick(
        'Link to product',
        'Привязать к товару',
        'Тауарға байлау',
      );
  String get attachBarcodeTitle => _pick(
        'Link barcode to existing product',
        'Привязать штрихкод к товару',
        'Штрихкодты бар тауарға байлау',
      );
  String attachBarcodeSubtitle(String code) => _pick(
        'Barcode: $code',
        'Штрихкод: $code',
        'Штрихкод: $code',
      );
  String barcodeLinkedMsg(String code, String productName) => _pick(
        'Barcode $code linked to "$productName"',
        'Штрихкод $code привязан к «$productName»',
        '$code штрихкоды «$productName» тауарына байланды',
      );
  String barcodeAlreadyLinkedMsg(String productName) => _pick(
        'Barcode is already linked to "$productName"',
        'Штрихкод уже привязан к «$productName»',
        'Бұл штрихкод «$productName» тауарына бұрыннан байланған',
      );
  String get extraBarcodesLabel => _pick(
        'Additional barcodes',
        'Доп. штрихкоды (партии)',
        'Қосымша штрихкодтар',
      );
  String get createNewProductBtn => _pick(
        'Create new product',
        'Создать новый товар',
        'Жаңа тауар қосу',
      );
  String get sendEstimateBtn => _pick(
        'Send estimate',
        'Отправить расчёт',
        'Есептемені жіберу',
      );
  String get estimateTitle => _pick(
        'Price Estimate',
        'Предварительный расчёт (смета)',
        'Алдын ала есептеу (смета)',
      );
  String get estimateDisclaimer => _pick(
        'Preliminary estimate — stock is not reserved.',
        'Предварительный расчёт — товар не списан и не забронирован.',
        'Алдын ала есептеу — тауар есептен шығарылмаған.',
      );
  String get estimateTotalLabel => _pick(
        'Estimate total',
        'Итого по смете',
        'Смета бойынша барлығы',
      );
  String estimateItemsUnitsSummary(int items, num units) => _pick(
        '$items items (${_q(units)} pcs)',
        'Позиций: $items (${_q(units)} шт.)',
        'Тауарлар: $items (${_q(units)} дана)',
      );
  String get selectSellerShort => _pick(
        'Seller',
        'Продавец',
        'Сатушы',
      );
  String get selectSellerTitle => _pick(
        'Select seller in shift',
        'Выбор продавца в смене',
        'Ауысымдағы сатушыны таңдау',
      );
  String get noSellerOption => _pick(
        'Not specified',
        'Без имени',
        'Аты көрсетілмеген',
      );
  String get addSellerHint => _pick(
        'New seller name',
        'Имя нового продавца',
        'Жаңа сатушының аты',
      );
  String get addSellerBtn => _pick(
        'Add',
        'Добавить',
        'Қосу',
      );
  String sellerLabel(String name) => _pick(
        'Seller: $name',
        'Продавец: $name',
        'Сатушы: $name',
      );
  String get shiftBySellerHeader => _pick(
        'By seller',
        'По продавцам',
        'Сатушылар бойынша',
      );
  String get unspecifiedSellerLabel => _pick(
        'Unspecified',
        'Не указан',
        'Көрсетілмеген',
      );
  String get priceTagQueueTitle => _pick(
        'Price tags to print',
        'На печать ценников',
        'Баға белгісін басып шығару',
      );
  String priceTagQueueBanner(int count) => _pick(
        'Price changed — update price tags ($count)',
        'Цена изменилась — обновите ценники ($count)',
        'Баға өзгерді — баға белгісін жаңартыңыз ($count)',
      );
  String get markPrintedAction => _pick(
        'Printed',
        'Напечатано',
        'Басылды',
      );
  String get clearPriceTagQueueBtn => _pick(
        'Clear list',
        'Очистить список',
        'Тізімді тазарту',
      );
  String get priceTagQueueEmpty => _pick(
        'Price tag print list is empty',
        'Список на печать ценников пуст',
        'Баға белгілерінің тізімі бос',
      );
  String addedToPriceTagQueueNotice(int count) => _pick(
        'Added to price tag print list: $count',
        'Добавлено на печать ценников: $count',
        'Баға белгісін басу тізіміне қосылды: $count',
      );
  String get belowCostPriceWarning => _pick(
        'Price is below cost!',
        'Цена ниже закупочной!',
        'Баға өзіндік құнынан төмен!',
      );
  String belowCostSaleWarning(String loss) => _pick(
        'Sale is below cost (loss: $loss).',
        'Продажа в минус (убыток: $loss).',
        'Шығынмен сату (шығын: $loss).',
      );
  String get belowCostPinRequiredNote => _pick(
        'Owner PIN is required in seller mode to complete this sale.',
        'В режиме продавца нужен PIN владельца для проведения такого чека.',
        'Сатушы режимінде мұндай чекті өткізу үшін иесінің PIN-коды қажет.',
      );
  String get belowCostPinDialogTitle => _pick(
        'Confirm sale below cost',
        'Продажа ниже закупки',
        'Өзіндік құнынан төмен сату',
      );
  String get confirmBelowCostAction => _pick(
        'Complete sale',
        'Провести чек',
        'Чекті өткізу',
      );
  String get undoAction => _pick(
        'Undo',
        'Отменить',
        'Болдырмау',
      );
  String get cartClearedMsg => _pick(
        'Cart cleared',
        'Корзина очищена',
        'Себет тазартылды',
      );
  String showMoreCountBtn(int remaining) => _pick(
        'Show more ($remaining left)',
        'Показать ещё (осталось $remaining)',
        'Тағы көрсету ($remaining қалды)',
      );
  String get hideSummaryHeaderTooltip => _pick(
        'Hide summary cards',
        'Скрыть сводку и советы',
        'Жиынтықты жасыру',
      );
  String get showSummaryHeaderTooltip => _pick(
        'Show summary cards',
        'Показать сводку и советы',
        'Жиынтықты көрсету',
      );
  String get purchaseOrderBtn => _pick(
        'To purchase',
        'К закупке',
        'Сатып алуға',
      );
  String get purchaseOrderTitle => _pick(
        'Supplier Purchase Order',
        'Заявка поставщику',
        'Жеткізушіге тапсырыс',
      );
  String get purchaseOrderEmpty => _pick(
        'All products are well stocked',
        'Все товары в достатке',
        'Барлық тауар жеткілікті',
      );
  String get supplierOptionalHint => _pick(
        'Supplier (optional)',
        'Поставщик (необязательно)',
        'Жеткізуші (міндетті емес)',
      );
  String get allSuppliersFilter => _pick(
        'All suppliers',
        'Все поставщики',
        'Барлық жеткізушілер',
      );
  String get supplierPhoneOptionalHint => _pick(
        'Supplier WhatsApp phone (optional)',
        'Телефон поставщика в WhatsApp (необяз.)',
        'Жеткізушінің WhatsApp нөмірі (міндетті емес)',
      );
  String get productPhotoLabel => _pick(
        'Product photo',
        'Фото товара',
        'Тауар фотосы',
      );
  String get cameraBtn => _pick(
        'Camera',
        'Камера',
        'Камера',
      );
  String get galleryBtn => _pick(
        'Gallery',
        'Галерея',
        'Галерея',
      );
  String get removePhotoBtn => _pick(
        'Remove photo',
        'Удалить фото',
        'Фотоны өшіру',
      );
  String get photoPickFailedMsg => _pick(
        'Could not load photo',
        'Не удалось загрузить фото',
        'Фотоны жүктеу мүмкін болмады',
      );
  String get syncAndBackupTitle => _pick(
        'Sync & Backup',
        'Синхронизация и бэкап',
        'Синхрондау және бэкап',
      );
  String get autoSyncGoogleSheetsSection => _pick(
        'Auto-sync (Google Sheets)',
        'Автосинхронизация (Google Таблица)',
        'Автосинхрондау (Google Кесте)',
      );
  String get manualBackupExportSection => _pick(
        'Manual backup / export',
        'Ручной бэкап / экспорт',
        'Қолмен бэкап / экспорт',
      );
  String get manualBackupExportSubtitle => _pick(
        'Copy for A1, CSV, JSON backup & import',
        'Копирование для A1, CSV, JSON и импорт',
        'A1 көшіру, CSV, JSON және импорт',
      );
  String get catalogMaintenanceTitle => _pick(
        'Catalog maintenance',
        'Обслуживание каталога',
        'Каталогқа қызмет көрсету',
      );
  String get catalogMaintenanceSubtitle => _pick(
        'Duplicates & bulk archive / trash',
        'Дубликаты и массовый перенос в архив/корзину',
        'Көшірмелер және жаппай мұрағат/себетке көшіру',
      );
  String get dangerBulkActionsTitle => _pick(
        'Bulk actions (use with caution)',
        'Массовые действия (осторожно)',
        'Жаппай әрекеттер (абайлаңыз)',
      );
  String get reportsBtn => _pick(
        'Reports',
        'Отчёты',
        'Есептер',
      );
  String get printInvoicePriceTagsBtn => _pick(
        'Print price tags',
        'Ценники',
        'Баға белгілері',
      );
  String get printAllPriceTagsBtn => _pick(
        'Print all (PDF)',
        'Распечатать все (PDF)',
        'Барлығын басу (PDF)',
      );
  String get batchPriceTagsTitle => _pick(
        'Print price tags',
        'Печать ценников',
        'Баға белгілерін басу',
      );
  String get cashDepositBtn => _pick(
        '+ Deposit',
        '+ Внести',
        '+ Салу',
      );
  String get cashWithdrawalBtn => _pick(
        '− Withdraw',
        '− Выемка',
        '− Алу',
      );
  String get cashDepositTitle => _pick(
        'Cash deposit (float)',
        'Внесение наличных (размен)',
        'Қолма-қол ақша салу (ұсақ ақша)',
      );
  String get cashWithdrawalTitle => _pick(
        'Cash withdrawal (collection)',
        'Выемка наличных (инкассация)',
        'Қолма-қол ақша алу (инкассация)',
      );
  String get cashDepositsLabel => _pick(
        'Deposits (float)',
        'Внесения (размен)',
        'Салымдар (ұсақ ақша)',
      );
  String get cashWithdrawalsLabel => _pick(
        'Withdrawals (collection)',
        'Выемки (инкассация)',
        'Алу (инкассация)',
      );
  String get cashMovementNoteHint => _pick(
        'Note (e.g. change float, owner collection)',
        'Комментарий (например: размен, инкассация)',
        'Түсініктеме (мысалы: ұсақ ақша, инкассация)',
      );
  String get shiftCashFormulaHintFull => _pick(
        'Start + cash sales + deposits − withdrawals − expenses',
        'Начало + нал. продажи + внесения − выемки − расходы',
        'Басы + қолма-қол сатылым + салым − алу − шығындар',
      );
  String get suppliersDirectoryBtn => _pick(
        'Suppliers',
        'Поставщики',
        'Жеткізушілер',
      );
  String get suppliersDirectoryTitle => _pick(
        'Suppliers Directory',
        'Справочник поставщиков',
        'Жеткізушілер анықтамалығы',
      );
  String get suppliersTabLabel => _pick(
        'Suppliers',
        'Поставщики',
        'Жеткізушілер',
      );
  String get cheapestSupplierTabLabel => _pick(
        'Best prices',
        'Где дешевле',
        'Қайда арзан',
      );
  String get suppliersEmptyMsg => _pick(
        'No suppliers yet. Specify supplier name when recording stock-in.',
        'Пока нет поставщиков. Указывайте поставщика при оформлении прихода.',
        'Әзірге жеткізушілер жоқ. Кіріс кезінде жеткізушіні көрсетіңіз.',
      );
  String get cheapestSupplierEmptyMsg => _pick(
        'No purchase history for price comparison yet.',
        'Пока нет закупок для сравнения цен между поставщиками.',
        'Бағаларды салыстыру үшін әзірге сатып алу тарихы жоқ.',
      );
  String get searchSuppliersHint => _pick(
        'Search supplier or product...',
        'Поиск по поставщику или товару...',
        'Жеткізуші немесе тауар бойынша іздеу...',
      );
  String supplierStatsSummary(int invoices, int products) => _pick(
        '$invoices invoices • $products items',
        'Накладных: $invoices • Позиций: $products',
        'Жүкқұжат: $invoices • Тауар: $products',
      );
  String get cheapestLastTimeLabel => _pick(
        'Cheapest last time',
        'Дешевле в последний раз',
        'Соңғы рет ең арзан',
      );
  String get moreOptionsBtn => _pick(
        'More options',
        'Ещё параметры',
        'Қосымша параметрлер',
      );
  String get quickPosItemsTitle => _pick(
        'Quick items',
        'Быстрые товары',
        'Жылдам тауарлар',
      );
  String get multiScanLabel => _pick(
        'Multi-scan',
        'Мультискан',
        'Мультискан',
      );
  String inReceiptCountLabel(num count) => _pick(
        'In receipt: ${_q(count)}',
        'В чеке: ${_q(count)}',
        'Чекте: ${_q(count)}',
      );
  String get exactCashBtn => _pick(
        'Exact',
        'Без сдачи',
        'Қайтарымсыз',
      );
  String get repeatOrderBtn => _pick(
        'Repeat order',
        'Повторить заказ',
        'Тапсырысты қайталау',
      );
  String orderRepeatedToCartMsg(int count) => _pick(
        'Added $count items to cart',
        'В корзину добавлено позиций: $count',
        'Себетке қосылған тауар: $count',
      );
  String orderRepeatedPartialMsg(int added, int skipped) => _pick(
        'Added $added items (unavailable: $skipped)',
        'Добавлено: $added • Нет в наличии: $skipped',
        'Қосылды: $added • Қоймада жоқ: $skipped',
      );
  String get noAvailableItemsToRepeatMsg => _pick(
        'None of the items from this receipt are in stock',
        'Товары из этого чека отсутствуют на складе',
        'Бұл чектегі тауарлар қоймада жоқ',
      );
  String get newCustomerBtn => _pick(
        'New customer',
        'Новый клиент',
        'Жаңа сатып алушы',
      );
  String get customPosItemBtn => _pick(
        '+ Custom item',
        '+ Своя позиция',
        '+ Еркін тауар',
      );
  String get customPosItemTitle => _pick(
        'Custom item (no card)',
        'Свободная позиция',
        'Еркін тауар',
      );
  String get customPosItemDefaultName => _pick(
        'Custom item',
        'Свободная позиция',
        'Еркін тауар',
      );
  String get customPosItemNameHint => _pick(
        'Name (optional)',
        'Название (необязательно)',
        'Атауы (міндетті емес)',
      );
  String get addToReceiptAction => _pick(
        'Add to receipt',
        'Добавить в чек',
        'Чекке қосу',
      );
  String get voiceSearchTooltip => _pick(
        'Voice search',
        'Голосовой поиск',
        'Дауыспен іздеу',
      );
  String get voiceListeningHint => _pick(
        'Listening...',
        'Слушаю...',
        'Тыңдап тұрмын...',
      );
  String get voiceSearchUnavailableMsg => _pick(
        'Voice search is unavailable on this device',
        'Голосовой поиск недоступен на этом устройстве',
        'Бұл құрылғыда дауыспен іздеу қолжетімсіз',
      );
  String get thermalPrintBtn => _pick(
        'Print (Bluetooth)',
        'Печать на принтер',
        'Принтерге басу',
      );
  String get thermalPrinterTitle => _pick(
        'Bluetooth Printer (58 / 80 mm)',
        'Термопринтер (58 / 80 мм)',
        'Термопринтер (58 / 80 мм)',
      );
  String get selectPrinterTitle => _pick(
        'Select Bluetooth Printer',
        'Выберите Bluetooth-принтер',
        'Bluetooth-принтерді таңдаңыз',
      );
  String get noPairedPrintersMsg => _pick(
        'No paired Bluetooth printers found. Pair your printer in phone Settings first.',
        'Сопряжённые Bluetooth-принтеры не найдены. Сначала подключите принтер в настройках телефона.',
        'Жұпталған Bluetooth-принтерлер табылмады. Алдымен телефон баптауларынан қосыңыз.',
      );
  String get paperWidthLabel => _pick(
        'Paper width',
        'Ширина ленты',
        'Таспа ені',
      );
  String get printSuccessMsg => _pick(
        'Sent to printer',
        'Отправлено на печать',
        'Басып шығаруға жіберілді',
      );
  String get printFailedMsg => _pick(
        'Could not print. Check printer power & Bluetooth.',
        'Не удалось напечатать. Проверьте питание принтера и Bluetooth.',
        'Басып шығару мүмкін болмады. Принтер мен Bluetooth-ды тексеріңіз.',
      );
  String get testPrintBtn => _pick(
        'Test print',
        'Пробная печать',
        'Сынақ басып шығару',
      );
  String get checkoutMoreOptionsTitle => _pick(
        'More (discount, debt, customer)',
        'Ещё (скидка, долг, клиент)',
        'Тағы (жеңілдік, қарыз, сатып алушы)',
      );
  String get frequentlyBoughtWithLabel => _pick(
        'Often bought with:',
        'С этим часто берут:',
        'Мұнымен жиі алады:',
      );
  String get sendPriceListBtn => _pick(
        'Send price list',
        'Отправить прайс',
        'Прайс жіберу',
      );
  String get priceListTitle => _pick(
        'Price List for WhatsApp',
        'Прайс-лист для WhatsApp',
        'WhatsApp-қа арналған прайс',
      );
  String get newArrivalsOnlyLabel => _pick(
        'New arrivals (14d)',
        'Новинки (14 дн.)',
        'Жаңа тауарлар (14 күн)',
      );
  String get includeWholesalePricesLabel => _pick(
        'Wholesale prices',
        'Оптовые цены',
        'Көтерме бағалар',
      );
  String get includeStockCountLabel => _pick(
        'Stock count',
        'Остатки',
        'Қалдық саны',
      );
  String get priceListEmptyMsg => _pick(
        'No products match the selected filters.',
        'Нет товаров по выбранным фильтрам.',
        'Таңдалған сүзгілер бойынша тауар жоқ.',
      );
  String priceListCountLabel(int count) => _pick(
        '$count item(s) in price list',
        'Позиций в прайсе: $count',
        'Прайстағы тауар: $count',
      );
  String approxDaysLeftShort(int days) => _pick(
        '~${days}d left',
        '~на $days дн.',
        '~$days күнге',
      );
  String get frozenCashBtn => _pick(
        'Frozen Cash (Dead Stock)',
        'Замороженные деньги (неликвид)',
        'Тоқтап тұрған ақша (өтпейтін)',
      );
  String get frozenCashTitle => _pick(
        'Frozen Cash Recovery',
        'Возврат замороженных денег',
        'Тоқтап тұрған ақшаны қайтару',
      );
  String get frozenCashSubtitle => _pick(
        'Top in-stock items with the most tied-up money and no sales for 30–60+ days.',
        'Товары, в которых лежит больше всего денег и не было продаж 30–60+ дней.',
        'Ең көп ақша салынған және 30–60+ күн сатылмаған тауарлар.',
      );
  String frozenCashTotalLabel(String amount, int count) => _pick(
        'Frozen: $amount ($count items)',
        'Заморожено: $amount ($count поз.)',
        'Тоқтап тұр: $amount ($count тауар)',
      );
  String get frozenCashFilter30Plus =>
      _pick('30+ days', '30+ дней', '30+ күн');
  String get frozenCashFilter30To60 =>
      _pick('30–60 days', '30–60 дней', '30–60 күн');
  String get frozenCashFilter60Plus =>
      _pick('60+ days', '60+ дней', '60+ күн');
  String frozenCashDaysIdle(int days, bool hasEverSold) => hasEverSold
      ? _pick(
          'No sales for $days d',
          'Без продаж $days дн.',
          '$days күн сатылмады',
        )
      : _pick(
          'No sales ($days d on shelf)',
          'Без продаж ($days дн. на складе)',
          'Сатылым жоқ ($days күн қоймада)',
        );
  String get frozenCashHintBadge => _pick(
        'Run promo / bundle',
        'Сделать акцию / комплект',
        'Акция / жинақ жасау',
      );
  String get frozenCashActionBtn => _pick(
        'Set Promo',
        'Сделать акцию',
        'Акция жасау',
      );
  String get frozenCashEmptyMsg => _pick(
        'No slow-moving stock in this period.',
        'Залежавшихся товаров за этот период нет.',
        'Бұл кезеңде өтпей тұрған тауарлар жоқ.',
      );
  String newMarginLabel(String pct) => _pick(
        'New margin: $pct%',
        'Новая маржа: $pct%',
        'Жаңа маржа: $pct%',
      );
  String raiseSellPriceAction(int percent, String price) => _pick(
        'Raise sell price (+$percent%) → $price',
        'Поднять цену продажи (+$percent%) → $price',
        'Сату бағасын көтеру (+$percent%) → $price',
      );
  String get noWholesaleDiscountBtn => _pick(
        'No discount (retail)',
        'Без скидки (розница)',
        'Жеңілдіксіз (бөлшек)',
      );
  String get restoreWholesaleBtn => _pick(
        'Apply wholesale',
        'Вернуть опт',
        'Көтерме бағаны қайтару',
      );
  String get allowCashierDiscountsLabel => _pick(
        'Allow Cashier Discounts',
        'Разрешать скидки продавцу',
        'Сатушыға жеңілдік беруге рұқсат',
      );
  String get allowCashierDiscountsHint => _pick(
        'When off, cashiers cannot apply receipt discounts',
        'Если выключено, в режиме продавца нельзя делать скидку',
        'Өшірулі болса, сатушы режимінде жеңілдік жасалмайды',
      );
  String get discountsDisabledNote => _pick(
        'Discounts are disabled by the owner',
        'Скидки отключены владельцем',
        'Жеңілдіктерді иесі өшірген',
      );
  String get supplierDebtModeLabel => _pick(
        'On credit (debt)',
        'В долг поставщику',
        'Жеткізушіге қарызға',
      );
  String supplierDebtBadge(String amount) => _pick(
        'We owe: $amount',
        'Наш долг: $amount',
        'Біздің қарыз: $amount',
      );
  String supplierDebtTotalLabel(String amount) => _pick(
        'Owed to suppliers: $amount',
        'Долг поставщикам: $amount',
        'Жеткізушілерге қарыз: $amount',
      );
  String supplierDebtOnlyFilter(int count) => _pick(
        'With Debt ($count)',
        'С долгом ($count)',
        'Қарызы бар ($count)',
      );
  String supplierDebtRepaymentTitle(String supplier) => supplier.trim().isEmpty
      ? _pick(
          'Supplier debt payment',
          'Оплата долга поставщику',
          'Жеткізушіге қарыз төлеу',
        )
      : _pick(
          'Supplier debt: ${supplier.trim()}',
          'Долг поставщику: ${supplier.trim()}',
          'Жеткізушіге қарыз: ${supplier.trim()}',
        );
  String get paySupplierDebtTitle => _pick(
        'Pay Supplier Debt',
        'Оплата поставщику',
        'Жеткізушіге төлем',
      );
  String get unspecifiedSupplierLabel => _pick(
        'Unspecified supplier',
        'Без поставщика',
        'Жеткізуші көрсетілмеген',
      );
}
