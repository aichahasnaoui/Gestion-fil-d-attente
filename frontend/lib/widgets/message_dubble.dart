import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  const MessageBubble({super.key, required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
        if (message.estUrgent && !isMine)
          Container(margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(6)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.priority_high, size: 12, color: Color(0xFFD32F2F)),
              SizedBox(width: 3),
              Text('Urgent', style: TextStyle(fontSize: 11, color: Color(0xFFD32F2F), fontWeight: FontWeight.w600)),
            ])),
        Row(mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMine) ...[
              CircleAvatar(radius: 14, backgroundColor: const Color(0xFFFFF3E0),
                child: Text(((message.expPrenom ?? ' ')[0]).toUpperCase(),
                  style: const TextStyle(fontSize: 10, color: Color(0xFFE65100)))),
              const SizedBox(width: 6),
            ],
            Flexible(child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMine ? const Color(0xFF1565C0) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMine ? 18 : 4),
                  bottomRight: Radius.circular(isMine ? 4 : 18)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4)]),
              child: Text(message.contenu, style: TextStyle(fontSize: 14,
                color: isMine ? Colors.white : Colors.black87)))),
            if (isMine) ...[
              const SizedBox(width: 4),
              Icon(message.lu ? Icons.done_all : Icons.done, size: 14,
                color: message.lu ? const Color(0xFF1565C0) : Colors.grey),
            ],
          ]),
        Padding(
          padding: EdgeInsets.only(top: 3, left: isMine ? 0 : 36, right: isMine ? 18 : 0),
          child: Text(DateFormat('HH:mm').format(message.createdAt.toLocal()),
            style: TextStyle(fontSize: 10, color: Colors.grey[500]))),
      ]),
    );
  }
}
