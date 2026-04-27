import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/tuning.dart';
import '../models/instrument_preset.dart';
import 'persistence_provider.dart';

const _selectedTuningKey = 'selected_tuning';
const _customTuningsKey = 'custom_tunings_list';

class TuningNotifier extends StateNotifier<Tuning> {
  TuningNotifier(this._prefs) : super(_loadSelected(_prefs));

  final SharedPreferences _prefs;

  static Tuning _loadSelected(SharedPreferences prefs) {
    final saved = prefs.getString(_selectedTuningKey);
    if (saved == null) return InstrumentPresets.standardGuitar;
    try {
      return Tuning.fromJsonString(saved);
    } catch (_) {
      return InstrumentPresets.standardGuitar;
    }
  }

  void selectTuning(Tuning tuning) {
    state = tuning;
    _prefs.setString(_selectedTuningKey, tuning.toJsonString());
  }

  List<Tuning> getCustomTunings() {
    final raw = _prefs.getString(_customTuningsKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Tuning.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void saveCustomTuning(Tuning tuning) {
    final customs = getCustomTunings();
    final existing = customs.indexWhere((t) => t.name == tuning.name);
    if (existing >= 0) {
      customs[existing] = tuning;
    } else {
      customs.add(tuning);
    }
    _prefs.setString(
      _customTuningsKey,
      jsonEncode(customs.map((t) => t.toJson()).toList()),
    );
    selectTuning(tuning);
  }

  void deleteCustomTuning(String name) {
    final customs = getCustomTunings()..removeWhere((t) => t.name == name);
    _prefs.setString(
      _customTuningsKey,
      jsonEncode(customs.map((t) => t.toJson()).toList()),
    );
    if (state.name == name) {
      selectTuning(InstrumentPresets.standardGuitar);
    }
  }
}

final tuningProvider = StateNotifierProvider<TuningNotifier, Tuning>((ref) {
  return TuningNotifier(ref.watch(sharedPreferencesProvider));
});
