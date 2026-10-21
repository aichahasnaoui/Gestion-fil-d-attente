import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:badges/badges.dart' as badges;
import 'package:qr_flutter/qr_flutter.dart';
import '../../constants.dart';
import '../../api_service.dart';
import '../../models.dart';
import '../../shared_widgets.dart';
import '../../socket_service.dart';
import '../../providers/notification_provider.dart';
import '../shared/notifications_screen.dart';
import '../shared/profile_screen.dart';

class ClientHome extends StatefulWidget {
  const ClientHome({super.key});
  @override
  State<ClientHome> createState() => _ClientHomeState();
}

class _ClientHomeState extends State<ClientHome> {
  int _tab = 0;
  UserModel? _user;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      final res = await ApiService().getMe();
      setState(() => _user = UserModel.fromJson(res.data['user']));
      if (!mounted) return;
      final provider = context.read<NotificationProvider>();
      // Set callback BEFORE init so it's ready when notifications arrive
      provider.onConfirmationRequest = (n) => _showConfirmDialog(n);
      provider.init(_user!.id);
    } catch (_) {}
  }

  void _showConfirmDialog(NotificationModel n) {
    final ticketId = n.data?['ticket_id'] as int?;
    if (ticketId == null) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('⏰ Confirmez votre présence',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('⚠️ Il reste 3 personnes avant votre tour !',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 8),
          const Text(
            'Confirmez votre présence maintenant.\nSinon votre ticket sera annulé automatiquement.',
            textAlign: TextAlign.center,
            style: TextStyle(color: kGray600, fontSize: 13),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await ApiService().cancelTicket(ticketId);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Ticket annulé'), backgroundColor: kRed));
            },
            child: const Text('Annuler mon ticket', style: TextStyle(color: kRed)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ApiService().confirmTicket(ticketId);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Présence confirmée ✅'), backgroundColor: kPrimary));
              } catch (_) {}
            },
            style: ElevatedButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
            child: const Text('Je suis là ✅'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<NotificationProvider>().unread;
    final screens = [
      _ClientDashboard(user: _user),
      const _MyTicketsScreen(),
      const NotificationsScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: screens[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: Colors.white,
        indicatorColor: kPrimaryLight,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: kPrimary),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.confirmation_number_outlined),
            selectedIcon: Icon(Icons.confirmation_number, color: kPrimary),
            label: 'My Tickets',
          ),
          NavigationDestination(
            icon: badges.Badge(
              showBadge: unread > 0,
              badgeContent: Text('$unread',
                  style: const TextStyle(color: Colors.white, fontSize: 10)),
              child: const Icon(Icons.notifications_outlined),
            ),
            selectedIcon: const Icon(Icons.notifications, color: kPrimary),
            label: 'Alerts',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: kPrimary),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _ClientDashboard extends StatefulWidget {
  final UserModel? user;
  const _ClientDashboard({this.user});
  @override
  State<_ClientDashboard> createState() => _ClientDashboardState();
}

class _ClientDashboardState extends State<_ClientDashboard> {
  List<ServiceModel> _services = [];
  String? _selectedType;
  bool _loading = true;
  final Set<int> _joinedServices = {};
  late final Function(dynamic) _queueHandler;

  final _types = [
    {'key': null, 'label': 'All', 'icon': Icons.apps},
    {'key': 'bank', 'label': 'Bank', 'icon': Icons.account_balance},
    {'key': 'post', 'label': 'Post', 'icon': Icons.local_post_office},
    {'key': 'telecom', 'label': 'Telecom', 'icon': Icons.phone_android},
    {'key': 'cnss', 'label': 'CNSS', 'icon': Icons.security},
    {'key': 'other', 'label': 'Other', 'icon': Icons.more_horiz},
  ];

  @override
  void initState() {
    super.initState();
    _queueHandler = (_) => _load(silent: true);
    SocketService().on('queue_update', _queueHandler);
    _load();
  }

  @override
  void dispose() {
    SocketService().off('queue_update', _queueHandler);
    for (final id in _joinedServices) {
      SocketService().leaveServiceRoom(id);
    }
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final res = await ApiService().getServices(type: _selectedType);
      final services = (res.data['services'] as List)
          .map((j) => ServiceModel.fromJson(j))
          .toList();
      final nextIds = services.map((s) => s.id).toSet();
      for (final id in _joinedServices.difference(nextIds)) {
        SocketService().leaveServiceRoom(id);
      }
      for (final id in nextIds.difference(_joinedServices)) {
        SocketService().joinServiceRoom(id);
      }
      _joinedServices
        ..clear()
        ..addAll(nextIds);
      setState(() {
        _services = services;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: kGray100,
        body: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(slivers: [
            // Header
            SliverToBoxAdapter(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF2D6BE4), Color(0xFF378ADD)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius:
                      BorderRadius.vertical(bottom: Radius.circular(28)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 56, 20, 24),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(
                                  'Hello, ${widget.user?.fullName.split(' ').first ?? ''}! 👋',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700)),
                              const Text('Take a ticket, skip the wait',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 13)),
                            ])),
                        GestureDetector(
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const ProfileScreen())),
                          child: AvatarCircle(
                            initials: widget.user?.initials ?? '?',
                            size: 44,
                            bg: Colors.white24,
                            fg: Colors.white,
                          ),
                        ),
                      ]),
                    ]),
              ).animate().fadeIn(duration: 400.ms),
            ),

            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                  delegate: SliverChildListDelegate([
                // Type filter chips
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _types.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final t = _types[i];
                      final selected = _selectedType == t['key'];
                      return FilterChip(
                        selected: selected,
                        label: Text(t['label'] as String),
                        avatar: Icon(t['icon'] as IconData, size: 16),
                        onSelected: (_) {
                          setState(() => _selectedType = t['key'] as String?);
                          _load();
                        },
                        selectedColor: kPrimaryLight,
                        checkmarkColor: kPrimary,
                        labelStyle: TextStyle(
                            color: selected ? kPrimary : kGray600,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.normal),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),

                const SectionHeader(title: 'Available Services'),
                const SizedBox(height: 4),

                if (_loading)
                  ...List.generate(4, (_) => const ShimmerCard())
                else if (_services.isEmpty)
                  const EmptyState(
                      icon: '🏢',
                      title: 'No services found',
                      subtitle: 'Try a different filter')
                else
                  ..._services
                      .map((s) => _ServiceCard(service: s))
                      .toList()
                      .animate(interval: 60.ms)
                      .fadeIn()
                      .slideY(begin: 0.05),
              ])),
            ),
          ]),
        ),
      );
}

