import 'package:flutter/material.dart';

/// RM Pulse brand kit — colours + the reusable logo / decoration widgets used
/// by the splash and login screens so both stay pixel-consistent with the
/// approved mockup.
class Brand {
  Brand._();

  // ── Aurora Mesh · Ocean Blue palette ───────────────────────────────────
  // Primary is ocean blue, flowing to teal across the mesh hero.
  static const Color indigo = Color(0xFF1560D8); // primary (ocean blue)
  static const Color violet = Color(0xFF1877CF);
  static const Color skyBlue = Color(0xFF12A5C9);
  static const Color aqua = Color(0xFF16C2A8);

  // Aliases kept so existing references stay valid, repointed to Ocean Blue.
  static const Color royalBlue = indigo;
  static const Color royalBlueLight = skyBlue;

  // Splash background (kept from the approved client mockup — dark navy).
  static const Color navyDark = Color(0xFF0B1F3F);
  static const Color navyMid = Color(0xFF102A50);

  // Tagline word colours — "Execute. Track. Deliver."
  static const Color execBlue = Color(0xFF2AA6E0);
  static const Color trackGreen = Color(0xFF5FBE3D);
  static const Color deliverPink = Color(0xFFE8468C);

  static const Color inkNavy = Color(0xFF0E2E5C); // primary dark text
  static const Color fieldBorder = Color(0xFFDCE6F2);
  static const Color labelInk = Color(0xFF294A73);

  static const Color surface = Color(0xFFF3F7FC); // page background
  static const Color card = Colors.white;
  static const Color mutedInk = Color(0xFF7B92B0);

  // Reusable gradients.
  /// The Aurora mesh used on hero headers (Ocean Blue → Teal).
  static const LinearGradient meshGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1B52D6), Color(0xFF1877CF), Color(0xFF12A5C9), Color(0xFF16C2A8)],
    stops: [0.0, 0.35, 0.75, 1.0],
  );
  static const LinearGradient headerGradient = meshGradient;
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF1560D8), Color(0xFF12B6C9)],
  );
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1560D8), Color(0xFF12B6C9)],
  );

  /// Soft card decoration used to group form controls.
  static BoxDecoration cardDecoration({double radius = 18}) => BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFFE4EDF7)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1560D8).withOpacity(0.09),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      );
}

/// A gradient primary button with an optional trailing icon and busy spinner.
class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  final Gradient gradient;
  final double height;

  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.gradient = Brand.primaryGradient,
    this.height = 54,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Material(
        borderRadius: BorderRadius.circular(14),
        elevation: enabled ? 3 : 0,
        shadowColor: Brand.royalBlue.withOpacity(0.4),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onPressed : null,
          child: Ink(
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Container(
              height: height,
              alignment: Alignment.center,
              child: busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            )),
                        if (icon != null) ...[
                          const SizedBox(width: 10),
                          Icon(icon, color: Colors.white, size: 20),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A gradient app bar with an optional back button and trailing actions.
class GradientAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBack;
  final List<Widget> actions;
  final double? progress; // 0..1 thin bar under the bar, null = none

  const GradientAppBar({
    super.key,
    required this.title,
    this.showBack = true,
    this.actions = const [],
    this.progress,
  });

  @override
  Size get preferredSize => Size.fromHeight(progress == null ? 58 : 61);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: Brand.headerGradient,
        boxShadow: [
          BoxShadow(color: Color(0x330E3C8C), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  if (showBack)
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  else
                    const SizedBox(width: 12),
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        )),
                  ),
                  ...actions,
                  const SizedBox(width: 4),
                ],
              ),
            ),
            if (progress != null)
              LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation(Color(0xFF7FE0A6)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Minimal HTML renderer for the small snippets the dropdown info card shows.
/// Supports `<b>`/`<strong>` (bold), `<br>` line breaks and plain text — enough
/// for the backend's `htmlText` (bold labels + line breaks) without a heavy
/// package dependency.
class HtmlLite extends StatelessWidget {
  final String html;
  final Color color;
  final double fontSize;
  const HtmlLite(this.html,
      {super.key, this.color = Brand.inkNavy, this.fontSize = 13.5});

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    // Normalise line breaks and split on bold tags.
    final normalized = html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</?p>', caseSensitive: false), '\n');
    final re = RegExp(r'<(b|strong)>(.*?)</\1>',
        caseSensitive: false, dotAll: true);
    int last = 0;
    for (final m in re.allMatches(normalized)) {
      if (m.start > last) {
        spans.add(TextSpan(text: _strip(normalized.substring(last, m.start))));
      }
      spans.add(TextSpan(
          text: _strip(m.group(2) ?? ''),
          style: const TextStyle(fontWeight: FontWeight.w700)));
      last = m.end;
    }
    if (last < normalized.length) {
      spans.add(TextSpan(text: _strip(normalized.substring(last))));
    }
    return RichText(
      text: TextSpan(
        style: TextStyle(color: color, fontSize: fontSize, height: 1.5),
        children: spans,
      ),
    );
  }

  static String _strip(String s) =>
      s.replaceAll(RegExp(r'<[^>]+>'), ''); // drop any other stray tags
}

