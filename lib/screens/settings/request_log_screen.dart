import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../services/app_traffic_service.dart';
import '../../services/request_log_service.dart';

enum _LogFilter { all, app, tunnel }

class RequestLogScreen extends StatefulWidget {
  const RequestLogScreen({super.key});

  @override
  State<RequestLogScreen> createState() => _RequestLogScreenState();
}

class _RequestLogScreenState extends State<RequestLogScreen> {
  _LogFilter _filter = _LogFilter.all;

  @override
  void initState() {
    super.initState();
    AppTrafficService.instance.start();
  }

  @override
  void dispose() {
    AppTrafficService.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([
            RequestLogService.instance,
            AppTrafficService.instance,
          ]),
          builder: (context, _) {
            final entries = RequestLogService.instance.entries.where(
              (e) => switch (_filter) {
                _LogFilter.all => true,
                _LogFilter.app => e.kind == RequestLogKind.app,
                _LogFilter.tunnel => e.kind == RequestLogKind.tunnel,
              },
            ).toList();

            final activeApps = AppTrafficService.instance.activeApps;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        tooltip: 'Назад',
                        icon: const Icon(
                          Icons.arrow_back,
                          color: AppColors.textPrimary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Журнал запросов',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      if (entries.isNotEmpty)
                        IconButton(
                          onPressed: () => RequestLogService.instance.clear(),
                          tooltip: 'Очистить',
                          icon: const Icon(
                            Icons.delete_outline,
                            color: AppColors.textSecondary,
                            size: 22,
                          ),
                        ),
                    ],
                  ),
                ),
                if (activeApps.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      'Активные приложения',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 68,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      scrollDirection: Axis.horizontal,
                      itemCount: activeApps.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final app = activeApps[index];
                        return _AppTrafficChip(app: app);
                      },
                    ),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'Все',
                        selected: _filter == _LogFilter.all,
                        onTap: () => setState(() => _filter = _LogFilter.all),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Приложение',
                        selected: _filter == _LogFilter.app,
                        onTap: () =>
                            setState(() => _filter = _LogFilter.app),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Туннель',
                        selected: _filter == _LogFilter.tunnel,
                        onTap: () =>
                            setState(() => _filter = _LogFilter.tunnel),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: entries.isEmpty
                      ? const _EmptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                          itemCount: entries.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) =>
                              _LogEntryCard(entry: entries[index]),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.14)
              : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.primary : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _AppTrafficChip extends StatelessWidget {
  const _AppTrafficChip({required this.app});

  final AppTrafficInfo app;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: app.iconBytes != null
              ? Image.memory(app.iconBytes!, fit: BoxFit.cover)
              : const Icon(
                  Icons.apps,
                  color: AppColors.textSecondary,
                  size: 22,
                ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 60,
          child: Text(
            app.label.length > 8
                ? '${app.label.substring(0, 7)}…'
                : app.label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 1),
        Text(
          '${Formatters.bytes(app.rxBytes)}↓ ${Formatters.bytes(app.txBytes)}↑',
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 8,
          ),
        ),
      ],
    );
  }
}

class _LogEntryCard extends StatelessWidget {
  const _LogEntryCard({required this.entry});

  final RequestLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final isTunnel = entry.kind == RequestLogKind.tunnel;
    final accent = isTunnel ? AppColors.primary : AppColors.accent;

    final details = <String>[
      if (entry.status != null) entry.status!,
      if (entry.durationMs != null) '${entry.durationMs} мс',
      if (entry.bytes != null) Formatters.bytes(entry.bytes!),
      if (entry.error != null) entry.error!,
    ];

    final pkg =
        isTunnel ? AppTrafficService.resolvePackage(entry.target) : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AppIcon(
            packageName: pkg,
            fallbackIcon: isTunnel ? Icons.shield_outlined : Icons.link,
            accent: accent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.target,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  entry.via,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
                if (pkg != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _pkgLabel(pkg),
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                ],
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    details.join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatTime(entry.time),
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  static String _pkgLabel(String pkg) {
    final lastDot = pkg.lastIndexOf('.');
    final name = pkg.substring(lastDot + 1);
    return name[0].toUpperCase() + name.substring(1);
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({
    required this.packageName,
    required this.fallbackIcon,
    required this.accent,
  });

  final String? packageName;
  final IconData fallbackIcon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (packageName == null) {
      return _FallbackIcon(icon: fallbackIcon, accent: accent);
    }

    final apps = AppTrafficService.instance.activeApps;
    final match = apps.where((a) => a.packageName == packageName).firstOrNull;

    if (match?.iconBytes == null) {
      return _FallbackIcon(icon: fallbackIcon, accent: accent);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Image.memory(
        match!.iconBytes!,
        width: 32,
        height: 32,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _FallbackIcon(icon: fallbackIcon, accent: accent),
      ),
    );
  }
}

class _FallbackIcon extends StatelessWidget {
  const _FallbackIcon({required this.icon, required this.accent});

  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, color: accent, size: 16),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.receipt_long,
            color: AppColors.textTertiary,
            size: 40,
          ),
          SizedBox(height: 12),
          Text(
            'Пока нет записей',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Подключитесь к VPN и зайдите на сайт —\nздесь появится запись о запросе',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
