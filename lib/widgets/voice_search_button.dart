import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../l10n/app_strings.dart';

class VoiceSearchButton extends StatefulWidget {
  const VoiceSearchButton({
    super.key,
    required this.strings,
    required this.language,
    required this.onResult,
  });

  final AppStrings strings;
  final AppLanguage language;
  final ValueChanged<String> onResult;

  @override
  State<VoiceSearchButton> createState() => _VoiceSearchButtonState();
}

class _VoiceSearchButtonState extends State<VoiceSearchButton> {
  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;
  bool _listening = false;

  String _localeIdFor(AppLanguage lang) {
    switch (lang) {
      case AppLanguage.ru:
        return 'ru_RU';
      case AppLanguage.kk:
        return 'kk_KZ';
      case AppLanguage.en:
        return 'en_US';
    }
  }

  @override
  void dispose() {
    if (_listening) {
      _speech.stop();
    }
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    try {
      if (!_initialized) {
        _initialized = await _speech.initialize(
          onStatus: (status) {
            if (!mounted) return;
            if (status == 'done' || status == 'notListening') {
              setState(() => _listening = false);
            }
          },
          onError: (_) {
            if (mounted) setState(() => _listening = false);
          },
        );
      }
      if (!_initialized) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(widget.strings.voiceSearchUnavailableMsg)),
          );
        }
        return;
      }

      if (mounted) setState(() => _listening = true);
      await _speech.listen(
        listenOptions: SpeechListenOptions(
          localeId: _localeIdFor(widget.language),
          listenMode: ListenMode.search,
          partialResults: true,
        ),
        onResult: (result) {
          final text = result.recognizedWords.trim();
          if (text.isNotEmpty) {
            widget.onResult(text);
          }
          if (result.finalResult && mounted) {
            setState(() => _listening = false);
          }
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() => _listening = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.strings.voiceSearchUnavailableMsg)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _listening
          ? widget.strings.voiceListeningHint
          : widget.strings.voiceSearchTooltip,
      onPressed: _toggle,
      icon: Icon(
        _listening ? Icons.mic : Icons.mic_none_outlined,
        color: _listening ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }
}
