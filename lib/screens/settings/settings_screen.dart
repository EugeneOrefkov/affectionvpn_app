import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../services/core_log_service.dart';
import '../../services/core_update_service.dart';
import '../../services/request_log_service.dart';
import '../../services/vpn_service.dart';
import '../../state/app_state.dart';
import '../onboarding/subscription_input_screen.dart';
import 'request_log_screen.dart';
import 'widgets/update_section.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _coreVersion = '';
  int _coreTapCount = 0;
  Timer? _coreTapTimer;
  bool _coreSheetOpen = false;

  @override
  void initState() {
    super.initState();
    _loadCoreVersion();
  }

  @override
  void dispose() {
    _coreTapTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCoreVersion() async {
    try {
      final version = await VpnService.instance.getCoreVersion();
      final match = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(version);
      if (mounted) {
        setState(() => _coreVersion = match?.group(1) ?? version.trim());
      }
    } catch (_) {}
  }

  /// Five quick taps on the core version open the experimental-core panel.
  void _onCoreTap() {
    if (_coreSheetOpen) {
      return;
    }
    _coreTapTimer?.cancel();
    _coreTapTimer = Timer(const Duration(seconds: 3), () {
      _coreTapCount = 0;
    });
    _coreTapCount++;
    if (_coreTapCount >= 5) {
      _coreTapCount = 0;
      _coreTapTimer?.cancel();
      _openExperimentalCoreSheet();
    }
  }

  Future<void> _openExperimentalCoreSheet() async {
    _coreSheetOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _ExperimentalCoreSheet(),
    );
    _coreSheetOpen = false;
    _loadCoreVersion();
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.link,
                              color: AppColors.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Ссылка на подписку',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                        child: SelectableText(
                          state.subscriptionUrl ?? '—',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Row(
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
                      ),
                      const Divider(height: 1),
                      _SwitchRow(
                        icon: Icons.sync,
                        title: 'Автообновление подписки',
                        subtitle: 'Обновление подписки происходит каждый час, '
                            'чтобы получать самые свежие изменения',
                        value: state.autoRefreshSubscription,
                        onChanged: state.setAutoRefreshSubscription,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const _SectionTitle('Подключение'),
                  _Card(
                    children: [
                      _PingMethodSelector(
                        value: state.pingMethod,
                        onChanged: state.setPingMethod,
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
                      _VpnModeSelector(
                        mode: state.proxyOnly ? VpnMode.proxy : VpnMode.tun,
                        onChanged: (mode) {
                          state.setProxyOnly(mode == VpnMode.proxy);
                        },
                      ),
                      const Divider(height: 1),
                      _SwitchRow(
                        icon: Icons.language,
                        title: 'Показывать IP на главном экране',
                        subtitle: 'Отображать текущий IP-адрес',
                        value: state.showIp,
                        onChanged: state.setShowIp,
                      ),
                      if (state.proxyOnly) ...[
                        const Divider(height: 1),
                        _SwitchRow(
                          icon: Icons.lock_outline,
                          title: 'Авторизация прокси',
                          subtitle: 'Требовать логин и пароль для подключения',
                          value: state.proxyAuthEnabled,
                          onChanged: state.setProxyAuthEnabled,
                        ),
                        if (state.proxyAuthEnabled) ...[
                          const Divider(height: 1),
                          _ProxyInfo(
                            host: state.proxyHost,
                            port: state.proxyPort,
                            login: state.proxyLogin,
                            password: state.proxyPassword,
                          ),
                        ],
                      ],
                      const Divider(height: 1),
                      _BypassCidrList(
                        cidrs: state.bypassCidrs,
                        onAdd: state.addBypassCidr,
                        onRemove: state.removeBypassCidr,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const _SectionTitle('Обновление'),
                  const UpdateSection(),
                  const SizedBox(height: 24),
                  const _SectionTitle('Журнал запросов'),
                  _Card(
                    children: [
                      _SwitchRow(
                        icon: Icons.list_alt,
                        title: 'Логирование запросов',
                        subtitle: 'Записывать запросы приложения и трафик туннеля',
                        value: state.requestLogEnabled,
                        onChanged: state.setRequestLogEnabled,
                      ),
                      const Divider(height: 1),
                      ListenableBuilder(
                        listenable: RequestLogService.instance,
                        builder: (context, _) => _OpenLogRow(
                          enabled: state.requestLogEnabled,
                          entryCount:
                              RequestLogService.instance.entries.length,
                          onTap: state.requestLogEnabled
                              ? () => _openRequestLog()
                              : null,
                        ),
                      ),
                    ],
                  ),
                  if (io.Platform.isLinux || io.Platform.isAndroid) ...[
                    const SizedBox(height: 24),
                    const _SectionTitle('Логи ядра'),
                    _Card(
                      children: [
                        AnimatedBuilder(
                          animation: CoreLogService.instance,
                          builder: (context, _) {
                            final hasLogs =
                                CoreLogService.instance.logs.isNotEmpty;
                            return InkWell(
                              onTap: hasLogs ? _openCoreLog : null,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(14, 14, 14, 14),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.terminal,
                                      color: hasLogs
                                          ? AppColors.primary
                                          : AppColors.textTertiary,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Вывод xray',
                                            style: TextStyle(
                                              color: hasLogs
                                                  ? AppColors.textPrimary
                                                  : AppColors.textSecondary,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            hasLogs
                                                ? '${CoreLogService.instance.logs.length} строк'
                                                : 'Нет логов',
                                            style: const TextStyle(
                                              color: AppColors.textTertiary,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Icon(
                                      Icons.chevron_right,
                                      color: AppColors.textTertiary,
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  const _SectionTitle('О приложении'),
                  _Card(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _onCoreTap,
                        child: _InfoRow(
                          icon: Icons.shield_outlined,
                          label: 'Ядро Xray',
                          value: _coreVersion.isEmpty ? '…' : _coreVersion,
                        ),
                      ),
                      const Divider(height: 1),
                      _InfoRow(
                        icon: Icons.info_outline,
                        label: 'Версия приложения',
                        value: state.currentVersion,
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

  void _openCoreLog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surface,
        insetPadding: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Вывод xray',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close, color: AppColors.textTertiary, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(10),
                  ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        CoreLogService.instance.logs.isEmpty
                            ? 'Логов нет'
                            : CoreLogService.instance.logs.join('\n'),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _openRequestLog() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RequestLogScreen()),
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
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
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
              maxLines: 1,
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

class _ProxyInfo extends StatelessWidget {
  const _ProxyInfo({
    required this.host,
    required this.port,
    required this.login,
    required this.password,
  });

  final String host;
  final int port;
  final String login;
  final String password;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lan_outlined,
                color: AppColors.accent,
                size: 20,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'SOCKS5 прокси',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ProxyValueRow(label: 'Адрес', value: host, copyable: true),
          _ProxyValueRow(label: 'Порт', value: '$port', copyable: true),
          _ProxyValueRow(label: 'Логин', value: login, copyable: true),
          _ProxyValueRow(label: 'Пароль', value: password, copyable: true),
        ],
      ),
    );
  }
}

class _ProxyValueRow extends StatelessWidget {
  const _ProxyValueRow({
    required this.label,
    required this.value,
    this.copyable = false,
  });

  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (copyable)
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    const SnackBar(
                      content: Text('Скопировано'),
                      duration: Duration(seconds: 1),
                    ),
                  );
              },
              icon: const Icon(
                Icons.copy,
                color: AppColors.textTertiary,
                size: 16,
              ),
            ),
        ],
      ),
    );
  }
}

class _BypassCidrList extends StatefulWidget {
  const _BypassCidrList({
    required this.cidrs,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> cidrs;
  final Future<void> Function(String cidr) onAdd;
  final Future<void> Function(String cidr) onRemove;

  @override
  State<_BypassCidrList> createState() => _BypassCidrListState();
}

class _BypassCidrListState extends State<_BypassCidrList> {
  final _controller = TextEditingController();
  static const _presets = [
    '10.0.0.0/8',
    '172.16.0.0/12',
    '192.168.0.0/16',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add(String cidr) async {
    final trimmed = cidr.trim();
    if (trimmed.isEmpty) return;
    if (!_validCidr(trimmed)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Неверный CIDR. Пример: 192.168.0.0/16'),
            duration: Duration(seconds: 2),
          ),
        );
      return;
    }
    await widget.onAdd(trimmed);
    _controller.clear();
  }

  static final _cidrRe = RegExp(
    r'^(\d{1,3}\.){3}\d{1,3}/\d{1,2}$',
  );

  bool _validCidr(String s) {
    if (!_cidrRe.hasMatch(s)) return false;
    final parts = s.split('/');
    final prefix = int.tryParse(parts[1]);
    if (prefix == null || prefix < 0 || prefix > 32) return false;
    return parts[0].split('.').every((p) {
      final n = int.tryParse(p);
      return n != null && n >= 0 && n <= 255;
    });
  }

  @override
  Widget build(BuildContext context) {
    final presets = _presets
        .where((p) => !widget.cidrs.contains(p))
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.route_outlined,
                color: AppColors.accent,
                size: 20,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Обход туннеля',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Подсети, которые идут напрямую, минуя прокси',
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: '192.168.0.0/16',
                    hintStyle: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 13,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(
                        color: AppColors.border,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(
                        color: AppColors.border,
                      ),
                    ),
                  ),
                  onSubmitted: _add,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => _add(_controller.text),
                icon: const Icon(
                  Icons.add,
                  color: AppColors.accent,
                  size: 20,
                ),
              ),
            ],
          ),
          if (presets.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in presets)
                  ActionChip(
                    label: Text(
                      p,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    backgroundColor: AppColors.card,
                    side: const BorderSide(color: AppColors.border),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _add(p),
                  ),
              ],
            ),
          ],
          if (widget.cidrs.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final cidr in widget.cidrs)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.circle,
                      color: AppColors.accent,
                      size: 6,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        cidr,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => widget.onRemove(cidr),
                      icon: const Icon(
                        Icons.close,
                        color: AppColors.textTertiary,
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ),
          ],
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

