import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/subscription_info.dart';
import '../../state/app_state.dart';
import 'widgets/ping_wave.dart';
import 'widgets/power_button.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.onOpenServers,
    required this.onOpenSettings,
  });

  final VoidCallback onOpenServers;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final server = state.selectedServer;
    final status = state.status;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: AppColors.gradient,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        'assets/app_icon.png',
                        width: 38,
                        height: 38,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Affection VPN',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _StatusChip(connected: state.isConnected),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    if (state.availableUpdate != null) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        child: _UpdateBanner(
                          version: state.availableUpdate!.version,
                          onTap: onOpenSettings,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    const SizedBox(height: 18),
                    const PowerButton(size: 210),
                    const SizedBox(height: 22),
                    Text(
                      _statusText(state),
                      style: TextStyle(
                        color: _statusColor(state),
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (server != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        server.displayName,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: state.isConnected
                              ? AppColors.success
                              : AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: state.showIp
                          ? Row(
                              children: [
                                Expanded(
                                  child: _PingCard(
                                    delayMs: server?.delayMs,
                                    connected: state.isConnected,
                                    isMeasuring:
                                        state.measuringIndex ==
                                        state.selectedIndex,
                                    onTap: () => context
                                        .read<AppState>()
                                        .measureServerDelay(
                                          state.selectedIndex,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _IpCard(connected: state.isConnected),
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(
                                  child: _PingCard(
                                    delayMs: server?.delayMs,
                                    connected: state.isConnected,
                                    isMeasuring:
                                        state.measuringIndex ==
                                        state.selectedIndex,
                                    onTap: () => context
                                        .read<AppState>()
                                        .measureServerDelay(
                                          state.selectedIndex,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: const _SpeedtestCard(),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _TrafficRow(status: status),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _SubscriptionBanner(info: state.subscriptionInfo),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusText(AppState state) {
    switch (state.connectionStatus) {
      case ConnectionStatus.connected:
        return 'Подключено';
      case ConnectionStatus.connecting:
        return 'Подключение…';
      case ConnectionStatus.disconnecting:
        return 'Отключение…';
      case ConnectionStatus.disconnected:
        return 'Отключено';
    }
  }

  Color _statusColor(AppState state) {
    switch (state.connectionStatus) {
      case ConnectionStatus.connected:
        return AppColors.success;
      case ConnectionStatus.connecting:
      case ConnectionStatus.disconnecting:
        return AppColors.warning;
      case ConnectionStatus.disconnected:
        return AppColors.textSecondary;
    }
  }
}

class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({required this.version, required this.onTap});

  final String version;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.system_update_alt,
                  color: AppColors.primary,
                  size: 17,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Доступно обновление',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Версия $version · обновить в настройках',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.chevron_right,
                color: AppColors.textTertiary,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (connected ? AppColors.success : AppColors.textTertiary)
            .withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connected ? AppColors.success : AppColors.textTertiary,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            connected ? 'В сети' : 'Офлайн',
            style: TextStyle(
              color: connected ? AppColors.success : AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrafficRow extends StatelessWidget {
  const _TrafficRow({required this.status});

  final dynamic status;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TrafficCard(
            label: 'Загрузка',
            speed: status.downloadSpeed,
            total: status.download,
            icon: Icons.south_west,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _TrafficCard(
            label: 'Отдача',
            speed: status.uploadSpeed,
            total: status.upload,
            icon: Icons.north_east,
            color: AppColors.pink,
          ),
        ),
      ],
    );
  }
}

class _TrafficCard extends StatelessWidget {
  const _TrafficCard({
    required this.label,
    required this.speed,
    required this.total,
    required this.icon,
    required this.color,
  });

  final String label;
  final int speed;
  final int total;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            Formatters.speed(speed),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            Formatters.bytes(total),
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _PingCard extends StatelessWidget {
  const _PingCard({
    required this.delayMs,
    required this.connected,
    required this.isMeasuring,
    required this.onTap,
  });

  final int? delayMs;
  final bool connected;
  final bool isMeasuring;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final measuring = connected && isMeasuring;
    return _StatCard(
      icon: Icons.network_ping,
      label: 'Пинг',
      onTap: connected ? onTap : null,
      child: measuring
          ? const PingWave(size: 20, strokeWidth: 2.2)
          : Text(
              !connected || delayMs == null || delayMs! <= 0 ? '—' : '$delayMs мс',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}

class _IpCard extends StatefulWidget {
  const _IpCard({required this.connected});

  final bool connected;

  @override
  State<_IpCard> createState() => _IpCardState();
}

class _IpCardState extends State<_IpCard> {
  String? _ip;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _IpCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connected != oldWidget.connected) {
      _load();
    }
  }

  Future<void> _load() async {
    if (_loading) {
      return;
    }
    setState(() => _loading = true);
    try {
      final ip = await context.read<AppState>().fetchCurrentIp();
      if (mounted) {
        setState(() => _ip = ip);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _StatCard(
      icon: Icons.language,
      label: 'IP адрес',
      onTap: _load,
      child: _loading
          ? const PingWave(size: 20, strokeWidth: 2.2, color: AppColors.accent)
          : Text(
              _ip ?? '—',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}

class _SpeedtestCard extends StatefulWidget {
  const _SpeedtestCard();

  @override
  State<_SpeedtestCard> createState() => _SpeedtestCardState();
}

class _SpeedtestCardState extends State<_SpeedtestCard> {
  double? _mbps;
  bool _loading = false;

  Future<void> _run() async {
    if (_loading) {
      return;
    }
    setState(() {
      _loading = true;
      _mbps = null;
    });
    try {
      final mbps = await context
          .read<AppState>()
          .measureSpeed(duration: const Duration(seconds: 5));
      if (mounted) {
        setState(() => _mbps = mbps);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Row(
        children: [
          const Icon(Icons.speed, color: AppColors.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Скорость',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _mbps == null
                      ? 'Замер скорости'
                      : '${_mbps!.toStringAsFixed(1)} Мбит/с',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (_loading)
            const PingWave(
              size: 22,
              strokeWidth: 2.2,
              color: AppColors.accent,
            )
          else
            Material(
              color: AppColors.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: _run,
                borderRadius: BorderRadius.circular(10),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Text(
                    'Замерить',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.child,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.accent, size: 15),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(height: 22, child: child),
          ],
        ),
      ),
    );
  }
}

class _SubscriptionBanner extends StatelessWidget {
  const _SubscriptionBanner({required this.info});

  final SubscriptionInfo? info;

  @override
  Widget build(BuildContext context) {
    final info = this.info;
    final hasInfo = info != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.speed,
                color: AppColors.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text(
                'Трафик подписки',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (hasInfo && info.hasTraffic)
                Text(
                  Formatters.percent(info.used, info.total ?? 0),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
            ],
          ),
          if (hasInfo) ...[
            if (info.hasTraffic) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (info.trafficUsedPercent ?? 0) / 100,
                  minHeight: 8,
                  backgroundColor: AppColors.surfaceAlt,
                  valueColor: AlwaysStoppedAnimation(
                    (info.trafficUsedPercent ?? 0) >= 85
                        ? AppColors.danger
                        : AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    info.hasTraffic
                        ? '${Formatters.bytes(info.used)} из '
                            '${Formatters.bytes(info.total ?? 0)}'
                        : 'Использовано ${Formatters.bytes(info.used)}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (info.expireDate != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    'до ${_formatDate(info.expireDate!)}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Информация о трафике недоступна',
                style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final yyyy = local.year;
    return '$dd.$mm.$yyyy';
  }
}
