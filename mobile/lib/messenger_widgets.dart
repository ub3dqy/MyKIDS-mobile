import 'package:flutter/material.dart';

import 'visuals.dart';
import 'design_system.dart';

const chatBackground = Color(0xffeaf0f7);
const outgoingBubble = Color(0xffdcecff);
const messengerMuted = Color(0xff59667a);
const callBackground = Color(0xff101a31);
Color get gameCallBackground => gameDesign.value == null
    ? callBackground
    : Color.lerp(gameDesign.value!.ink, Colors.black, .62)!;

String messageTime(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return '';
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String messageDay(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return '';
  final today = DateTime.now();
  final day = DateTime(date.year, date.month, date.day);
  final current = DateTime(today.year, today.month, today.day);
  if (day == current) return 'Сегодня';
  if (day == DateTime(today.year, today.month, today.day - 1)) return 'Вчера';
  return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
}

class FamilyAvatar extends StatelessWidget {
  final String name;
  final bool group;
  final double size;
  final bool dark;
  const FamilyAvatar({
    super.key,
    required this.name,
    this.group = false,
    this.size = 52,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    final initials =
        (parts.isEmpty
                ? ''
                : '${parts.first.characters.first}${parts.length > 1 ? parts.last.characters.first : ''}')
            .toUpperCase();
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color:
              gameDesign.value?.soft ??
              (dark ? const Color(0xff293e62) : const Color(0xffdbeaff)),
        ),
        alignment: Alignment.center,
        child: group
            ? Icon(
                Icons.people_alt_rounded,
                size: size * .48,
                color: dark ? Colors.white : actionBlue,
              )
            : Text(
                initials.isEmpty ? 'М' : initials,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: size * .3,
                  color: dark ? Colors.white : actionBlue,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

/// A shared, labelled touch target for ongoing and incoming calls.
class CallControl extends StatelessWidget {
  final String label;
  final String? tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;
  final Color? color;
  const CallControl({
    super.key,
    required this.label,
    required this.icon,
    this.tooltip,
    this.onPressed,
    this.selected = false,
    this.color,
  });
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip ?? label,
    child: SizedBox(
      width: 88,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: Colors.white,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: onPressed == null
                    ? const Color(0xff222e43)
                    : color ??
                          (selected ? Colors.white : const Color(0xff29364e)),
              ),
              child: Icon(
                icon,
                color: onPressed == null
                    ? const Color(0xff8190a5)
                    : selected && color == null
                    ? callBackground
                    : Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: onPressed == null
                    ? const Color(0xff8190a5)
                    : Colors.white,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class MessageBubble extends StatelessWidget {
  final bool own, read, delivered;
  final String sender, text, timestamp;
  final String? attachmentLabel;
  final VoidCallback? onAttachment, onRead;
  const MessageBubble({
    super.key,
    required this.own,
    required this.sender,
    required this.text,
    required this.timestamp,
    this.read = false,
    this.delivered = false,
    this.attachmentLabel,
    this.onAttachment,
    this.onRead,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: bounds.maxWidth * .88),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(12, 9, 10, 6),
        decoration: BoxDecoration(
          color: own
              ? (gameDesign.value?.soft ?? outgoingBubble)
              : (gameDesign.value?.surface ?? Colors.white),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(own ? 16 : 4),
            bottomRight: Radius.circular(own ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!own) ...[
              Text(
                sender,
                style: const TextStyle(
                  color: actionBlue,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
            ],
            if (text.isNotEmpty)
              SelectableText(
                text,
                style: TextStyle(
                  color: gameDesign.value?.ink ?? ink,
                  fontSize: 16,
                  height: 1.3,
                ),
              ),
            if (attachmentLabel != null)
              TextButton.icon(
                onPressed: onAttachment,
                icon: const Icon(Icons.play_circle_outline),
                label: Text(attachmentLabel!),
              ),
            const SizedBox(height: 3),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                Text(
                  messageTime(timestamp),
                  style: const TextStyle(color: messengerMuted, fontSize: 11),
                ),
                if (own)
                  Semantics(
                    label: read
                        ? 'Прочитано получателем'
                        : delivered
                        ? 'Доставлено'
                        : 'Отправлено',
                    child: Icon(
                      read || delivered ? Icons.done_all : Icons.done,
                      size: 16,
                      color: read ? actionBlue : messengerMuted,
                    ),
                  ),
                if (onRead != null)
                  IconButton(
                    tooltip: 'Отметить прочитанным',
                    onPressed: onRead,
                    icon: const Icon(Icons.done_all, size: 18),
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
