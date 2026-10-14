import 'package:flutter/material.dart';

import '../models/registration_result.dart';
import '../models/scan_record.dart';

/// Compact list of this session's submissions (kept in memory only).
class RecentScansList extends StatelessWidget {
  const RecentScansList({
    super.key,
    required this.records,
    required this.onClear,
  });

  final List<ScanRecord> records;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent (this session)',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (records.isNotEmpty)
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Clear'),
              ),
          ],
        ),
        Text(
          'Only shows submissions from this device since the app opened.',
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (records.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No submissions yet.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium,
            ),
          )
        else
          Card.outlined(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < records.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _RecentTile(record: records[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.record});

  final ScanRecord record;

  @override
  Widget build(BuildContext context) {
    final (String label, Color color, IconData icon) = switch (record.status) {
      RegistrationStatus.stored => (
        'New',
        const Color(0xFF1B8A3F),
        Icons.check_circle,
      ),
      RegistrationStatus.duplicate => (
        'Duplicate',
        const Color(0xFFB07D00),
        Icons.content_copy,
      ),
      _ => ('Failed', Theme.of(context).colorScheme.error, Icons.error_outline),
    };

    return ListTile(
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(
        record.registrationNumber,
        style: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 1),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${record.source == SubmissionSource.qr ? 'QR scan' : 'Manual'}'
        ' · ${_formatTime(record.timestamp)}',
      ),
      trailing: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  static String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}
