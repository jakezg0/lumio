import '../l10n/app_strings.dart';

String formatMoney(double amount, [AppCurrency currency = AppCurrency.kzt]) {
  final negative = amount < 0;
  final abs = amount.abs();
  final String formattedNumber;

  if (currency == AppCurrency.kzt && (abs - abs.roundToDouble()).abs() < 0.005) {
    formattedNumber = _withSpaceGrouping(abs.round().toString());
  } else {
    final fixed = abs.toStringAsFixed(2);
    final parts = fixed.split('.');
    formattedNumber = '${_withSpaceGrouping(parts[0])}.${parts[1]}';
  }

  final signed = negative ? '-$formattedNumber' : formattedNumber;
  if (currency == AppCurrency.usd) {
    return negative ? '-\$${formattedNumber}' : '\$$formattedNumber';
  }
  return '$signed ${currency.symbol}';
}

String _withSpaceGrouping(String digits) {
  if (digits.length <= 3) return digits;
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final remaining = digits.length - i;
    if (i > 0 && remaining % 3 == 0) {
      buffer.write(' ');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

String formatDate(DateTime dt) {
  final year = dt.year.toString();
  final month = dt.month.toString().padLeft(2, '0');
  final day = dt.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

String formatDateTime(DateTime dt) {
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');
  return '${formatDate(dt)} $hour:$minute';
}
