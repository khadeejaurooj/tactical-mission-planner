import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import 'models/mission.dart';
import 'services/mission_repository.dart';
import 'viewmodels/mission_view_model.dart';
import 'views/home_page.dart';

Future<Mission> _loadSampleMission() async {
  final raw = await rootBundle.loadString('assets/sample_mission.json');
  return Mission.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

void main() {
  runApp(const MissionPlannerApp());
}

class MissionPlannerApp extends StatelessWidget {
  const MissionPlannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MissionViewModel(
        repository: SharedPrefsMissionRepository(),
        sampleLoader: _loadSampleMission,
      )..init(),
      child: MaterialApp(
        title: 'Tactical Navigation & Mission Planning',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF00BFA5),
            brightness: Brightness.dark,
          ),
        ),
        home: const HomePage(),
      ),
    );
  }
}
