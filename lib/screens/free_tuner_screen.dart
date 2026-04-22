import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/audio_provider.dart';
import '../widgets/note_display.dart';
import '../widgets/tuning_meter.dart';
import '../widgets/permission_gate.dart';
import '../widgets/common/app_colors.dart';

class FreeTunerScreen extends ConsumerWidget {
  const FreeTunerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pitchAsync = ref.watch(pitchStreamProvider);

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

          final hz = pitchResult.frequencyHz;
          final hzText =
              pitchResult.pitched ? '${hz.toStringAsFixed(1)} Hz' : '— Hz';

          return SafeArea(
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    'FREE TUNER',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    hzText,
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w300,
                      color: pitchResult.pitched
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Center(
                    child: NoteDisplay(
                      note: pitchResult.nearestNote,
                      centsOff: pitchResult.centsOff,
                      pitched: pitchResult.pitched,
                    ),
                  ),
                ),
                SizedBox(
                  height: 180,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TuningMeter(
                      centsOff: pitchResult.pitched ? pitchResult.centsOff : 0,
                      pitched: pitchResult.pitched,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 24),
                  child: Text(
                    pitchResult.pitched
                        ? '${pitchResult.centsOff >= 0 ? '+' : ''}${pitchResult.centsOff.toStringAsFixed(0)} ¢'
                        : '',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }
}