class _ServiceCard extends StatelessWidget {
  final ServiceModel service;
  const _ServiceCard({required this.service});

  static const _typeColors = {
    'bank': [Color(0xFF1BA87A), Color(0xFFE4F7F0)],
    'post': [Color(0xFFF57C2B), Color(0xFFFFF1E6)],
    'telecom': [Color(0xFF2D6BE4), Color(0xFFEDF2FD)],
    'cnss': [Color(0xFF7F77DD), Color(0xFFF0EFFE)],
    'hospital': [Color(0xFFE24B4A), Color(0xFFFCEBEB)],
    'clinic': [Color(0xFF0F6E56), Color(0xFFE1F5EE)],
  };

  @override
  Widget build(BuildContext context) {
    final colors = _typeColors[service.type] ?? [kGray600, kGray100];
    return AppCard(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => _TakeTicketScreen(service: service))),
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
              color: colors[1], borderRadius: BorderRadius.circular(14)),
          child: Icon(Icons.business, color: colors[0], size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(service.name,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 2),
          Text(service.address ?? '',
              style: const TextStyle(color: kGray600, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: colors[1], borderRadius: BorderRadius.circular(20)),
              child: Text('${service.todayInQueue} waiting',
                  style: TextStyle(color: colors[0], fontSize: 11, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 6),
            // Open guichets badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: service.openGuichets > 0 ? const Color(0xFFE4F7F0) : kRedLight,
                  borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.window,
                    size: 10,
                    color: service.openGuichets > 0 ? const Color(0xFF1BA87A) : kRed),
                const SizedBox(width: 3),
                Text(
                  '${service.openGuichets} guichet${service.openGuichets > 1 ? 's' : ''}',
                  style: TextStyle(
                      color: service.openGuichets > 0 ? const Color(0xFF1BA87A) : kRed,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ]),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.access_time, size: 12, color: kGray400),
            const SizedBox(width: 3),
            Text('~${service.todayAvgWait} min',
                style: const TextStyle(color: kGray600, fontSize: 11)),
          ]),
        ])),
        const Icon(Icons.chevron_right, color: kGray400),
      ]),
    );
  }
}

