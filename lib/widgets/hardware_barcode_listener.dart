import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Pure buffer for USB / Bluetooth HID barcode scanners (keyboard wedge + Enter).
class HardwareBarcodeBuffer {
  HardwareBarcodeBuffer({
    this.maxInterKeyDelay = const Duration(milliseconds: 400),
    this.minLength = 4,
  });

  final Duration maxInterKeyDelay;
  final int minLength;
  final StringBuffer _buffer = StringBuffer();
  DateTime? _lastKeyAt;

  String? processKey({
    required LogicalKeyboardKey logicalKey,
    required String? character,
    required DateTime now,
  }) {
    if (_lastKeyAt != null && now.difference(_lastKeyAt!) > maxInterKeyDelay) {
      _buffer.clear();
    }

    if (logicalKey == LogicalKeyboardKey.enter ||
        logicalKey == LogicalKeyboardKey.numpadEnter) {
      final code = _buffer.toString().trim();
      _buffer.clear();
      _lastKeyAt = null;
      if (code.length >= minLength) {
        return code;
      }
      return null;
    }

    if (character != null && character.isNotEmpty) {
      final codeUnit = character.codeUnitAt(0);
      // Printable non-control characters (space 0x20 .. ~ 0x7E, or extended).
      if (codeUnit >= 0x21 && codeUnit != 0x7F) {
        _buffer.write(character);
        _lastKeyAt = now;
      }
    }
    return null;
  }

  void clear() {
    _buffer.clear();
    _lastKeyAt = null;
  }
}

/// Intercepts hardware HID barcode scanner input (USB / Bluetooth) when focus
/// is not inside a text input field, and delivers the scanned code on Enter.
class HardwareBarcodeListener extends StatefulWidget {
  const HardwareBarcodeListener({
    super.key,
    required this.onBarcode,
    required this.child,
    this.enabled = true,
  });

  final ValueChanged<String> onBarcode;
  final Widget child;
  final bool enabled;

  @override
  State<HardwareBarcodeListener> createState() =>
      _HardwareBarcodeListenerState();
}

class _HardwareBarcodeListenerState extends State<HardwareBarcodeListener> {
  final HardwareBarcodeBuffer _buffer = HardwareBarcodeBuffer();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _isFocusInsideEditableText() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    if (focusContext.widget is EditableText) return true;
    return focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!widget.enabled || !mounted) return false;
    if (event is! KeyDownEvent) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    if (_isFocusInsideEditableText()) {
      _buffer.clear();
      return false;
    }

    final scanned = _buffer.processKey(
      logicalKey: event.logicalKey,
      character: event.character,
      now: DateTime.now(),
    );
    if (scanned != null) {
      widget.onBarcode(scanned);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
