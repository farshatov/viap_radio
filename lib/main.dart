import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:viap_radio/screens/splash.dart';
import 'package:viap_radio/utils/router.dart';

void main() async {
  await Hive.initFlutter();
  await Hive.openBox("viap");

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'VIAP',
      home: const SplashPage(),
      onGenerateRoute: (settings) => AppRouter.generateRoute(settings),
    );
  }
}