class _TakeTicketScreen extends StatefulWidget {
  final ServiceModel service;
  const _TakeTicketScreen({required this.service});
  @override
  State<_TakeTicketScreen> createState() => _TakeTicketScreenState();
}

class _TakeTicketScreenState extends State<_TakeTicketScreen> {
  TicketModel? _ticket;
  bool _loading = false;
  bool _confirming = false;
  Timer? _timer;
  late final Function(dynamic) _queueHandler;

  @override
  void initState() {
    super.initState();
    _queueHandler = (data) {
      if (data is Map && data['service_id'] == widget.service.id) {
        _refreshAhead();
      }
    };
    SocketService().on('queue_update', _queueHandler);
    SocketService().joinServiceRoom(widget.service.id);
  }

  @override
  void dispose() {
    _timer?.cancel();
    SocketService().off('queue_update', _queueHandler);
    SocketService().leaveServiceRoom(widget.service.id);
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer =
        Timer.periodic(const Duration(seconds: 30), (_) => _refreshAhead());
  }

  Future<void> _refreshAhead() async {
    if (_ticket == null || !_ticket!.isActive) return;
    try {
      final res = await ApiService().getTicket(_ticket!.id);
      if (mounted)
        setState(() => _ticket = TicketModel.fromJson(res.data['ticket']));
    } catch (_) {}
  }

