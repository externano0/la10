import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// Placeholder routes for the tracking feature.
final trackingRoutes = <RouteBase>[
  GoRoute(
    path: '/tracking',
    builder: (context, state) => const _Placeholder(label: 'tracking'),
  ),
];

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(label)),
        body: Center(child: Text('$label feature — coming soon')),
      );
}
