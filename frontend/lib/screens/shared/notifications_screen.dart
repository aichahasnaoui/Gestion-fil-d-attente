import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import '../../constants.dart';
import '../../api_service.dart';
import '../../providers/notification_provider.dart';
import '../../models.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  IconData _iconFor(String type) {
    switch (type) {
      case 'ticket_alert':          return Icons.confirmation_number;
      case 'appointment_alert':     return Icons.calendar_today;
      case 'appointment_reminder':  return Icons.alarm;
      case 'confirmation_request':  return Icons.alarm;
      case 'doctor_response':       return Icons.medical_services;
      default:                      return Icons.notifications;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'ticket_alert':          return kAmber;
      case 'appointment_alert':     return kPrimary;
      case 'appointment_reminder':  return const Color(0xFFF57C2B);
      case 'confirmation_request':  return kRed;
      case 'doctor_response':       return kPurple;
      default:                      return kGray600;
    }
  }

  bool _hasTicketActions(NotificationModel n) {
    final action = n.data?['action'];
    return n.type == 'confirmation_request' ||
        (n.type == 'ticket_alert' && action == 'confirm_arrival');
  }

  bool _isObsoleteTicketAction(NotificationModel n, List<NotificationModel> all) {
    final ticketId = _ticketIdFor(n);
    if (ticketId == null) return false;

    DateTime? sentAt;
    try {
      sentAt = DateTime.parse(n.sentAt);
    } catch (_) {}

    return all.any((other) {
      if (other.id == n.id || _ticketIdFor(other) != ticketId) return false;
      if (!_looksLikeTerminalTicketNotification(other)) return false;
      if (sentAt == null) return true;
      try {
        return DateTime.parse(other.sentAt).isAfter(sentAt);
      } catch (_) {
        return true;
      }
    });
  }

  bool _looksLikeTerminalTicketNotification(NotificationModel n) {
    final text = '${n.title} ${n.body}'.toLowerCase();
    return text.contains('annul') ||
        text.contains('absent') ||
        text.contains('presence confirm') ||
        text.contains('présence confirm') ||
        text.contains('no_show') ||
        text.contains('served') ||
        text.contains('termin');
  }

  int? _ticketIdFor(NotificationModel n) {
    final raw = n.data?['ticket_id'];
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  String _errorMessage(Object e) {
    if (e is DioException && e.response?.data is Map) {
      final data = e.response!.data as Map;
      final msg = data['error'] ?? data['message'];
      if (msg != null) return msg.toString();
    }
    return 'Action impossible. Le ticket a peut-etre deja ete annule.';
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      const months = [
        'Jan','Fév','Mar','Avr','Mai','Jun',
        'Jul','Aoû','Sep','Oct','Nov','Déc'
      ];
      return '${dt.day} ${months[dt.month - 1]} à '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso.length > 16 ? iso.substring(0, 16) : iso;
    }
  }

  void _handleTap(BuildContext context, NotificationModel n, NotificationProvider provider) {
    // Mark as read
    if (!n.isRead) {
      ApiService().readNotification(n.id);
      provider.markReadLocal(n.id);
    }

    // Show confirm dialog for confirmation_request
    if (n.type == 'confirmation_request') {
      provider.onConfirmationRequest?.call(n);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationProvider>();
    final notifs   = provider.notifications;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (provider.unread > 0)
            TextButton(
              onPressed: provider.markAllRead,
              child: const Text('Tout marquer comme lu',
                  style: TextStyle(color: kPrimary)),
            ),
        ],
      ),
      body: notifs.isEmpty
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('🔔', style: TextStyle(fontSize: 48)),
                SizedBox(height: 16),
                Text('Aucune notification',
                    style: TextStyle(fontWeight: FontWeight.w600,
                        fontSize: 16, color: kGray900)),
                SizedBox(height: 8),
                Text('Vous serez averti lorsque votre tour approche',
                    style: TextStyle(color: kGray600, fontSize: 13)),
              ]),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: notifs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final n     = notifs[i];
                final color = _colorFor(n.type);
                final hasTicketActions = _hasTicketActions(n) &&
                    !_isObsoleteTicketAction(n, notifs);

                return GestureDetector(
                  onTap: () => _handleTap(context, n, provider),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: n.isRead
                          ? Colors.white
                          : (hasTicketActions
                              ? kRedLight
                              : kPrimaryLight.withOpacity(0.5)),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: n.isRead
                              ? kGray200
                              : color.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                  color: color.withOpacity(0.1),
                                  shape: BoxShape.circle),
                              child: Icon(_iconFor(n.type), color: color, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(n.title,
                                      style: TextStyle(
                                          fontWeight: n.isRead
                                              ? FontWeight.w500
                                              : FontWeight.w700,
                                          fontSize: 14,
                                          color: kGray900)),
                                  const SizedBox(height: 3),
                                  Text(n.body,
                                      style: const TextStyle(
                                          color: kGray600, fontSize: 13)),
                                  const SizedBox(height: 4),
                                  Text(_formatTime(n.sentAt),
                                      style: const TextStyle(
                                          color: kGray400, fontSize: 11)),
                                ],
                              ),
                            ),
                            if (!n.isRead)
                              Container(
                                  width: 8, height: 8,
                                  decoration: BoxDecoration(
                                      color: color, shape: BoxShape.circle)),
                          ],
                        ),
                        // Show confirm/cancel buttons for actionable ticket alerts.
                        if (hasTicketActions) ...[
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  final ticketId = _ticketIdFor(n);
                                  if (ticketId == null) return;
                                  try {
                                    await ApiService().confirmTicket(ticketId);
                                    await ApiService().readNotification(n.id);
                                    provider.markReadLocal(n.id);
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text('Présence confirmée ✅'),
                                            backgroundColor: kPrimary));
                                  } catch (e) {
                                    await ApiService().readNotification(n.id);
                                    provider.markReadLocal(n.id);
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(_errorMessage(e)),
                                            backgroundColor: kRed));
                                  }
                                },
                                icon: const Icon(Icons.check_circle, size: 16),
                                label: const Text('Je suis là ✅'),
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(0, 40),
                                  backgroundColor: kPrimary,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final ticketId = _ticketIdFor(n);
                                  if (ticketId == null) return;
                                  try {
                                    await ApiService().cancelTicket(ticketId);
                                    await ApiService().readNotification(n.id);
                                    provider.markReadLocal(n.id);
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text('Ticket annulé'),
                                            backgroundColor: kRed));
                                  } catch (e) {
                                    await ApiService().readNotification(n.id);
                                    provider.markReadLocal(n.id);
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            content: Text(_errorMessage(e)),
                                            backgroundColor: kRed));
                                  }
                                },
                                icon: const Icon(Icons.cancel_outlined,
                                    color: kRed, size: 16),
                                label: const Text('Annuler'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 40),
                                  foregroundColor: kRed,
                                  side: const BorderSide(color: kRed),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                          ]),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
