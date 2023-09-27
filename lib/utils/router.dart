import 'package:flutter/material.dart';

import 'package:viap_radio/screens/splash.dart';
import 'package:viap_radio/screens/home.dart';

class AppRouter {
  static const String splashRoute = '/';
  static const String homeRoute = '/home';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splashRoute:
        return MaterialPageRoute<dynamic>(
          builder: (_) => const SplashPage(),
        );
      case homeRoute:
        return MaterialPageRoute<dynamic>(
          builder: (_) => const HomePage(),
        );
      default:
        return MaterialPageRoute<dynamic>(
          builder: (_) => const SplashPage(),
        );
    }
  }
}