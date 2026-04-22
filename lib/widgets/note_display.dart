import 'package:flutter/material.dart';
import '../models/note.dart';
import 'common/app_colors.dart';

class NoteDisplay extends StatelessWidget {
  final Note? note;
  final double centsOff;
  final bool pitched;

  const NoteDisplay({
    super.key,
    required this.note,
    required this.centsOff,
    required this.pitched,
  });

  Color get _noteColor {
    if (!pitched || note == null) return AppColors.textSecondary;
    if (centsOff.abs() <= 5) return AppColors.inTune;
    if (centsOff.abs() <= 25) return AppColors.close;
    return AppColors.outOfTune;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 150),
          style: TextStyle(
            fontSize: 96,
            fontWeight: FontWeight.w700,
            color: _noteColor,
            height: 1,
          ),
          child: Text(
            note?.name ?? '-',
          ),
        ),
        if (note != null && pitched)
          Text(
            note!.octave.toString(),
            style: TextStyle(
              fontSize: 28,
              color: _noteColor.withValues(alpha: 0.7),
              fontWeight: FontWeight.w400,
            ),
          ),
      ],
    );
  }
}
