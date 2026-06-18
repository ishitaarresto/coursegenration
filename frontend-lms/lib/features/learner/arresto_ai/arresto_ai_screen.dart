import 'package:flutter/material.dart';
import '../../shared/arresto_ai/arresto_ai_panel.dart';

class ArrestoAiScreen extends StatelessWidget {
  const ArrestoAiScreen({super.key});

  @override
  Widget build(BuildContext context) => const ArrestoAIPanel(embedded: true);
}
