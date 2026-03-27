import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/dicom_formatters.dart';
import '../../domain/entities/dicom_models.dart';

class SeriesCard extends StatefulWidget {
  const SeriesCard({
    super.key,
    required this.series,
    required this.thumbnailBytes,
    required this.isSelected,
    required this.isLoading,
    required this.onTap,
    this.loadProgress,
  });

  final DicomSeries series;
  final Uint8List? thumbnailBytes;
  final bool isSelected;
  final bool isLoading;
  final double? loadProgress;
  final VoidCallback onTap;

  @override
  State<SeriesCard> createState() => _SeriesCardState();
}

class _SeriesCardState extends State<SeriesCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.01 : 1,
        duration: const Duration(milliseconds: 180),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: widget.isSelected
                  ? AppTheme.accent.withValues(alpha: 0.14)
                  : AppTheme.onSurface.withValues(
                      alpha: _hovered ? 0.08 : 0.04,
                    ),
              border: Border.all(
                color: widget.isSelected
                    ? AppTheme.accent.withValues(alpha: 0.55)
                    : AppTheme.onSurface.withValues(alpha: 0.08),
              ),
            ),
            child: Column(
              children: [
                if (widget.isLoading)
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(18),
                    ),
                    child: LinearProgressIndicator(
                      value: widget.loadProgress,
                      minHeight: 2,
                      backgroundColor: AppTheme.onSurface.withValues(alpha: 0.04),
                      color: AppTheme.accent.withValues(alpha: 0.6),
                    ),
                  ),
                Row(
                  children: [
                    _SeriesThumbnail(
                      bytes: widget.thumbnailBytes,
                      modality: widget.series.modality,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.series.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            compactFileCount(widget.series.instances.length),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.onSurface.withValues(alpha: 0.85),
                            ),
                          ),
                          if (widget.isLoading && widget.loadProgress != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${(widget.loadProgress! * widget.series.instances.length).round()}/${widget.series.instances.length} loaded',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppTheme.accent.withValues(alpha: 0.8),
                                ),
                              ),
                            ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _SeriesChip(label: widget.series.modality),
                              if (widget.series.leadInstance.rows != null &&
                                  widget.series.leadInstance.columns != null)
                                _SeriesChip(
                                  label:
                                      '${widget.series.leadInstance.columns} x ${widget.series.leadInstance.rows}',
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SeriesThumbnail extends StatelessWidget {
  const _SeriesThumbnail({required this.bytes, required this.modality});

  final Uint8List? bytes;
  final String modality;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.onSurface.withValues(alpha: 0.1),
            AppTheme.onSurface.withValues(alpha: 0.03),
          ],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: bytes != null && bytes!.isNotEmpty
          ? Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  bytes!,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.0),
                        Colors.black.withValues(alpha: 0.35),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      modality,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
              ],
            )
          : Stack(
              children: [
                Center(
                  child: Text(
                    modality,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                for (var index = 0; index < 5; index++)
                  Positioned(
                    left: 12 + (index * 9),
                    bottom: 12,
                    child: Container(
                      width: 4,
                      height: 16 + (index * 6),
                      decoration: BoxDecoration(
                        color: AppTheme.highlight.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _SeriesChip extends StatelessWidget {
  const _SeriesChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: AppTheme.onSurface.withValues(alpha: 0.06),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}
