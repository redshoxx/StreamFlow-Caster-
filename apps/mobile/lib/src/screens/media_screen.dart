import 'package:flutter/material.dart';

class MediaScreen extends StatelessWidget {
  const MediaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Erkannte Medien erscheinen aktuell direkt im Browser. Persistente Medienliste folgt in 0.2.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
