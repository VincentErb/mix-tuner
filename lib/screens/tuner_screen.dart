import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/note.dart';
import '../models/tuning.dart';
import '../models/instrument_preset.dart';
import '../providers/audio_provider.dart';
import '../providers/tuning_provider.dart';
import '../providers/string_provider.dart';
import '../services/string_tracker.dart';
import '../widgets/tuning_meter.dart';
import '../widgets/note_display.dart';
import '../widgets/string_selector.dart';
import '../widgets/permission_gate.dart';
import '../widgets/common/app_colors.dart';

class TunerScreen extends ConsumerStatefulWidget {
  const TunerScreen({super.key});

  @override
  ConsumerState<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends ConsumerState<TunerScreen> {
  final StringTracker _tracker = StringTracker();
  String? _lastTuningName;

  @override
  Widget build(BuildContext context) {
    final pitchAsync = ref.watch(pitchStreamProvider);
    final tuning = ref.watch(tuningProvider);
    final selectedString = ref.watch(selectedStringIndexProvider);

    // Reset tracker when the tuning changes.
    if (_lastTuningName != tuning.name) {
      _tracker.reset();
      _lastTuningName = tuning.name;
    }

    final isAutoMode = selectedString == -1;

    return Container(
      color: AppColors.background,
      child: pitchAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.inTune),
        ),
        error: (e, _) => Center(
          child: Text('Error: $e',
              style: const TextStyle(color: AppColors.outOfTune)),
        ),
        data: (pitchResult) {
          if (pitchResult == null) {
            return const PermissionGate();
          }

          // Update tracker every frame; pass 0 on silence.
          final autoIdx = _tracker.update(
            pitchResult.pitched ? pitchResult.frequencyHz : 0,
            tuning.strings,
          );
          final activeIdx = isAutoMode ? autoIdx : selectedString;
          final targetNote =
              activeIdx != null ? tuning.strings[activeIdx] : null;

          double displayCents = pitchResult.centsOff;
          Note? displayNote = pitchResult.nearestNote;
          bool isInTune = false;

          if (pitchResult.pitched && targetNote != null) {
            final targetFreq = targetNote.frequency;
            double rawCents =
                1200 * log(pitchResult.frequencyHz / targetFreq) / ln2;
            // Octave-snap: if the detected pitch is ≈ an octave away from the
            // target (e.g. guitalele A2 detected as A3), fold it back so the
            // meter reads the correct deviation rather than ±1200 ¢.
            while (rawCents > 600) { rawCents -= 1200; }
            while (rawCents < -600) { rawCents += 1200; }
            displayCents = rawCents.clamp(-60.0, 60.0);
            displayNote = targetNote;
            isInTune = displayCents.abs() <= 10;
          }

          return SafeArea(
            child: Column(
              children: [
                // ── Header row: tuning name + AUTO/MANUAL toggle ──────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _InstrumentPicker(
                        current: tuning,
                        allTunings: [
                          ...InstrumentPresets.all,
                          ...ref.read(tuningProvider.notifier).getCustomTunings(),
                        ],
                        onSelect: (t) {
                          ref.read(tuningProvider.notifier).selectTuning(t);
                          ref.read(selectedStringIndexProvider.notifier).state = -1;
                        },
                      ),
                      _ModeToggle(
                        isAuto: isAutoMode,
                        onToggle: (wantsAuto) {
                          if (wantsAuto) {
                            ref
                                .read(selectedStringIndexProvider.notifier)
                                .state = -1;
                          } else {
                            // Lock to the currently highlighted string.
                            ref
                                .read(selectedStringIndexProvider.notifier)
                                .state = autoIdx ?? 0;
                          }
                        },
                      ),
                    ],
                  ),
                ),

                // ── Target string label ───────────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    targetNote?.displayName ?? '',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 18,
                    ),
                  ),
                ),

                // ── Detected note ─────────────────────────────────────────
                Expanded(
                  flex: 3,
                  child: Center(
                    child: NoteDisplay(
                      note: pitchResult.pitched ? displayNote : null,
                      centsOff: displayCents,
                      pitched: pitchResult.pitched,
                    ),
                  ),
                ),

                // ── Arc meter ─────────────────────────────────────────────
                SizedBox(
                  height: 180,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TuningMeter(
                      centsOff: pitchResult.pitched ? displayCents : 0,
                      pitched: pitchResult.pitched,
                    ),
                  ),
                ),

                // ── Cents readout ─────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    pitchResult.pitched
                        ? '${displayCents >= 0 ? '+' : ''}${displayCents.toStringAsFixed(0)} ¢'
                        : '',
                    style: TextStyle(
                      color:
                          isInTune ? AppColors.inTune : AppColors.textSecondary,
                      fontSize: 16,
                    ),
                  ),
                ),

                // ── In-tune indicator bar ─────────────────────────────────
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 4,
                  width: isInTune ? 80 : 0,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.inTune,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // ── String selector ───────────────────────────────────────
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: StringSelector(
                    strings: tuning.strings,
                    selectedIndex: selectedString,
                    // In manual mode don't show the auto-glow; user owns the
                    // selection explicitly.
                    autoDetectedIndex: isAutoMode ? autoIdx : null,
                    onStringTap: (idx) {
                      // Tapping any string in either mode locks to that string
                      // (manual mode). The toggle is the way back to auto.
                      ref.read(selectedStringIndexProvider.notifier).state =
                          idx;
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Tappable tuning name label that pops up a quick instrument switcher.
class _InstrumentPicker extends StatelessWidget {
  final Tuning current;
  final List<Tuning> allTunings;
  final ValueChanged<Tuning> onSelect;

  const _InstrumentPicker({
    required this.current,
    required this.allTunings,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Tuning>(
      onSelected: onSelect,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.divider),
      ),
      itemBuilder: (_) => allTunings
          .map(
            (t) => PopupMenuItem<Tuning>(
              value: t,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t.name,
                      style: TextStyle(
                        color: t.name == current.name
                            ? AppColors.inTune
                            : AppColors.textPrimary,
                        fontWeight: t.name == current.name
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (t.name == current.name)
                    const Icon(Icons.check, color: AppColors.inTune, size: 16),
                ],
              ),
            ),
          )
          .toList(),
      // The visible "button" — styled like a label with a chevron
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            current.name.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 2),
          const Icon(
            Icons.arrow_drop_down,
            color: AppColors.textSecondary,
            size: 18,
          ),
        ],
      ),
    );
  }
}

/// Pill-shaped AUTO / MANUAL toggle.
class _ModeToggle extends StatelessWidget {
  final bool isAuto;
  final ValueChanged<bool> onToggle;

  const _ModeToggle({required this.isAuto, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onToggle(!isAuto),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.divider),
        ),
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Pill(label: 'AUTO', active: isAuto),
            const SizedBox(width: 2),
            _Pill(label: 'MANUAL', active: !isAuto),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool active;

  const _Pill({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active ? AppColors.inTune.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? AppColors.inTune : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? AppColors.inTune : AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
