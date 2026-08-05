import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/server_config.dart';

class ServerCard extends StatelessWidget {
  const ServerCard({
    super.key,
    required this.server,
    this.selected = false,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.pingMethod = 'tcp',
  });

  final ServerConfig? server;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final String pingMethod;

  @override
  Widget build(BuildContext context) {
    final item = server;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.borderSoft,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              _FlagBadge(server: item),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item?.displayName ?? 'Сервер',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item == null ? 'Не выбран' : item.protocol,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _DelayBadge(delayMs: item?.delayMs, pingMethod: pingMethod),
              const SizedBox(width: 8),
              if (trailing != null)
                trailing!
              else
                Icon(
                  selected
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  color:
                      selected ? AppColors.primary : AppColors.textTertiary,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlagBadge extends StatelessWidget {
  const _FlagBadge({required this.server});

  final ServerConfig? server;

  @override
  Widget build(BuildContext context) {
    final item = server;
    final hasFlag = item?.hasFlag ?? false;
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: hasFlag
          ? Text(
              _flagEmoji(item!.countryCode),
              style: const TextStyle(fontSize: 22),
            )
          : const Icon(
              Icons.public,
              color: AppColors.textSecondary,
              size: 22,
            ),
    );
  }

  String _flagEmoji(String code) {
    return code.toUpperCase().codeUnits.map((c) {
      return String.fromCharCode(0x1F1E6 + c - 0x41);
    }).join();
  }
}

class _DelayBadge extends StatelessWidget {
  const _DelayBadge({required this.delayMs, required this.pingMethod});

  final int? delayMs;
  final String pingMethod;

  @override
  Widget build(BuildContext context) {
    if (delayMs == null || delayMs! <= 0) {
      return const Text(
        'н/д',
        style: TextStyle(
          color: AppColors.textTertiary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    // HTTP GET measures the full tunnel path, so its healthy range is wider.
    final isHttpGet = pingMethod == 'get';
    final color = isHttpGet
        ? delayMs! <= 600
            ? AppColors.success
            : delayMs! <= 1200
                ? AppColors.warning
                : AppColors.danger
        : delayMs! < 150
            ? AppColors.success
            : delayMs! < 350
                ? AppColors.warning
                : AppColors.danger;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '$delayMs',
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          'мс',
          style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 9),
        ),
      ],
    );
  }
}
