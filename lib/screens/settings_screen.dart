import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/note.dart';
import '../models/tuning.dart';
import '../models/instrument_preset.dart';
import '../providers/tuning_provider.dart';
import '../widgets/common/app_colors.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _noteNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
  ];

  final _customNameController = TextEditingController(text: 'My Tuning');
  // Custom string count and notes (default to standard guitar)
  int _stringCount = 6;
  late List<String> _customNoteNames;
  late List<int> _customOctaves;

  @override
  void initState() {
    super.initState();
    _initCustomFromPreset(InstrumentPresets.standardGuitar);
  }

  void _initCustomFromPreset(Tuning tuning) {
    _stringCount = tuning.strings.length;
    _customNoteNames = tuning.strings.map((n) => n.name).toList();
    _customOctaves = tuning.strings.map((n) => n.octave).toList();
  }

  @override
  void dispose() {
    _customNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentTuning = ref.watch(tuningProvider);
    final notifier = ref.read(tuningProvider.notifier);
    final customTunings = notifier.getCustomTunings();
    final allTunings = [...InstrumentPresets.all, ...customTunings];

    return SafeArea(
      child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'INSTRUMENT PRESETS',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
            ),

            // Preset tiles
            ...allTunings.map((tuning) => _TuningTile(
              tuning: tuning,
              isSelected: currentTuning.name == tuning.name,
              onTap: () => notifier.selectTuning(tuning),
              onDelete: tuning.isCustom
                  ? () => notifier.deleteCustomTuning(tuning.name)
                  : null,
            )),

            const SizedBox(height: 24),

            // Custom tuning editor
            _buildCustomEditor(notifier),
          ],
        ),
    );
  }

  Widget _buildCustomEditor(TuningNotifier notifier) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CUSTOM TUNING',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),

          // Tuning name
          TextField(
            controller: _customNameController,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Tuning Name',
              labelStyle: TextStyle(color: AppColors.textSecondary),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.divider),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.inTune),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // String count
          Row(
            children: [
              const Text('Strings:', style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(width: 16),
              ...List.generate(4, (i) => i + 4).map((count) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() {
                    _stringCount = count;
                    // Extend or truncate lists
                    while (_customNoteNames.length < count) {
                      _customNoteNames.add('E');
                      _customOctaves.add(2);
                    }
                    _customNoteNames = _customNoteNames.take(count).toList();
                    _customOctaves = _customOctaves.take(count).toList();
                  }),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _stringCount == count
                          ? AppColors.inTune.withValues(alpha: 0.2)
                          : AppColors.surfaceVariant,
                      border: Border.all(
                        color: _stringCount == count
                            ? AppColors.inTune
                            : AppColors.divider,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$count',
                        style: TextStyle(
                          color: _stringCount == count
                              ? AppColors.inTune
                              : AppColors.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              )),
            ],
          ),
          const SizedBox(height: 16),

          // String pickers
          const Text(
            'Strings (low → high)',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 8),
          ...List.generate(_stringCount, (i) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Text(
                  'String ${i + 1}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(width: 16),
                // Note name dropdown
                DropdownButton<String>(
                  value: _customNoteNames[i],
                  dropdownColor: AppColors.surface,
                  style: const TextStyle(color: AppColors.textPrimary),
                  underline: Container(height: 1, color: AppColors.divider),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _customNoteNames[i] = val);
                    }
                  },
                  items: _noteNames
                      .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                      .toList(),
                ),
                const SizedBox(width: 16),
                // Octave dropdown
                DropdownButton<int>(
                  value: _customOctaves[i],
                  dropdownColor: AppColors.surface,
                  style: const TextStyle(color: AppColors.textPrimary),
                  underline: Container(height: 1, color: AppColors.divider),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _customOctaves[i] = val);
                    }
                  },
                  items: List.generate(8, (o) => o)
                      .map((o) => DropdownMenuItem(value: o, child: Text('$o')))
                      .toList(),
                ),
              ],
            ),
          )),

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                final name = _customNameController.text.trim();
                if (name.isEmpty) return;
                final strings = List.generate(
                  _stringCount,
                  (i) => Note.fromNameOctave(_customNoteNames[i], _customOctaves[i]),
                );
                final tuning = Tuning(
                  name: name,
                  strings: strings,
                  isCustom: true,
                );
                notifier.saveCustomTuning(tuning);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Saved "$name"'),
                    backgroundColor: AppColors.inTune,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.inTune,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Save Custom Tuning',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

class _TuningTile extends StatelessWidget {
  final Tuning tuning;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _TuningTile({
    required this.tuning,
    required this.isSelected,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.inTune.withValues(alpha: 0.1)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? AppColors.inTune : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        title: Text(
          tuning.name,
          style: TextStyle(
            color: isSelected ? AppColors.inTune : AppColors.textPrimary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        subtitle: Text(
          tuning.strings.map((n) => n.displayName).join(' – '),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected)
              const Icon(Icons.check_circle, color: AppColors.inTune, size: 20),
            if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.textSecondary),
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ],
        ),
      ),
    );
  }
}