/// A small gradient rounded-square icon chip used on card section headers.
class AuroraIconChip extends StatelessWidget {
  final IconData icon;
  final double size;
  const AuroraIconChip(this.icon, {super.key, this.size = 38});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: Brand.accentGradient,
          borderRadius: BorderRadius.circular(size * 0.32),
          boxShadow: [
            BoxShadow(
              color: Brand.indigo.withOpacity(0.30),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.5),
      );
}

/// The Aurora Mesh hero header with a "STEP x OF y" label, a big title, and an
/// overlapping floating stepper card. Used at the top of multi-step flows.
class AuroraStepHeader extends StatelessWidget {
  final String kicker; // e.g. "Start installation"
  final String title; // e.g. "Site details"
  final int currentStep; // 1-based
  final int totalSteps;
  final List<String> stepLabels; // optional labels under each dot
  final bool showBack;
  final bool showStepper;
  final List<Widget> actions;

  const AuroraStepHeader({
    super.key,
    required this.kicker,
    required this.title,
    this.currentStep = 1,
    this.totalSteps = 1,
    this.stepLabels = const [],
    this.showBack = true,
    this.showStepper = true,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.only(bottom: showStepper ? 32 : 12),
              decoration: const BoxDecoration(
                gradient: Brand.meshGradient,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 12, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (showBack)
                            IconButton(
                              icon: const Icon(Icons.arrow_back,
                                  color: Colors.white),
                              onPressed: () => Navigator.of(context).maybePop(),
                            )
                          else
                            const SizedBox(width: 10),
                          Expanded(
                            child: Text(kicker,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                )),
                          ),
                          ...actions,
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('STEP $currentStep OF $totalSteps',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                )),
                            const SizedBox(height: 1),
                            Text(title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                )),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (showStepper)
              Positioned(
                left: 16,
                right: 16,
                bottom: -24,
                child: _StepperCard(
                  current: currentStep,
                  total: totalSteps,
                  labels: stepLabels,
                ),
              ),
          ],
        ),
        SizedBox(height: showStepper ? 28 : 6),
      ],
    );
  }
}

class _StepperCard extends StatelessWidget {
  final int current;
  final int total;
  final List<String> labels;
  const _StepperCard(
      {required this.current, required this.total, this.labels = const []});

  @override
  Widget build(BuildContext context) {
    final row = <Widget>[];
    for (var i = 1; i <= total; i++) {
      final done = i < current;
      final active = i == current;
      final on = done || active;
      row.add(Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: on ? Brand.accentGradient : null,
          color: on ? null : const Color(0xFFE1EAF6),
        ),
        alignment: Alignment.center,
        child: done
            ? const Icon(Icons.check, size: 15, color: Colors.white)
            : Text('$i',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: active ? Colors.white : Brand.mutedInk,
                )),
      ));
      if (i < total) {
        row.add(Expanded(
          child: Container(
            height: 3,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: i < current ? Brand.indigo : const Color(0xFFE1EAF6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ));
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Brand.indigo.withOpacity(0.14),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(children: row),
    );
  }
}

/// A floating bottom action bar (Back + primary) matching the Aurora style.
class AuroraActionBar extends StatelessWidget {
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final IconData? primaryIcon;
  final VoidCallback? onBack; // null hides the Back button
  final String backLabel;
  final bool busy;

