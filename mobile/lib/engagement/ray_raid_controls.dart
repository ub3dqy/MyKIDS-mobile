import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'ray_raid_model.dart';

class RaidStick extends StatefulWidget {
  final String label;
  final bool firing;
  final double size;
  final void Function(RaidVec vector, bool pressed) onInput;
  final void Function(RaidVec vector) onAccessibleMove;
  const RaidStick({
    super.key,
    required this.label,
    required this.onInput,
    required this.onAccessibleMove,
    this.firing = false,
    this.size = 126,
  });
  @override
  State<RaidStick> createState() => _RaidStickState();
}

class _RaidStickState extends State<RaidStick> {
  int? pointer;
  Offset displacement = Offset.zero;
  void update(PointerEvent event) {
    if (!mounted) return;
    final center = Offset(widget.size / 2, widget.size / 2);
    final d = event.localPosition - center;
    final maximum = widget.size * .3;
    final limited = d.distance > maximum ? d / d.distance * maximum : d;
    setState(() => displacement = limited);
    widget.onInput(RaidVec(limited.dx / maximum, limited.dy / maximum), true);
  }

  void release(PointerEvent event) {
    if (!mounted || event.pointer != pointer) return;
    pointer = null;
    setState(() => displacement = Offset.zero);
    widget.onInput(RaidVec.zero, false);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    hint: widget.firing
        ? 'Удерживай для огня, веди пальцем для прицеливания'
        : 'Веди пальцем в нужную сторону',
    customSemanticsActions: widget.firing
        ? {
            const CustomSemanticsAction(label: 'Короткий огонь'): () =>
                widget.onAccessibleMove(RaidVec.zero),
          }
        : {
            for (final item in const [
              ('Шаг влево', RaidVec(-1, 0)),
              ('Шаг вправо', RaidVec(1, 0)),
              ('Шаг вверх', RaidVec(0, -1)),
              ('Шаг вниз', RaidVec(0, 1)),
            ])
              CustomSemanticsAction(label: item.$1): () =>
                  widget.onAccessibleMove(item.$2),
          },
    child: ExcludeSemantics(
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (!mounted || pointer != null) return;
          pointer = event.pointer;
          update(event);
        },
        onPointerMove: (event) {
          if (pointer == event.pointer) update(event);
        },
        onPointerUp: release,
        onPointerCancel: release,
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(
            painter: _StickPainter(
              displacement,
              widget.firing,
              pointer != null,
            ),
          ),
        ),
      ),
    ),
  );
}

class _StickPainter extends CustomPainter {
  final Offset delta;
  final bool fire, pressed;
  _StickPainter(this.delta, this.fire, this.pressed);
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero), radius = size.width / 2 - 3;
    final accent = fire ? const Color(0xffffb85d) : const Color(0xff71efff);
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xb312253c));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = accent.withValues(alpha: .55),
    );
    canvas.drawCircle(
      center,
      radius * .72,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = accent.withValues(alpha: .17),
    );
    final knob = center + delta;
    canvas.drawCircle(
      knob.translate(0, 4),
      radius * .40,
      Paint()..color = const Color(0x77101a2e),
    );
    canvas.drawCircle(
      knob,
      radius * .40,
      Paint()..color = pressed ? accent : accent.withValues(alpha: .55),
    );
    final paint = Paint()
      ..color = const Color(0xff12283e)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    if (fire) {
      canvas.drawCircle(knob, 9, paint);
      canvas.drawLine(knob.translate(-14, 0), knob.translate(14, 0), paint);
      canvas.drawLine(knob.translate(0, -14), knob.translate(0, 14), paint);
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(knob.dx - 10, knob.dy)
          ..lineTo(knob.dx + 10, knob.dy)
          ..moveTo(knob.dx, knob.dy - 10)
          ..lineTo(knob.dx, knob.dy + 10),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StickPainter old) =>
      delta != old.delta || pressed != old.pressed || fire != old.fire;
}

class RaidAbilityButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final double remaining, recharge;
  final VoidCallback onPressed;
  const RaidAbilityButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.remaining,
    required this.recharge,
    required this.onPressed,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: remaining <= 0,
    label: remaining <= 0
        ? '$label готов'
        : '$label: ещё ${remaining.ceil()} сек.',
    child: Tooltip(
      message: label,
      child: SizedBox.square(
        dimension: 58,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CircularProgressIndicator(
                value: remaining <= 0 ? 1 : 1 - remaining / recharge,
                strokeWidth: 3,
                backgroundColor: const Color(0xff203d53),
                color: color,
              ),
            ),
            IconButton.filled(
              onPressed: remaining <= 0 ? onPressed : null,
              style: IconButton.styleFrom(
                minimumSize: const Size(52, 52),
                backgroundColor: const Color(0xff132d43),
                foregroundColor: color,
                disabledBackgroundColor: const Color(0xdd102235),
              ),
              icon: remaining > 0
                  ? Text(
                      '${remaining.ceil()}',
                      style: const TextStyle(fontSize: 18, color: Colors.white),
                    )
                  : Icon(icon, size: 26),
            ),
          ],
        ),
      ),
    ),
  );
}
