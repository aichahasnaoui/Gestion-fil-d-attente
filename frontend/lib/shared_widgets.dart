import 'package:flutter/material.dart';
import 'constants.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final Color? borderColor;
  final VoidCallback? onTap;
  const AppCard({super.key, required this.child, this.padding, this.borderColor, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor ?? kGray200, width: 0.5),
          ),
          padding: padding ?? const EdgeInsets.all(16),
          child: child,
        ),
      );
}

class StatusBadge extends StatelessWidget {
  final String status;
  const StatusBadge(this.status, {super.key});

  static const _labels = {
    'waiting':   'En attente',
    'pending':   'En attente',
    'confirmed': 'Confirmé',
    'accepted':  'Accepté',
    'called':    'Appelé',
    'completed': 'Terminé',
    'served':    'Servi',
    'cancelled': 'Annulé',
    'rejected':  'Refusé',
    'no_show':   'Absent',
    'expired':   'Expiré',
  };

  static const _colors = {
    'waiting':   [Color(0xFFFAEEDA), Color(0xFFBA7517)],
    'pending':   [Color(0xFFFAEEDA), Color(0xFFBA7517)],
    'confirmed': [Color(0xFFE1F5EE), Color(0xFF0F6E56)],
    'accepted':  [Color(0xFFE1F5EE), Color(0xFF0F6E56)],
    'called':    [Color(0xFFE6F1FB), Color(0xFF378ADD)],
    'completed': [Color(0xFFF5F5F7), Color(0xFF6B6B80)],
    'served':    [Color(0xFFF5F5F7), Color(0xFF6B6B80)],
    'cancelled': [Color(0xFFFCEBEB), Color(0xFFE24B4A)],
    'rejected':  [Color(0xFFFCEBEB), Color(0xFFE24B4A)],
    'no_show':   [Color(0xFFFCEBEB), Color(0xFFE24B4A)],
    'expired':   [Color(0xFFFFF3E0), Color(0xFFF57C2B)],
  };

  @override
  Widget build(BuildContext context) {
    final c = _colors[status] ?? const [Color(0xFFF5F5F7), Color(0xFF6B6B80)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(20)),
      child: Text(
        _labels[status] ?? status.replaceAll('_', ' '),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: c[1]),
      ),
    );
  }
}

class AvatarCircle extends StatelessWidget {
  final String initials;
  final Color bg;
  final Color fg;
  final double size;
  const AvatarCircle({super.key, required this.initials, this.bg = kPrimaryLight, this.fg = kPrimary, this.size = 40});

  @override
  Widget build(BuildContext context) => Container(
        width: size, height: size,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(initials, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: size * 0.32)),
      );
}

class ConfirmDots extends StatelessWidget {
  final int filled;
  const ConfirmDots({super.key, required this.filled});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) => Container(
              width: 10, height: 10,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < filled ? kPrimary : Colors.transparent,
                border: Border.all(color: kPrimary, width: 1.5),
              ),
            )),
      );
}

class QueueProgress extends StatelessWidget {
  final int ahead;
  final int total;
  const QueueProgress({super.key, required this.ahead, this.total = 20});

  @override
  Widget build(BuildContext context) {
    final pct = ((total - ahead) / total).clamp(0.0, 1.0);
    final color = ahead <= 4 ? kAmber : kPrimary;
    return Row(children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: pct, backgroundColor: kGray200, color: color, minHeight: 6),
        ),
      ),
      const SizedBox(width: 10),
      Text('$ahead devant', style: const TextStyle(fontSize: 12, color: kGray600)),
    ]);
  }
}

class AlertBanner extends StatelessWidget {
  final String title, body;
  final Color bg, fg;
  const AlertBanner({super.key, required this.title, required this.body, this.bg = kAmberLight, this.fg = kAmber});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: fg, fontSize: 13)),
          const SizedBox(height: 4),
          Text(body, style: TextStyle(color: fg, fontSize: 12)),
        ]),
      );
}

class ShimmerCard extends StatelessWidget {
  const ShimmerCard({super.key});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        height: 90,
        decoration: BoxDecoration(color: kGray200, borderRadius: BorderRadius.circular(16)),
      );
}

class EmptyState extends StatelessWidget {
  final String icon, title, subtitle;
  const EmptyState({super.key, required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(icon, style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: kGray900)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: kGray600, fontSize: 13)),
          ]),
        ),
      );
}

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;
  const SectionHeader({super.key, required this.title, this.action});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: kGray900))),
          if (action != null) action!,
        ]),
      );
}
