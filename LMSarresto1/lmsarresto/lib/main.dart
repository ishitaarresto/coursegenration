import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/theme.dart';
import 'core/router/router.dart';

void main() {
  runApp(const ProviderScope(child: ArrestoApp()));
}

class ArrestoApp extends ConsumerWidget {
  const ArrestoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Arresto LMS',
      debugShowCheckedModeBanner: false,
      theme: ArrestoTheme.light(),
      routerConfig: router,
    );
  }
}
