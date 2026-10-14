import 'package:flutter/material.dart';

import '../models/status_message.dart';

/// Card showing the latest outcome. Success is only shown once the server
/// has confirmed it.
class SubmissionStatus extends StatelessWidget {
  const SubmissionStatus({super.key, required this.status});

  final StatusMessage status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final (
      Color background,
      Color foreground,
      IconData? icon,
    ) = switch (status.kind) {
      StatusKind.idle => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        Icons.info_outline,
      ),
      StatusKind.working => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        null,
      ),
      StatusKind.success => (
        const Color(0xFFDDF4E4),
        const Color(0xFF0B5A26),
        Icons.check_circle,
      ),
      StatusKind.duplicate => (
        const Color(0xFFFFF1CC),
        const Color(0xFF6B4E00),
        Icons.content_copy,
      ),
      StatusKind.warning => (
        const Color(0xFFFFE5CC),
        const Color(0xFF7A3E00),
        Icons.warning_amber_rounded,
      ),
      StatusKind.error => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.error_outline,
      ),
    };

    return Semantics(
      liveRegion: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox.square(
              dimension: 28,
              child: icon == null
                  ? Padding(
                      padding: const EdgeInsets.all(4),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: foreground,
                      ),
                    )
                  : Icon(icon, color: foreground, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status.title,
                    style: textTheme.titleMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    status.detail,
                    style: textTheme.bodyMedium?.copyWith(color: foreground),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
