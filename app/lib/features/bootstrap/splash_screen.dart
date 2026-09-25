import 'package:flutter/material.dart';

import '../branding/brand.dart';

/// Shown while the local config loads. Once [AppState.ready] flips, the app
/// swaps to the login/home gate. Matches the approved RM Pulse splash mockup:
/// deep-navy hero with the R.M pulse mark and a "Powered by R.M arts" curved
/// white footer.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.navyDark,
      body: Stack(
        children: [
          // Deep navy gradient backdrop.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Brand.navyMid, Brand.navyDark, Color(0xFF081831)],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          // Faint wave lines near the top.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 260,
            child: CustomPaint(
              painter:
                  WaveBackgroundPainter(color: Colors.white, opacity: 0.06),
            ),
          ),
          // Soft glow rising from the bottom-centre (above the white curve).
          Positioned(
            bottom: 150,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    const Color(0xFF2AA6E0).withValues(alpha: 0.45),
                    Brand.navyDark.withValues(alpha: 0.0),
                  ]),
                ),
              ),
            ),
          ),

          // Hero: R.M pulse mark + tagline + pulse line, vertically centred.
          Positioned.fill(
            bottom: 150,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const RmPulseLogo(dark: true, featherSize: 118),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: 220,
                    height: 34,
                    child: CustomPaint(
                      painter: PulseLinePainter(color: const Color(0xFF39B6F0)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Curved white "Powered by R.M arts" footer.
          Align(
            alignment: Alignment.bottomCenter,
            child: ClipPath(
              clipper: _TopCurveClipper(),
              child: Container(
                width: double.infinity,
                height: 168,
                color: Colors.white,
                padding: const EdgeInsets.only(top: 46),
                alignment: Alignment.topCenter,
                child: const PoweredByFooter(onLightCard: true),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Clips the footer with a concave curved top edge (matches the mockup sweep).
class _TopCurveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, size.height * 0.28);
    path.quadraticBezierTo(
      size.width * 0.5,
      -size.height * 0.10,
      size.width,
      size.height * 0.28,
    );
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