  Future<void> _issue() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService().issueTicket(widget.service.id);
      setState(() => _ticket = TicketModel.fromJson(res.data['ticket']));
      _startTimer();
      if (!mounted) return;
      final ahead = _ticket!.ahead;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ahead == 0
            ? 'You are next! 🎉'
            : '$ahead ticket${ahead > 1 ? 's' : ''} before you'),
        backgroundColor: kPrimary,
      ));
    } on DioException catch (e) {
      if (!mounted) return;
      final existing = e.response?.data is Map
          ? (e.response!.data as Map)['ticket']
          : null;
      if (e.response?.statusCode == 409 && existing is Map) {
        setState(() =>
            _ticket = TicketModel.fromJson(Map<String, dynamic>.from(existing)));
        _startTimer();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('You already have an active ticket for this service.'),
            backgroundColor: kPrimary));
        return;
      }
      final msg = e.response?.data is Map
          ? (e.response!.data['error'] ?? 'Failed to take ticket.')
          : 'Failed to take ticket.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg), backgroundColor: kRed));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to take ticket. Please try again.'),
          backgroundColor: kRed));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm() async {
    if (_ticket == null || _ticket!.confirmationCount >= 3) return;
    setState(() => _confirming = true);
    try {
      final res = await ApiService().confirmTicket(_ticket!.id);
      setState(() => _ticket = TicketModel.fromJson(res.data['ticket']));
      if (!mounted) return;
      final left = res.data['confirmations_left'] as int;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(left > 0
            ? 'Confirmed (${_ticket!.confirmationCount}/3). $left more needed.'
            : 'Fully confirmed! Please head to the counter. ✅'),
        backgroundColor: kPrimary,
      ));
    } catch (_) {
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<void> _cancel() async {
    if (_ticket == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel Ticket'),
        content: const Text('Are you sure you want to cancel your ticket?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes, Cancel', style: TextStyle(color: kRed))),
        ],
      ),
    );
    if (ok != true) return;
    await ApiService().cancelTicket(_ticket!.id);
    setState(() => _ticket = null);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.service.name)),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _ticket == null ? _buildIssueView() : _buildTicketView(),
        ),
      );

  Widget _buildIssueView() {
    final service = widget.service;
    final approxWait = service.todayInQueue * service.todayAvgWait;
    
    return Column(
      children: [
        // Premium Service Header Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2D6BE4), Color(0xFF378ADD)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2D6BE4).withOpacity(0.2),
                blurRadius: 15,
                offset: const Offset(0, 8),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.business, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 20),
              Text(
                service.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, color: Colors.white70, size: 14),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      service.address ?? 'No address listed',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 20),
        
        // 3-Column Stats Dashboard
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: kGray200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'LIVE QUEUE OVERVIEW',
                style: TextStyle(color: kGray400, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.0),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('👥 En attente', style: TextStyle(color: kGray500, fontSize: 11, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text('${service.todayInQueue}', style: const TextStyle(color: kGray800, fontSize: 20, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                  Container(width: 1, height: 40, color: kGray200),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('🪟 Guichets ouverts', style: TextStyle(color: kGray500, fontSize: 11, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text(
                        '${service.openGuichets}',
                        style: TextStyle(
                          color: service.openGuichets > 0 ? const Color(0xFF1BA87A) : kRed,
                          fontSize: 20, fontWeight: FontWeight.w800,
                        ),
                      ),
                    ]),
                  ),
                  Container(width: 1, height: 40, color: kGray200),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('⏰ Attente approx.', style: TextStyle(color: kGray500, fontSize: 11, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text('~$approxWait min', style: const TextStyle(color: kGray800, fontSize: 20, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 28),
        
        // Take Ticket Action Button
        ElevatedButton.icon(
          onPressed: _loading ? null : _issue,
          icon: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.add_circle_outline),
          label: const Text('Take a Ticket Now'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 56),
            backgroundColor: kPrimary,
            foregroundColor: Colors.white,
            elevation: 2,
            shadowColor: kPrimary.withOpacity(0.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ].animate().fadeIn(duration: 350.ms),
    );
  }

  Widget _buildTicketView() {
    final t = _ticket!;
    final needsConfirm = t.ahead <= 4 &&
        t.confirmationCount < 3 &&
        ['waiting', 'called'].contains(t.status);
    final paddedNumber = t.ticketNumber.toString().padLeft(3, '0');

    return Column(children: [
      // Premium Physical Ticket card
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: kGray200),
          boxShadow: [
            BoxShadow(
                color: kPrimary.withOpacity(0.06),
                blurRadius: 20,
                offset: const Offset(0, 10))
          ],
        ),
        child: Stack(
          children: [
            Column(
              children: [
                // Top Header of the Ticket
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF2D6BE4), Color(0xFF378ADD)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(23)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.business, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.service.name.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      StatusBadge(t.status),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Ticket Padded Number Display
                const Text(
                  'TICKET NUMBER',
                  style: TextStyle(
                    color: kGray400,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  paddedNumber,
                  style: const TextStyle(
                    fontSize: 76,
                    fontWeight: FontWeight.w900,
                    color: kPrimary,
                    height: 1.0,
                    letterSpacing: 2,
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Custom Dashed Tear Line with notches on sides
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: List.generate(
                      24,
                      (i) => Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          height: 1.5,
                          color: i % 2 == 0 ? Colors.transparent : kGray300,
                        ),
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Bottom part details: Stats Row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      // Stat 1: Ahead
                      Expanded(
                        child: GestureDetector(
                          onTap: _refreshAhead,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: t.ahead == 0 ? const Color(0xFFE4F7F0) : kPrimaryLight,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  t.ahead == 0 ? '🎉' : '👥',
                                  style: const TextStyle(fontSize: 22),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  t.ahead == 0 ? 'Next' : '${t.ahead}',
                                  style: TextStyle(
                                    color: t.ahead == 0 ? const Color(0xFF1BA87A) : kPrimary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 20,
                                  ),
                                ),
                                Text(
                                  t.ahead == 0 ? 'Your turn!' : 'Ahead of you',
                                  style: TextStyle(
                                    color: t.ahead == 0 ? const Color(0xFF1BA87A).withOpacity(0.8) : kPrimary.withOpacity(0.8),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Stat 2: Wait
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: kGray100,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              const Text('⏰', style: TextStyle(fontSize: 22)),
                              const SizedBox(height: 4),
                              Text(
                                '~${t.estimatedWaitMin ?? 0} min',
                                style: const TextStyle(
                                  color: kGray800,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20,
                                ),
                              ),
                              const Text(
                                'Est. Wait Time',
                                style: TextStyle(
                                  color: kGray500,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // QR Code
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kGray50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: kGray100),
                    ),
                    child: QrImageView(
                      data: t.qrCode,
                      size: 130,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: kPrimary,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: kPrimary,
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Tap to refresh hint
                TextButton.icon(
                  onPressed: _refreshAhead,
                  icon: const Icon(Icons.refresh, size: 14, color: kGray500),
                  label: const Text(
                    'Tap to refresh live status',
                    style: TextStyle(color: kGray500, fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // Progress
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: QueueProgress(ahead: t.ahead, total: 20),
                ),
                
                const SizedBox(height: 24),
              ],
            ),
            
            // Side Circle Notches (Paper Ticket Cutouts)
            Positioned(
              left: -12,
              top: 174, // Centered vertically around the dashed divider
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: kGray100, // Matches background color of the scaffold
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              right: -12,
              top: 174,
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: kGray100,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ).animate().scale(begin: const Offset(0.95, 0.95)).fadeIn(duration: 300.ms),

      // Alert banner when close
      if (needsConfirm) ...[
        const SizedBox(height: 16),
        AlertBanner(
          title: '⏰ Almost your turn!',
          body:
              'You are ${t.ahead} tickets away. Please confirm you will arrive (${t.confirmationCount}/3).',
        ).animate().shake(),
      ],

      // Confirmation dots
      if (['waiting', 'called', 'confirmed'].contains(t.status)) ...[
        const SizedBox(height: 16),
        AppCard(
            child: Column(children: [
          const Text('Arrival Confirmations',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          ConfirmDots(filled: t.confirmationCount),
          const SizedBox(height: 4),
          Text('${t.confirmationCount}/3 confirmed',
              style: const TextStyle(color: kGray600, fontSize: 12)),
        ])),
      ],

      const SizedBox(height: 20),

      // Actions
      if (needsConfirm)
        ElevatedButton.icon(
          onPressed: _confirming ? null : _confirm,
          icon: _confirming
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.check_circle_outline),
          label: Text('Confirm Arrival (${t.confirmationCount}/3)'),
          style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52)),
        ),

      // Confirmation button when ticket is called
      if (t.status == 'called') ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kAmberLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kAmber.withOpacity(0.4)),
          ),
          child: Column(children: [
            const Row(children: [
              Icon(Icons.campaign, color: kAmber, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "C'est votre tour ! Confirmez votre présence",
                  style: TextStyle(color: kAmber, fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            const Text(
              'Si vous ne confirmez pas, votre ticket sera annulé automatiquement.',
              style: TextStyle(color: kAmber, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _confirming ? null : _confirm,
                  icon: _confirming
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.check_circle, size: 18),
                  label: const Text('Je suis là ✅'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _cancel,
                  icon: const Icon(Icons.cancel_outlined, color: kRed, size: 18),
                  label: const Text('Annuler'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kRed,
                    side: const BorderSide(color: kRed),
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ],

      if (t.isActive && t.status != 'called') ...[
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _cancel,
          icon: const Icon(Icons.cancel_outlined, color: kRed),
          label: const Text('Annuler mon ticket'),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              foregroundColor: kRed,
              side: const BorderSide(color: kRed)),
        ),
      ],
    ]);
  }
}

class _MyTicketsScreen extends StatefulWidget {
  const _MyTicketsScreen();
  @override
  State<_MyTicketsScreen> createState() => _MyTicketsScreenState();
}

class _MyTicketsScreenState extends State<_MyTicketsScreen> {
  List<TicketModel> _tickets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService().getMyTickets();
      setState(() {
        _tickets = (res.data['tickets'] as List)
            .map((j) => TicketModel.fromJson(j))
            .toList();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('My Tickets')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _tickets.isEmpty
                ? const EmptyState(
                    icon: '🎫',
                    title: 'No tickets yet',
                    subtitle: 'Take a ticket from a service to see it here')
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _tickets.length,
                    itemBuilder: (_, i) {
                      final t = _tickets[i];
                      return AppCard(
                        child: Row(children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                                color: kPrimaryLight,
                                borderRadius: BorderRadius.circular(14)),
                            child: Center(
                                child: Text(
                                    t.ticketNumber.toString().padLeft(3, '0'),
                                    style: const TextStyle(
                                        color: kPrimary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800))),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text('Queue #${t.queueId}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14)),
                                Text(t.issuedAt.substring(0, 16),
                                    style: const TextStyle(
                                        color: kGray600, fontSize: 12)),
                                if (t.isActive)
                                  Text(
                                      '${t.ahead} ahead · ~${t.estimatedWaitMin ?? 0} min',
                                      style: const TextStyle(
                                          color: kGray600, fontSize: 11)),
                              ])),
                          StatusBadge(t.status),
                        ]),
                      );
                    }),
      );
}
