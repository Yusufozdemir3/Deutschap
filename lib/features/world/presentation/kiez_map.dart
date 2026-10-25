import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../content/models/world.dart';

IconData placeIcon(String name) => switch (name) {
      'home' => Icons.home_rounded,
      'bakery' => Icons.bakery_dining_rounded,
      'cafe' => Icons.local_cafe_rounded,
      'office' => Icons.account_balance_rounded,
      'doctor' => Icons.local_hospital_rounded,
      'cart' => Icons.shopping_cart_rounded,
      'park' => Icons.park_rounded,
      'train' => Icons.subway_rounded,
      'movie' => Icons.movie_rounded,
      'work' => Icons.work_rounded,
      'mail' => Icons.markunread_mailbox_rounded,
      _ => Icons.place_rounded,
    };

/// A drawn (not photographic) neighbourhood map with one pin per place.
/// Unlocked places are filled; locked ones are outlined with a lock, so
/// the state never depends on colour alone.
class KiezMap extends StatelessWidget {
  const KiezMap({super.key, required this.places, required this.unlocked, this.onTap, this.compact = false});
  final List<Place> places;
  final Set<String> unlocked;
  final void Function(Place p)? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pin = compact ? 26.0 : 44.0;
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = compact ? w * 0.55 : w * 1.05;
      return SizedBox(
        width: w,
        height: h,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          child: Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _KiezPainter(p, showLabels: !compact))),
            for (final place in places)
              Positioned(
                left: (place.x * w - pin / 2).clamp(2.0, w - pin - 2),
                top: (place.y * h - pin / 2).clamp(2.0, h - pin - 2),
                child: _Pin(
                  place: place,
                  open: unlocked.contains(place.id),
                  size: pin,
                  showLabel: !compact,
                  onTap: onTap == null ? null : () => onTap!(place),
                ),
              ),
          ]),
        ),
      );
    });
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.place, required this.open, required this.size, required this.showLabel, this.onTap});
  final Place place;
  final bool open;
  final double size;
  final bool showLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final circle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: open ? p.primary : p.surface,
        border: Border.all(color: open ? p.surface : p.inkMuted.withValues(alpha: 0.5), width: 2),
        boxShadow: open ? [BoxShadow(color: p.primary.withValues(alpha: 0.35), blurRadius: 8)] : null,
      ),
      child: Icon(open ? placeIcon(place.icon) : Icons.lock_outline_rounded, size: size * 0.5, color: open ? p.onPrimary : p.inkMuted),
    );
    return Semantics(
      button: onTap != null,
      label: '${place.nameDe}, ${place.nameTr}, ${open ? 'açık' : 'henüz kilitli'}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            circle,
            if (showLabel && open)
              Positioned(
                top: size + 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: p.surface.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(6)),
                  child: Text(place.nameDe, style: context.text.labelSmall!.copyWith(color: p.ink), maxLines: 1),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Stylised streets, a park and the river. Purely decorative.
class _KiezPainter extends CustomPainter {
  _KiezPainter(this.p, {required this.showLabels});
  final AppPalette p;
  final bool showLabels;

  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Offset.zero & s, Paint()..color = p.surfaceAlt);
    // Blocks: subtle grid of buildings.
    final block = Paint()..color = p.paper;
    for (var i = 0; i < 6; i++) {
      for (var j = 0; j < 6; j++) {
        final r = Rect.fromLTWH(s.width * (i / 6) + 6, s.height * (j / 6) + 6, s.width / 6 - 12, s.height / 6 - 12);
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)), block);
      }
    }
    // River Spree along the bottom.
    final river = Path()
      ..moveTo(0, s.height * 0.93)
      ..cubicTo(s.width * 0.3, s.height * 0.86, s.width * 0.6, s.height * 1.0, s.width, s.height * 0.9)
      ..lineTo(s.width, s.height)
      ..lineTo(0, s.height)
      ..close();
    canvas.drawPath(river, Paint()..color = const Color(0xFF7FB2D9).withValues(alpha: 0.55));
    // Park.
    final park = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(s.width * 0.45, s.height * 0.66), width: s.width * 0.28, height: s.height * 0.17),
      const Radius.circular(24),
    );
    canvas.drawRRect(park, Paint()..color = p.success.withValues(alpha: 0.25));
    // Streets.
    final street = Paint()
      ..color = p.surface
      ..strokeWidth = s.width * 0.035
      ..strokeCap = StrokeCap.round;
    final edge = Paint()
      ..color = p.line
      ..strokeWidth = s.width * 0.035 + 2
      ..strokeCap = StrokeCap.round;
    final streets = [
      (Offset(0, s.height * 0.42), Offset(s.width, s.height * 0.42)),
      (Offset(s.width * 0.55, 0), Offset(s.width * 0.55, s.height * 0.88)),
      (Offset(s.width * 0.1, s.height * 0.12), Offset(s.width * 0.9, s.height * 0.12)),
      (Offset(s.width * 0.25, s.height * 0.15), Offset(s.width * 0.25, s.height * 0.85)),
      (Offset(s.width * 0.55, s.height * 0.5), Offset(s.width * 0.95, s.height * 0.75)),
    ];
    for (final (a, b) in streets) {
      canvas.drawLine(a, b, edge);
    }
    for (final (a, b) in streets) {
      canvas.drawLine(a, b, street);
    }
    if (showLabels) {
      _label(canvas, 'Spree', Offset(s.width * 0.78, s.height * 0.94), p.inkMuted);
    }
  }

  void _label(Canvas c, String text, Offset at, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: 11, fontStyle: FontStyle.italic, fontFamily: 'Literata')),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, at);
  }

  @override
  bool shouldRepaint(_KiezPainter old) => old.p != p || old.showLabels != showLabels;
}
