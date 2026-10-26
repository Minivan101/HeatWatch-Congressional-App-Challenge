import 'package:flutter/material.dart';

class DataStatus extends StatelessWidget {
  const DataStatus({
    super.key,
    required this.message,
    this.loading = false,
    this.failed = false,
    this.saved = false,
    this.onRetry,
  });
  final String message;
  final bool loading, failed, saved;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: failed
            ? Theme.of(context).colorScheme.errorContainer
            : Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                loading
                    ? Icons.sync
                    : failed
                    ? Icons.cloud_off_outlined
                    : saved
                    ? Icons.offline_pin_outlined
                    : Icons.info_outline,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
          if (onRetry != null && !loading)
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry check'),
            ),
        ],
      ),
    ),
  );
}
