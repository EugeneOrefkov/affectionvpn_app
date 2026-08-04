import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../services/vpn_service.dart';
import '../../state/app_state.dart';
import '../onboarding/subscription_input_screen.dart';
import '../onboarding/welcome_screen.dart';
import 'widgets/update_section.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _coreVersion = '';

  @override
  void initState() {
    super.initState();
    _loadCoreVersion();
  }

  Future<void> _loadCoreVersion() async {
    try {
      final version = await VpnService.instance.getCoreVersion();
      if (mounted) {
        setState(() => _coreVersion = version);
      }
    } catch (_) {}
  }

  Future<void> _removeSubscription() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить подписку?'),
        content: const Text(
          'Все сохранённые серверы будут удалены. '
          'Вы сможете добавить подписку позже.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Удалить',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await context.read<AppState>().removeSubscription();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Text(
                'Настройки',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  const _SectionTitle('Подписка'),
                  _Card(
                    children: [
                      _InfoRow(
                        icon: Icons.link,
                        label: 'Ссылка на подписку',
                        value: state.subscriptionUrl ?? '—',
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _ActionButton(
                              icon: Icons.refresh,
                              label: 'Обновить',
                              onTap: state.isLoadingSubscription
                                  ? null
                                  : _refresh,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _ActionButton(
                              icon: Icons.edit,
                              label: 'Заменить',
                              onTap: () => _replaceSubscription(state),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _DangerButton(
                        icon: Icons.delete_outline,
                        label: 'Удалить подписку',
                        onTap: _removeSubscription,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const _SectionTitle('Подключение'),
                  _Card(
                    children: [
                      _SwitchRow(
                        icon: Icons.tune,
                        title: 'Автовыбор лучшего сервера',
                        subtitle: 'Подключаться к серверу с наименьшим пингом',
                        value: state.autoSelectBest,
                        onChanged: state.setAutoSelectBest,
                      ),
                      const Divider(height: 1),
                      _SwitchRow(
                        icon: Icons.autorenew,
                        title: 'Автоподключение',
                        subtitle: 'Подключаться при запуске приложения',
                        value: state.autoConnect,
                        onChanged: state.setAutoConnect,
                      ),
                      const Divider(height: 1),
                      _SwitchRow(
                        icon: Icons.remove_road,
                        title: 'Только прокси',
                        subtitle: 'Без системного VPN-туннеля',
                        value: state.proxyOnly,
                        onChanged: state.setProxyOnly,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const _SectionTitle('Обновление'),
                  const UpdateSection(),
                  const SizedBox(height: 24),
                  const _SectionTitle('О приложении'),
                  _Card(
                    children: [
                      _InfoRow(
                        icon: Icons.shield_outlined,
                        label: 'Ядро Xray',
                        value: _coreVersion.isEmpty ? '…' : _coreVersion,
                      ),
                      const Divider(height: 1),
                      _InfoRow(
                        icon: Icons.info_outline,
                        label: 'Версия приложения',
                        value: state.currentVersion,
                      ),
                      const Divider(height: 1),
                      const _InfoRow(
                        icon: Icons.privacy_tip_outlined,
                        label: 'Протоколы',
                        value: 'VLESS · VMess · Trojan · Shadowsocks',
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Center(
                    child: Text(
                      'Affection VPN · с любовью к приватности',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    final state = context.read<AppState>();
    try {
      await state.refreshSubscription();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Подписка обновлена')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка обновления: $e')),
        );
      }
    }
  }

  void _replaceSubscription(AppState state) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SubscriptionInputScreen(
          initialUrl: state.subscriptionUrl,
          replacesCurrent: true,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(icon, color: AppColors.accent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        backgroundColor: AppColors.surfaceAlt,
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

class _DangerButton extends StatelessWidget {
  const _DangerButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.danger,
        side: BorderSide(color: AppColors.danger.withValues(alpha: 0.4)),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
