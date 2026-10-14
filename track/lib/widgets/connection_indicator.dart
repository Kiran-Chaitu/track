import 'package:flutter/material.dart';

import '../models/registration_result.dart';

/// Small app-bar chip showing whether the backend is reachable.
class ConnectionIndicator extends StatelessWidget {
  const ConnectionIndicator({
    super.key,
    required this.health,
    required this.onRefresh,
  });

  final BackendHealth health;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final (String label, Color color) = switch (health) {
      BackendHealth.checking => ('Checking', Colors.grey),
      BackendHealth.online => ('Online', const Color(0xFF1B8A3F)),
      BackendHealth.storageIssue => ('Storage issue', const Color(0xFFB07D00)),
      BackendHealth.offline => ('Offline', Theme.of(context).colorScheme.error),
      BackendHealth.notConfigured => (
        'Not configured',
        Theme.of(context).colorScheme.error,
      ),
    };

    return Tooltip(
      message: 'Server status: $label. Tap to re-check.',
      child: ActionChip(
        onPressed: onRefresh,
        avatar: Icon(Icons.circle, size: 12, color: color),
        label: Text(label),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
