import 'dart:convert';
import 'note.dart';

class Tuning {
  final String name;
  final List<Note> strings; // ordered low-to-high
  final bool isCustom;

  const Tuning({
    required this.name,
    required this.strings,
    this.isCustom = false,
  });

  Tuning copyWith({String? name, List<Note>? strings, bool? isCustom}) {
    return Tuning(
      name: name ?? this.name,
      strings: strings ?? this.strings,
      isCustom: isCustom ?? this.isCustom,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'isCustom': isCustom,
    'strings': strings.map((n) => n.toJson()).toList(),
  };

  factory Tuning.fromJson(Map<String, dynamic> json) => Tuning(
    name: json['name'] as String,
    isCustom: (json['isCustom'] as bool?) ?? false,
    strings: (json['strings'] as List)
        .map((e) => Note.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  String toJsonString() => jsonEncode(toJson());
  factory Tuning.fromJsonString(String s) => Tuning.fromJson(jsonDecode(s));

  @override
  bool operator ==(Object other) =>
      other is Tuning && other.name == name && other.isCustom == isCustom;

  @override
  int get hashCode => Object.hash(name, isCustom);
}
