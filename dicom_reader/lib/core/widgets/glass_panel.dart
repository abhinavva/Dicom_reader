import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            color: color ?? AppTheme.onSurface.withValues(alpha: 0.08),
            border: Border.all(color: AppTheme.onSurface.withValues(alpha: 0.1)),
            boxShadow: [
              BoxShadow(
                blurRadius: 32,
                spreadRadius: -14,
                color: Colors.black.withValues(alpha: 0.48),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
