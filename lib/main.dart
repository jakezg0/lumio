import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/expenses_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/pos_screen.dart';
import 'screens/sales_screen.dart';
import 'state/shop_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  runApp(const ShopInventoryApp());
}

class ShopInventoryApp extends StatefulWidget {
  const ShopInventoryApp({super.key, this.controller});

  final ShopController? controller;

  @override
  State<ShopInventoryApp> createState() => _ShopInventoryAppState();
}

class _ShopInventoryAppState extends State<ShopInventoryApp>
    with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  late final ShopController _controller;
  int _currentIndex = 0;
  bool _reminderDialogOpen = false;
  bool _initialReminderChecked = false;
  DateTime? _lastReminderShownAt;
  int _lastHandledSyncNoticeVersion = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = widget.controller ?? ShopController();
    _controller.addListener(_onControllerChanged);
    _controller.initialize();
  }

  void _onControllerChanged() {
    if (!_initialReminderChecked && _controller.isLoaded) {
      _initialReminderChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeShowNegativeStockReminder(force: true);
      });
    }
    if (_controller.syncNoticeVersion != _lastHandledSyncNoticeVersion) {
      _lastHandledSyncNoticeVersion = _controller.syncNoticeVersion;
      final notice = _controller.lastSheetSyncNotice;
      final isError = _controller.lastSheetSyncIsError;
      if (notice.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final messenger = _scaffoldMessengerKey.currentState;
          if (messenger == null) return;
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text(notice),
              backgroundColor: isError ? Colors.red.shade700 : null,
              duration: Duration(seconds: isError ? 5 : 3),
            ),
          );
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _controller.isLoaded) {
      _maybeShowNegativeStockReminder(force: true);
      _controller.syncFromSheetInBackground();
    } else if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.inactive) &&
        _controller.isLoaded) {
      _controller.flushAutoBackupIfPending();
    }
  }

  Future<void> _maybeShowNegativeStockReminder({bool force = false}) async {
    if (!mounted || _reminderDialogOpen || !_controller.isLoaded) return;
    final reminders = _controller.activeNegativeStockReminders;
    if (reminders.isEmpty) return;

    final now = DateTime.now();
    if (!force &&
        _lastReminderShownAt != null &&
        now.difference(_lastReminderShownAt!) < const Duration(minutes: 2)) {
      return;
    }
    if (force &&
        _lastReminderShownAt != null &&
        now.difference(_lastReminderShownAt!) < const Duration(seconds: 10)) {
      return;
    }

    final navContext = _navigatorKey.currentContext;
    if (navContext == null) return;

    _reminderDialogOpen = true;
    _lastReminderShownAt = now;
    final strings = _controller.strings;
    final maxRemaining = reminders
        .map((e) => e.remaining)
        .reduce((a, b) => a > b ? a : b);
    final shownNumber = (6 - maxRemaining).clamp(1, 5);

    try {
      final goToGoods = await showDialog<bool>(
        context: navContext,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(ctx).colorScheme.error,
            size: 32,
          ),
          title: Text(strings.negativeStockReminderTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  strings.reminderCountOfFive(shownNumber, 5),
                  style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                        color: Theme.of(ctx).colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(height: 10),
              Text(strings.negativeStockReminderBody),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final item in reminders)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.product.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${item.product.stock}',
                                style: TextStyle(
                                  color: Theme.of(ctx).colorScheme.error,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(strings.remindLaterBtn),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(strings.restoreStockNowBtn),
            ),
          ],
        ),
      );

      await _controller.acknowledgeNegativeStockReminders();
      if (goToGoods == true && mounted) {
        await _controller.prepareStockInForNegativeProducts();
        _controller.requestOpenStockIn();
        setState(() => _currentIndex = 0);
      }
    } finally {
      _reminderDialogOpen = false;
    }
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    _controller.syncWithSystemLocales(
      locales ?? PlatformDispatcher.instance.locales,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onControllerChanged);
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      title: 'Lumio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
        ),
        useMaterial3: true,
      ),
      home: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          if (!_controller.isLoaded) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final strings = _controller.strings;
          final isCashier = _controller.cashierMode;
          final negativeCount = _controller.negativeStockProductsCount;
          final screens = [
            InventoryScreen(controller: _controller),
            PosScreen(controller: _controller),
            SalesScreen(controller: _controller),
            if (!isCashier) ExpensesScreen(controller: _controller),
          ];

          final safeIndex = _currentIndex >= screens.length ? 0 : _currentIndex;

          return Scaffold(
            resizeToAvoidBottomInset: false,
            body: Column(
              children: [
                if (_controller.isSyncing)
                  Material(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                strings.syncingWithSheetsStatus,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer,
                                      fontWeight: FontWeight.w600,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(child: screens[safeIndex]),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: safeIndex,
              onDestinationSelected: (index) {
                if (index != _currentIndex) {
                  const tabKeys = [
                    FeatureUsageKeys.tabGoods,
                    FeatureUsageKeys.tabSell,
                    FeatureUsageKeys.tabSales,
                    FeatureUsageKeys.tabExpenses,
                  ];
                  if (index >= 0 && index < tabKeys.length) {
                    _controller.trackFeatureUsage(tabKeys[index]);
                  }
                }
                setState(() => _currentIndex = index);
                if (index != 0) {
                  _maybeShowNegativeStockReminder();
                }
              },
              destinations: [
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: negativeCount > 0,
                    label: Text('$negativeCount'),
                    child: const Icon(Icons.inventory_2_outlined),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: negativeCount > 0,
                    label: Text('$negativeCount'),
                    child: const Icon(Icons.inventory_2),
                  ),
                  label: strings.navGoods,
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: _controller.cartItemCount > 0,
                    label: Text('${_controller.cartItemCount}'),
                    child: const Icon(Icons.point_of_sale_outlined),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: _controller.cartItemCount > 0,
                    label: Text('${_controller.cartItemCount}'),
                    child: const Icon(Icons.point_of_sale),
                  ),
                  label: strings.navSell,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.receipt_long_outlined),
                  selectedIcon: const Icon(Icons.receipt_long),
                  label: strings.navSales,
                ),
                if (!isCashier)
                  NavigationDestination(
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                    selectedIcon: const Icon(Icons.account_balance_wallet),
                    label: strings.navExpenses,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
