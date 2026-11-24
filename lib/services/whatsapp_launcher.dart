import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'input_normalizer.dart';

class WhatsAppLauncher {
  const WhatsAppLauncher._();

  static String normalizeWhatsAppDigits(String rawPhone) {
    final normalized = InputNormalizer.normalizePhone(rawPhone);
    final digits = normalized.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 7) return '';
    return digits;
  }

  static Uri? buildWhatsAppUri({
    required String phone,
    required String message,
  }) {
    final digits = normalizeWhatsAppDigits(phone);
    if (digits.isEmpty) return null;
    return Uri.https('wa.me', '/$digits', {'text': message});
  }

  static Future<void> openChatOrShare({
    required String phone,
    required String message,
    String subject = '',
  }) async {
    final digits = normalizeWhatsAppDigits(phone);
    if (digits.isNotEmpty) {
      final appUri = Uri(
        scheme: 'whatsapp',
        host: 'send',
        queryParameters: {'phone': digits, 'text': message},
      );
      try {
        if (await canLaunchUrl(appUri) &&
            await launchUrl(appUri, mode: LaunchMode.externalApplication)) {
          return;
        }
      } catch (_) {}

      final webUri = buildWhatsAppUri(phone: phone, message: message);
      if (webUri != null) {
        try {
          if (await launchUrl(webUri, mode: LaunchMode.externalApplication)) {
            return;
          }
        } catch (_) {}
      }
    }

    await Share.share(
      message,
      subject: subject.isNotEmpty ? subject : null,
    );
  }
}
