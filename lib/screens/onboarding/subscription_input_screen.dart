import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../state/app_state.dart';
import '../home/main_shell.dart';

class SubscriptionInputScreen extends StatefulWidget {
  const SubscriptionInputScreen({super.key, this.initialUrl, this.replacesCurrent = false});

  final String? initialUrl;

  /// When true, keeps the current navigation stack and pops after import
  /// (used from Settings). Otherwise replaces the stack with MainShell.
  final bool replacesCurrent;

  @override
  State<SubscriptionInputScreen> createState() =>
      _SubscriptionInputScreenState();
}

class _SubscriptionInputScreenState extends State<SubscriptionInputScreen> {
  final _controller = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialUrl != null) {
      _controller.text = widget.initialUrl!;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final url = _controller.text.trim();
    if (url.isEmpty) {
      _showError('Введите ссылку на подписку');
      return;
    }
    if (_loading) {
      return;
    }
    setState(() => _loading = true);
    FocusScope.of(context).unfocus();
    final state = context.read<AppState>();
    try {
      await state.addSubscription(url);
      if (!mounted) {
        return;
      }
      if (widget.replacesCurrent) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainShell()),
        );
      }
    } catch (e) {
      if (mounted) {
        _showError('Не удалось загрузить подписку.\n$e');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      _controller.text = text.trim();
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _openCabinet() async {
    final uri = Uri.parse('https://cabinet.affectiion.ru');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      _showError('Не удалось открыть ссылку');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Подписка')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              const Text(
                'Вставьте ссылку на подписку',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Ссылку на подписку можно получить в личном кабинете Affection VPN:',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: _openCabinet,
                child: const Text(
                  'https://cabinet.affectiion.ru',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'После импорта все серверы появятся в приложении автоматически.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.url,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'https://sub.affectiion.ru/xxxxxx',
                  suffixIcon: IconButton(
                    onPressed: _paste,
                    tooltip: 'Вставить',
                    icon: const Icon(
                      Icons.content_paste_go,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                onSubmitted: (_) => _import(),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loading ? null : _import,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  disabledBackgroundColor:
                      AppColors.primary.withValues(alpha: 0.5),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Импортировать',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
