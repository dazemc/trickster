import 'package:flutter/widgets.dart';

import '../services/cpu.dart';
import '../theme/accent.dart';
import '../theme/tokens.dart';
import 'pill.dart';

class CpuPill extends StatelessWidget {
  const CpuPill({required this.accent, required this.sample, super.key});

  final WallpaperAccent accent;
  final CpuSample sample;

  @override
  Widget build(BuildContext context) {
    final percent = ((sample.current ?? 0) * 100).round();
    return SystemBarCard(
      accent: accent,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'CPU ',
              style: ShellText.systemBarCaption.copyWith(
                color: accent.captionColor(),
              ),
            ),
            TextSpan(
              text: '$percent%',
              style: ShellText.systemBarValue,
            ),
          ],
        ),
        maxLines: 1,
      ),
    );
  }
}
