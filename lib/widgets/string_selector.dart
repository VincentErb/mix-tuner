import 'package:flutter/material.dart';
import '../models/note.dart';
import 'common/app_colors.dart';

class StringSelector extends StatelessWidget {
  final List<Note> strings;
  final int selectedIndex; // -1 = auto-detect
  final int? autoDetectedIndex;
  final ValueChanged<int> onStringTap;

  const StringSelector({
    super.key,
    required this.strings,
    required this.selectedIndex,
    required this.autoDetectedIndex,
    required this.onStringTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveSelected =
        selectedIndex == -1 ? autoDetectedIndex : selectedIndex;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(strings.length, (i) {
        final isSelected = effectiveSelected == i;
        return GestureDetector(
          onTap: () => onStringTap(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected
                  ? AppColors.inTune.withValues(alpha: 0.2)
                  : AppColors.surfaceVariant,
              border: Border.all(
                color: isSelected
                    ? AppColors.inTune
                    : AppColors.divider,
                width: isSelected ? 2.5 : 1.5,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    strings[i].name,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.inTune
                          : AppColors.textPrimary,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    strings[i].octave.toString(),
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.inTune.withValues(alpha: 0.8)
                          : AppColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}