  const AuroraActionBar({
    super.key,
    required this.primaryLabel,
    required this.onPrimary,
    this.primaryIcon = Icons.arrow_forward,
    this.onBack,
    this.backLabel = 'Back',
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Color(0x14000000), blurRadius: 14, offset: Offset(0, -3)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              if (onBack != null) ...[
                Expanded(
                  flex: 4,
                  child: OutlinedButton(
                    onPressed: onBack,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      side: const BorderSide(color: Brand.fieldBorder),
                      foregroundColor: Brand.indigo,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(backLabel),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                flex: 7,
                child: GradientButton(
                  label: primaryLabel,
                  icon: primaryIcon,
                  onPressed: onPrimary,
                  busy: busy,
                  height: 52,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The R.M pulse hero mark: the colourful feather next to the "R.M pulse"
/// wordmark, with the "Execute. Track. Deliver." tagline underneath.
///
/// [dark] renders the wordmark in white (for the dark splash); otherwise it is
/// navy (for the light login screen).
class RmPulseLogo extends StatelessWidget {
  final bool dark;
  final double featherSize;

  const RmPulseLogo({super.key, this.dark = false, this.featherSize = 96});

  @override
  Widget build(BuildContext context) {
    final wordColor = dark ? Colors.white : Brand.inkNavy;
    final pulseColor = dark ? const Color(0xFFDCE7F5) : const Color(0xFF3C4A63);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset('assets/images/feather.png',
                height: featherSize, fit: BoxFit.contain),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('R.M',
                    style: TextStyle(
                      color: wordColor,
                      fontSize: featherSize * 0.52,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                      letterSpacing: -0.5,
                    )),
                Text('pulse',
                    style: TextStyle(
                      color: pulseColor,
                      fontSize: featherSize * 0.34,
                      fontWeight: FontWeight.w300,
                      height: 1.05,
                      letterSpacing: 1.5,
                    )),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        const _Tagline(),
      ],
    );
  }
}

/// "Execute. Track. Deliver." with each word in its brand colour.
class _Tagline extends StatelessWidget {
  const _Tagline();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Text('Execute.', style: TextStyle(color: Brand.execBlue, fontSize: 16, fontWeight: FontWeight.w700)),
        SizedBox(width: 6),
        Text('Track.', style: TextStyle(color: Brand.trackGreen, fontSize: 16, fontWeight: FontWeight.w700)),
        SizedBox(width: 6),
        Text('Deliver.', style: TextStyle(color: Brand.deliverPink, fontSize: 16, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

/// The "Powered by / R.M arts" footer lockup used at the bottom of both screens.
class PoweredByFooter extends StatelessWidget {
  final bool onLightCard;
  const PoweredByFooter({super.key, this.onLightCard = true});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Powered by',
            style: TextStyle(
              fontSize: 11,
              color: onLightCard ? const Color(0xFF6B7A90) : Colors.white70,
              letterSpacing: 0.3,
            )),
        const SizedBox(height: 6),
        Image.asset('assets/images/logo.png', height: 46, fit: BoxFit.contain),
      ],
    );
  }
}

/// Subtle flowing wave lines used as a background decoration.
class WaveBackgroundPainter extends CustomPainter {
  final Color color;
  final double opacity;
  WaveBackgroundPainter({required this.color, this.opacity = 0.10});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = color.withOpacity(opacity);

    for (int i = 0; i < 5; i++) {
      final path = Path();
      final dy = size.height * (0.06 + i * 0.045);
      path.moveTo(0, dy);
      path.cubicTo(
        size.width * 0.30, dy - 26,
        size.width * 0.62, dy + 30,
        size.width, dy - 8,
      );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A thin ECG / heartbeat line with a single blip — the "pulse" motif.
class PulseLinePainter extends CustomPainter {
  final Color color;
  PulseLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    final midY = size.height / 2;
    final path = Path()..moveTo(0, midY);
    final b = size.width * 0.42; // blip start
    path.lineTo(b, midY);
    path.lineTo(b + size.width * 0.03, midY - size.height * 0.42);
    path.lineTo(b + size.width * 0.07, midY + size.height * 0.5);
    path.lineTo(b + size.width * 0.10, midY);
    path.lineTo(size.width, midY);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
