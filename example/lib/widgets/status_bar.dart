import 'package:flutter/material.dart';
import 'package:flutter_mind_local_example/constants/enum.dart';

class StatusBar extends StatelessWidget {
  const StatusBar({super.key, required this.status});
  final Status status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      Status.loading => const LinearProgressIndicator(),
      Status.thinking => LinearProgressIndicator(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
      _ => const SizedBox.shrink(),
    };
  }
}
