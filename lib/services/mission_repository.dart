import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/mission.dart';

/// Persistence boundary for missions. Everything is stored as JSON.
abstract class MissionRepository {
  Future<List<Mission>> loadAll();
  Future<void> saveAll(List<Mission> missions);
}

/// Stores all missions as one JSON document in local storage
/// (SharedPreferences works on Android, iOS, web and desktop).
class SharedPrefsMissionRepository implements MissionRepository {
  static const String storageKey = 'missions_v1';

  @override
  Future<List<Mission>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return [
        for (final item in decoded['missions'] as List)
          Mission.fromJson(Map<String, dynamic>.from(item as Map)),
      ];
    } on Object {
      // A corrupted store should never stop the app from opening.
      return [];
    }
  }

  @override
  Future<void> saveAll(List<Mission> missions) async {
    final prefs = await SharedPreferences.getInstance();
    final document = {
      'schemaVersion': Mission.schemaVersion,
      'missions': missions.map((m) => m.toJson()).toList(),
    };
    await prefs.setString(storageKey, jsonEncode(document));
  }
}

/// Used by tests.
class InMemoryMissionRepository implements MissionRepository {
  InMemoryMissionRepository([List<Mission>? initial]) : _missions = [...?initial];

  List<Mission> _missions;

  @override
  Future<List<Mission>> loadAll() async => [..._missions];

  @override
  Future<void> saveAll(List<Mission> missions) async => _missions = [...missions];
}
