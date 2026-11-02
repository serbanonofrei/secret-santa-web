import 'package:flutter/material.dart';

import '../../data/models/color_info.dart';

/// Parses `#RRGGBB` / `RRGGBB` (optionally `#AARRGGBB`). Returns null if invalid.
Color? parseHexColor(String hex) {
  var value = hex.trim();
  if (value.startsWith('#')) value = value.substring(1);
  if (value.length == 6) value = 'FF$value';
  if (value.length != 8) return null;
  final parsed = int.tryParse(value, radix: 16);
  return parsed == null ? null : Color(parsed);
}

/// A labelled color: swatch + name + hex value.
///
/// Accessibility: the color is never the only information. Name and hex are
/// always shown as text, and screen readers get one combined label.
class ColorSwatchCard extends StatelessWidget {
  const ColorSwatchCard({super.key, required this.label, required this.color});

  /// e.g. "Your color", "Buy a gift for".
  final String label;
  final ColorInfo color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final swatch = parseHexColor(color.hexColor);

    return Semantics(
      container: true,
      label: '$label: ${color.name}, ${color.hexColor}',
      child: ExcludeSemantics(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: swatch ?? theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    // Border keeps very light / very dark colors visible on any theme.
                    border: Border.all(color: theme.colorScheme.outline, width: 2),
                  ),
                  child: swatch == null ? const Icon(Icons.help_outline) : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: theme.textTheme.labelLarge),
                      const SizedBox(height: 4),
                      Text(color.name, style: theme.textTheme.headlineSmall),
                      Text(color.hexColor, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
