import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../state/app_state.dart';

class UpdateSection extends StatefulWidget {
  const UpdateSection({super.key});

  @override
  State<UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends State<UpdateSection> {
  bool _checked = false;

  Future<void> _check() async {
    final state = context.read<AppState>();
    try {
      final found = await state.checkForUpdates();
      if (!mounted) {
        return;
      }
      setState(() => _checked = !found);
      if (!found) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('У вас установлена актуальная версия')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _checked = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось проверить обновления: $e')),
        );
      }
    }
  }

  Future<void> _download() async {
    final state = context.read<AppState>();
    try {
      await state.downloadUpdate();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: $e')),
        );
      }
    }
  }

  Future<void> _install() async {
    final state = context.read<AppState>();
    try {
      await state.installUpdate();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final update = state.availableUpdate;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        children: [
          if (state.isCheckingUpdate)
            const _CheckRow(active: true)
          else if (update != null)
            _UpdateAvailable(
              update: update,
              isDownloading: state.isDownloadingUpdate,
              progress: state.downloadProgress,
              downloaded: state.downloadedApkPath != null,
              onDownload: _download,
              onInstall: _install,
              onDismiss: state.dismissUpdate,
            )
          else
            _CheckRow(
              active: false,
              checked: _checked,
              currentVersion: state.currentVersion,
              onPressed: _check,
            ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.active,
    this.checked = false,
    this.currentVersion,
    this.onPressed,
  });

  final bool active;
  final bool checked;
  final String? currentVersion;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (active) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text(
              'Проверка обновлений…',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(
            Icons.system_update_alt,
            color: AppColors.primary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  checked ? 'Актуальная версия' : 'Обновление',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  checked
                      ? 'У вас версия $currentVersion'
                      : 'Проверяйте обновления приложения',
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          _ActionButton(
            label: 'Проверить',
            icon: Icons.refresh,
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}

class _UpdateAvailable extends StatelessWidget {
  const _UpdateAvailable({
    required this.update,
    required this.isDownloading,
    required this.progress,
    required this.downloaded,
    required this.onDownload,
    required this.onInstall,
    required this.onDismiss,
  });

  final dynamic update;
  final bool isDownloading;
  final double? progress;
  final bool downloaded;
  final VoidCallback onDownload;
  final VoidCallback onInstall;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final version = update.version as String;
    final size = update.size as int?;
    final changelog = update.changelog as String?;
    final publishedAt = update.publishedAt as DateTime?;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.system_update_alt,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Доступна версия $version',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      publishedAt != null
                          ? 'Опубликовано ${_formatDate(publishedAt)}'
                          : 'Доступно новое обновление',
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: isDownloading ? null : onDismiss,
                icon: const Icon(
                  Icons.close,
                  color: AppColors.textTertiary,
                  size: 18,
                ),
              ),
            ],
          ),
          if (changelog != null && changelog.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                changelog.trim(),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (isDownloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: AppColors.surfaceAlt,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _progressText(progress, size),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ] else
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: downloaded ? 'Установить' : 'Скачать',
                    icon: downloaded
                        ? Icons.install_desktop
                        : Icons.download,
                    filled: true,
                    onPressed: downloaded ? onInstall : onDownload,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _progressText(double? progress, int? size) {
    final percent = ((progress ?? 0) * 100).clamp(0, 100).round();
    if (size != null && size > 0) {
      return 'Скачано $percent% из ${Formatters.bytes(size)}';
    }
    return 'Скачано $percent%';
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final yyyy = local.year;
    return '$dd.$mm.$yyyy';
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        backgroundColor: AppColors.surfaceAlt,
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
