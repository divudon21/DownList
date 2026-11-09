import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class UploadScreen extends StatelessWidget {
  const UploadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_upload_outlined,
            size: 64,
            color: colorScheme.onSurfaceVariant,
          ).animate().fadeIn(duration: 600.ms).scale(),
          const SizedBox(height: 16),
          Text(
            'Upload',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ).animate().fadeIn(duration: 700.ms),
          const SizedBox(height: 8),
          Text(
            'Upload functionality is intentionally left empty for now.',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
            ),
          ).animate().fadeIn(duration: 800.ms),
        ],
      ),
    );
  }
}
