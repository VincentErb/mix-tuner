import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Index of the currently selected string (0 = lowest string).
/// -1 means auto-detect mode (highlight closest string automatically).
final selectedStringIndexProvider = StateProvider<int>((ref) => -1);
