import 'dart:async';
import 'package:flutter/material.dart';
import '../models.dart';
import '../api_service.dart';
import '../socket_service.dart';

class NotificationProvider extends ChangeNotifier {
  List<NotificationModel> _notifications = [];
  int _unread = 0;
  int? _userId;
  bool _initialized = false;
  Timer? _pollTimer;
  final Set<int> _shownConfirmIds = {};

  List<NotificationModel> get notifications => _notifications;
  int get unread => _unread;

  void Function(NotificationModel)? onConfirmationRequest;

  void init(int userId) {
    _userId = userId;
    _load();
    SocketService().joinUserRoom(userId);

    if (!_initialized) {
      _initialized = true;

      // Socket listener
      SocketService().on('notification', (data) {
        final n = NotificationModel.fromJson(Map<String, dynamic>.from(data));
        _notifications.insert(0, n);
        _unread++;
        notifyListeners();
        _triggerConfirmDialog(n);
      });

      // Polling fallback every 8 seconds
      _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _pollAndCheck());
    }
  }

  void _triggerConfirmDialog(NotificationModel n) {
    if (n.type == 'confirmation_request' && !_shownConfirmIds.contains(n.id)) {
      _shownConfirmIds.add(n.id);
      Future.delayed(const Duration(milliseconds: 200), () {
        onConfirmationRequest?.call(n);
      });
    }
  }

  Future<void> _pollAndCheck() async {
    if (_userId == null) return;
    try {
      final res = await ApiService().getNotifications();
      final newList = (res.data['notifications'] as List)
          .map((j) => NotificationModel.fromJson(j))
          .toList();

      // Check for new confirmation_request not yet shown
      for (final n in newList) {
        if (n.type == 'confirmation_request' && !n.isRead) {
          _triggerConfirmDialog(n);
        }
      }

      final newUnread = res.data['unread'] ?? 0;
      if (newUnread != _unread || newList.length != _notifications.length) {
        _notifications = newList;
        _unread = newUnread;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final res = await ApiService().getNotifications();
      _notifications = (res.data['notifications'] as List)
          .map((j) => NotificationModel.fromJson(j)).toList();
      _unread = res.data['unread'] ?? 0;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    await ApiService().readAllNotifications();
    _unread = 0;
    _notifications = _notifications.map((n) => NotificationModel(
      id: n.id, type: n.type, title: n.title, body: n.body,
      sentAt: n.sentAt, isRead: true, data: n.data,
    )).toList();
    notifyListeners();
  }

  void markReadLocal(int id) {
    var changed = false;
    _notifications = _notifications.map((n) {
      if (n.id != id || n.isRead) return n;
      changed = true;
      return NotificationModel(
        id: n.id,
        type: n.type,
        title: n.title,
        body: n.body,
        sentAt: n.sentAt,
        isRead: true,
        data: n.data,
      );
    }).toList();
    if (changed) {
      _unread = _unread > 0 ? _unread - 1 : 0;
      notifyListeners();
    }
  }

  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
