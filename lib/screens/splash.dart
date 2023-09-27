import 'package:flutter/material.dart';

import 'package:viap_radio/utils/assets.dart';
import 'package:viap_radio/utils/router.dart';
import 'package:viap_radio/utils/theme.dart';

import 'dart:async';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();

    Future.delayed(
      const Duration(seconds: 2),
          () => Navigator.pushReplacementNamed(context, AppRouter.homeRoute),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Ink(
        decoration: BoxDecoration(
          gradient: MusicPlayerTheme().linearGradientBody,
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Image(image: AssetImage('assets/logo.png'), width: 200, height: 200),
            Text(
              'VIAP',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}