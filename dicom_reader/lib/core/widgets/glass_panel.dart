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
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            color: color ?? AppTheme.onSurface.withValues(alpha: 0.06),
            border: Border.all(
              color: AppTheme.onSurface.withValues(alpha: 0.08),
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.onSurface.withValues(alpha: 0.05),
                Colors.transparent,
              ],
            ),
            boxShadow: [
              BoxShadow(
                blurRadius: 40,
                spreadRadius: -16,
                color: Colors.black.withValues(alpha: 0.5),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
