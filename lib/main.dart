import 'package:flutter/material.dart';

import 'package:antenna_aligner/screens/alignment_screen.dart';
import 'package:antenna_aligner/screens/ap_manager_screen.dart';
import 'package:antenna_aligner/screens/home_screen.dart';
import 'package:antenna_aligner/screens/settings_screen.dart';
import 'package:antenna_aligner/utils/constants.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Constants.appName,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const HomeScreen(),
        '/ap_manager': (context) => const APManagerScreen(),
        '/alignment': (context) => const AlignmentScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}
