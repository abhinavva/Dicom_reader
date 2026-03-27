import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass_panel.dart';

class ViewerEmptyState extends StatelessWidget {
  const ViewerEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: GlassPanel(
          padding: const EdgeInsets.all(28),
          color: AppTheme.glassEmpty,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.accent.withValues(alpha: 0.9),
                      AppTheme.highlight.withValues(alpha: 0.6),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.monitor_heart_rounded,
                  size: 42,
                  color: AppTheme.background,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'No active viewer session',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Open a study from the worklist or use the top-right icons to load local files/folders.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppTheme.onSurface.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
