import 'package:flutter/material.dart';

/// Temporary screen for routes whose real UI arrives in a later phase.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title, required this.phase});

  final String title;
  final String phase;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text('$title\n(coming in $phase)', textAlign: TextAlign.center),
      ),
    );
  }
}
