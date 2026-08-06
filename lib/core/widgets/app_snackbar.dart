import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Whether [error] is a connectivity problem the user can fix by checking
/// their network (or retrying).
bool isNetworkError(Object error) =>
    error is SocketException ||
    error is HttpException ||
    error is HandshakeException ||
    error is TimeoutException;

/// Compact bottom sheet snackbar for ordinary users. Never surfaces raw
/// exception text; network failures get a plain, actionable hint instead.
void showErrorSnackBar(
  BuildContext context, {
  required String title,
  Object? error,
}) {
  final network = error != null && isNetworkError(error);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                network ? Icons.wifi_off : Icons.error_outline,
                color: AppColors.danger,
                size: 17,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (network) ...[
                    const SizedBox(height: 2),
                    const Text(
                      'Проверьте подключение к интернету и попробуйте ещё раз',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
}