class _OpenLogRow extends StatelessWidget {
  const _OpenLogRow({
    required this.enabled,
    required this.entryCount,
    required this.onTap,
  });

  final bool enabled;
  final int entryCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Row(
          children: [
            Icon(
              Icons.receipt_long,
              color: enabled ? AppColors.primary : AppColors.textTertiary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Журнал запросов',
                    style: TextStyle(
                      color: enabled
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    enabled
                        ? '$entryCount записей'
                        : 'Включите логирование, чтобы просматривать записи',
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              Icons.chevron_right,
              color: enabled ? AppColors.textTertiary : AppColors.border,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _PingMethodSelector extends StatelessWidget {
  const _PingMethodSelector({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.network_check,
                color: AppColors.accent,
                size: 20,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Метод проверки пинга',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'TCP — быстрое измерение; GET — точная проверка через прокси',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MethodChip(
                  label: 'HTTP GET',
                  selected: value == 'get',
                  onTap: () => onChanged('get'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MethodChip(
                  label: 'TCP',
                  selected: value == 'tcp',
                  onTap: () => onChanged('tcp'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MethodChip extends StatelessWidget {
  const _MethodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.14) : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.primary : AppColors.textSecondary,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
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

class _ExperimentalCoreSheet extends StatefulWidget {
  const _ExperimentalCoreSheet();

  @override
  State<_ExperimentalCoreSheet> createState() => _ExperimentalCoreSheetState();
}

class _ExperimentalCoreSheetState extends State<_ExperimentalCoreSheet> {
  bool? _supported;
  String? _installed;
  String? _latest;
  String? _active;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = CoreUpdateService.instance;
    final supported = await service.isSupported();
    String? installed;
    String? latest;
    String? active;
    if (supported) {
      installed = await service.installedVersion();
      latest = await service.fetchLatestVersion();
      try {
        final v = await VpnService.instance.getCoreVersion();
        active =
            RegExp(r'(\d+\.\d+\.\d+)').firstMatch(v)?.group(1) ?? v.trim();
      } catch (_) {}
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _supported = supported;
      _installed = installed;
      _latest = latest;
      _active = active;
    });
  }

  Future<void> _install() async {
    final version = _latest;
    if (version == null || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await CoreUpdateService.instance.install(version);
      if (!mounted) {
        return;
      }
      setState(() {
        _installed = version;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Экспериментальное ядро установлено. Переподключитесь для применения.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _reset() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await CoreUpdateService.instance.reset();
      if (!mounted) {
        return;
      }
      setState(() {
        _installed = null;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Стандартное ядро восстановлено. Переподключитесь для применения.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final supported = _supported;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.science_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Экспериментальное ядро',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.close,
                    color: AppColors.textTertiary,
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (supported == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (!supported)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Экспериментальное ядро недоступно для этого устройства',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              )
            else ...[
              if (_active != null)
                _CoreStatusLine(label: 'Активное ядро', value: _active!),
              if (_installed != null) ...[
                const SizedBox(height: 6),
                _CoreStatusLine(
                  label: 'Экспериментальное',
                  value: _installed!,
                  highlight: true,
                ),
              ],
              const SizedBox(height: 14),
              if (_latest != null)
                _CoreStatusLine(
                  label: 'Доступно',
                  value: 'v$_latest',
                  valueColor: AppColors.primary,
                )
              else
                const Text(
                  'Не удалось получить последнюю версию',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
              const SizedBox(height: 18),
              if (_busy)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _latest == null ? null : _install,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.download, size: 18),
                    label: Text(
                      _installed == null
                          ? 'Установить экспериментальное ядро'
                          : 'Обновить до последней версии',
                    ),
                  ),
                ),
                if (_installed != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _reset,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text('Вернуть стандартное ядро'),
                    ),
                  ),
                ],
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              const Text(
                'Экспериментальная сборка может быть нестабильной. '
                'После установки переподключитесь для применения.',
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum VpnMode { proxy, tun }

class _VpnModeSelector extends StatelessWidget {
  const _VpnModeSelector({
    required this.mode,
    required this.onChanged,
  });

  final VpnMode mode;
  final ValueChanged<VpnMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.remove_road, color: AppColors.accent, size: 20),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Режим работы',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Системное прокси или TUN-туннель',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MethodChip(
                  label: 'Системное прокси',
                  selected: mode == VpnMode.proxy,
                  onTap: () => onChanged(VpnMode.proxy),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MethodChip(
                  label: 'TUN',
                  selected: mode == VpnMode.tun,
                  onTap: () => onChanged(VpnMode.tun),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CoreStatusLine extends StatelessWidget {
  const _CoreStatusLine({
    required this.label,
    required this.value,
    this.highlight = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool highlight;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = valueColor ??
        (highlight ? AppColors.accent : AppColors.textPrimary);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: effectiveColor,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
