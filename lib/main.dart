import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'screens/expenses_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/pos_screen.dart';
import 'screens/sales_screen.dart';
import 'state/shop_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  late final ShopController _controller;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = widget.controller ?? ShopController();
    _controller.initialize();
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
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
          final strings = _controller.strings;
          final isCashier = _controller.cashierMode;
          final screens = [
            InventoryScreen(controller: _controller),
            PosScreen(controller: _controller),
            SalesScreen(controller: _controller),
            if (!isCashier) ExpensesScreen(controller: _controller),
          ];

          final safeIndex = _currentIndex >= screens.length ? 0 : _currentIndex;

          return Scaffold(
            resizeToAvoidBottomInset: false,
            body: screens[safeIndex],
            bottomNavigationBar: NavigationBar(
              selectedIndex: safeIndex,
              onDestinationSelected: (index) {
                setState(() => _currentIndex = index);
              },
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.inventory_2_outlined),
                  selectedIcon: const Icon(Icons.inventory_2),
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
