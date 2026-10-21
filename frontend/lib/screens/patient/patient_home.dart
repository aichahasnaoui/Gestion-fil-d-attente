import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:badges/badges.dart' as badges;
import '../../constants.dart';
import '../../api_service.dart';
import '../../models.dart';
import '../../shared_widgets.dart';
import '../../providers/notification_provider.dart';
import '../../models.dart';
import 'patient_appointments.dart';
import 'patient_records.dart';
import '../chat_screens.dart';
import '../shared/notifications_screen.dart';
import '../shared/profile_screen.dart';
import '../../socket_service.dart';

class PatientHome extends StatefulWidget {
  const PatientHome({super.key});
  @override
  State<PatientHome> createState() => _PatientHomeState();
}

class _PatientHomeState extends State<PatientHome> {
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
            'Confirmez votre présence maintenant.\nSi vous ne confirmez pas, votre ticket sera annulé automatiquement.',
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
      _PatientDashboard(user: _user),
      const PatientAppointmentsScreen(),
      const PatientRecordsScreen(),
      const ConversationsScreen(),
      const NotificationsScreen(),
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
            label: 'Accueil',
          ),
          const NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month, color: kPrimary),
            label: 'Rendez-vous',
          ),
          const NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder, color: kPrimary),
            label: 'Dossiers',
          ),
          const NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble, color: kPrimary),
            label: 'Messages',
          ),
          NavigationDestination(
            icon: badges.Badge(
              showBadge: unread > 0,
              badgeContent: Text('$unread',
                  style: const TextStyle(color: Colors.white, fontSize: 10)),
              child: const Icon(Icons.notifications_outlined),
            ),
            selectedIcon: const Icon(Icons.notifications, color: kPrimary),
            label: 'Alertes',
          ),
        ],
      ),
    );
  }
}

class _PatientDashboard extends StatefulWidget {
  final UserModel? user;
  const _PatientDashboard({this.user});
  @override
  State<_PatientDashboard> createState() => _PatientDashboardState();
}

class _PatientDashboardState extends State<_PatientDashboard> {
  List<DoctorModel> _doctors = [];
  List<AppointmentModel> _upcoming = [];
  TicketModel? _activeTicket;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    SocketService().on('queue_update', _onQueueUpdate);
  }

  @override
  void dispose() {
    SocketService().off('queue_update');
    if (_activeTicket != null) {
      SocketService().leaveServiceRoom(_activeTicket!.serviceId);
    }
    super.dispose();
  }

  void _onQueueUpdate(data) {
    if (_activeTicket != null && data['service_id'] == _activeTicket!.serviceId) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final docRes = await ApiService().listDoctors();
      if (mounted) {
        setState(() {
          _doctors = (docRes.data['doctors'] as List)
              .map((j) => DoctorModel.fromJson(j))
              .toList();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Doctors load error: $e');
      if (mounted) setState(() => _loading = false);
    }

    try {
      final apptRes = await ApiService().getMyAppointments();
      if (mounted) {
        setState(() {
          _upcoming = (apptRes.data['appointments'] as List)
              .map((j) => AppointmentModel.fromJson(j))
              .where((a) => ['pending', 'accepted', 'confirmed'].contains(a.status))
              .take(3)
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Appointments load error: $e');
    }

    try {
      final ticketRes = await ApiService().getMyTickets();
      if (mounted) {
        final tickets = (ticketRes.data['tickets'] as List)
            .map((j) => TicketModel.fromJson(j))
            .where((t) => t.isActive)
            .toList();
        final newTicket = tickets.isNotEmpty ? tickets.first : null;

        // Fetch fresh ahead count for the active ticket
        TicketModel? freshTicket = newTicket;
        if (newTicket != null) {
          try {
            final fresh = await ApiService().getTicket(newTicket.id);
            freshTicket = TicketModel.fromJson(fresh.data['ticket']);
          } catch (_) {}
        }

        if (mounted) {
          setState(() {
            if (_activeTicket != null &&
                (freshTicket == null || freshTicket.serviceId != _activeTicket!.serviceId)) {
              SocketService().leaveServiceRoom(_activeTicket!.serviceId);
            }
            if (freshTicket != null &&
                (_activeTicket == null || _activeTicket!.serviceId != freshTicket.serviceId)) {
              SocketService().joinServiceRoom(freshTicket.serviceId);
            }
            _activeTicket = freshTicket;
          });
        }
      }
    } catch (e) {
      debugPrint('Tickets load error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return Scaffold(
      backgroundColor: kGray100,
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [kPrimary, Color(0xFF1BA87A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius:
                      BorderRadius.vertical(bottom: Radius.circular(28)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 56, 20, 28),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        GestureDetector(
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const ProfileScreen())),
                          child: AvatarCircle(
                            initials: user?.initials ?? '?',
                            size: 46,
                            bg: Colors.white24,
                            fg: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(
                                  'Bonjour, ${user?.fullName.split(' ').first ?? ''} !',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700)),
                              const Text("Comment vous sentez-vous aujourd'hui ?",
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 13)),
                            ])),
                      ]),
                      const SizedBox(height: 20),
                      // Quick stats
                      Row(children: [
                        _StatChip(
                            icon: Icons.calendar_today,
                            label: '${_upcoming.length} à venir'),
                        const SizedBox(width: 10),
                        _StatChip(
                            icon: Icons.people_outline,
                            label: '${_doctors.length} médecins'),
                      ]),
                    ]),
              ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1),
            ),

            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                  delegate: SliverChildListDelegate([
                // Quick actions
                const SectionHeader(title: 'Actions rapides'),
                const SizedBox(height: 8),
                Row(children: [
                  _QuickAction(
                      icon: Icons.search,
                      label: 'Trouver un médecin',
                      color: kPrimary,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const _FindDoctorScreen()))),
                  const SizedBox(width: 10),
                  _QuickAction(
                      icon: Icons.confirmation_number_outlined,
                      label: 'Prendre un ticket',
                      color: const Color(0xFF1BA87A),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const _PatientTicketScreen()))),
                  const SizedBox(width: 10),
                  _QuickAction(
                      icon: Icons.medication_outlined,
                      label: 'Ordonnances',
                      color: const Color(0xFFF57C2B),
                      onTap: () {}),
                ]).animate().fadeIn(delay: 100.ms),

                const SizedBox(height: 20),
                // Active Ticket section
                _ActiveTicketSection(),
                const SizedBox(height: 20),

                // Upcoming appointments
                if (_upcoming.isNotEmpty) ...[
                  SectionHeader(
                      title: 'Rendez-vous à venir',
                      action: TextButton(
                          onPressed: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const PatientAppointmentsScreen())),
                          child: const Text('Tout voir',
                              style: TextStyle(color: kPrimary)))),
                  ..._upcoming
                      .map((a) => _UpcomingApptCard(appt: a))
                      .toList()
                      .animate(interval: 80.ms)
                      .fadeIn()
                      .slideX(begin: 0.1),
                  const SizedBox(height: 12),
                ],

                // Doctors
                SectionHeader(
                    title: 'Médecins disponibles',
                    action: TextButton(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _FindDoctorScreen())),
                        child: const Text('Tout voir',
                            style: TextStyle(color: kPrimary)))),
                const SizedBox(height: 4),
                if (_loading)
                  ...List.generate(3, (_) => const ShimmerCard())
                else if (_doctors.isEmpty)
                  const EmptyState(
                      icon: '👨‍⚕️',
                      title: 'Aucun médecin trouvé',
                      subtitle: 'Revenez plus tard')
                else
                  ..._doctors
                      .map((d) => _DoctorCard(doctor: d))
                      .toList()
                      .animate(interval: 60.ms)
                      .fadeIn()
                      .slideX(begin: 0.05),
              ])),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ActiveTicketSection() {
    if (_activeTicket == null) return const SizedBox.shrink();
    final t = _activeTicket!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Votre ticket actif'),
        const SizedBox(height: 8),
        AppCard(
          onTap: () async {
            try {
              // Refresh ticket data first
              final res = await ApiService().getTicket(t.id);
              final fresh = TicketModel.fromJson(res.data['ticket']);
              if (mounted) setState(() => _activeTicket = fresh);
              final svcRes = await ApiService().getService(t.serviceId);
              final service = ServiceModel.fromJson(svcRes.data['service']);
              if (!mounted) return;
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => _PatientTakeTicketScreen(service: service)));
            } catch (_) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Impossible de charger le service.'),
                  backgroundColor: kRed));
            }
          },
          child: Row(children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [kPrimary, Color(0xFF1BA87A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  t.ticketNumber.toString().padLeft(3, '0'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TICKET ACTIF',
                    style: TextStyle(
                      color: kPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    t.ahead == 0
                        ? 'Vous êtes le prochain !'
                        : '${t.ahead} personne(s) devant vous',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: kGray900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '~${(t.estimatedWaitMin ?? 0)} min d\'attente estimée',
                    style: const TextStyle(color: kGray500, fontSize: 11),
                  ),
                ],
              ),
            ),
            StatusBadge(t.status),
          ]),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatChip({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
            color: Colors.white24, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ]),
      );
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickAction(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kGray200),
            ),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 8),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: kGray900)),
            ]),
          ),
        ),
      );
}

class _UpcomingApptCard extends StatelessWidget {
  final AppointmentModel appt;
  const _UpcomingApptCard({required this.appt});

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      const months = ['Jan','Fév','Mar','Avr','Mai','Jun','Jul','Aoû','Sep','Oct','Nov','Déc'];
      return '${dt.day} ${months[dt.month - 1]} à ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    } catch (_) { return iso.length > 16 ? iso.substring(0, 16) : iso; }
  }

  @override
  Widget build(BuildContext context) => AppCard(
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
                color: kPrimaryLight, borderRadius: BorderRadius.circular(12)),
            child: Center(
              child: Text(
                (appt.doctorName ?? 'Dr').trim().split(' ').take(2)
                    .map((w) => w.isNotEmpty ? w[0] : '').join().toUpperCase(),
                style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Dr. ${appt.doctorName ?? 'Inconnu'}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                if (appt.doctorSpecialty != null && appt.doctorSpecialty!.isNotEmpty)
                  Text(_specialtyLabel(appt.doctorSpecialty!),
                      style: const TextStyle(color: kPrimary, fontSize: 11, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Row(children: [
                  const Icon(Icons.access_time, size: 11, color: kGray400),
                  const SizedBox(width: 3),
                  Text(_formatDate(appt.scheduledAt),
                      style: const TextStyle(color: kGray600, fontSize: 11)),
                ]),
                if (appt.reason != null && appt.reason!.isNotEmpty)
                  Text(appt.reason!, style: const TextStyle(color: kGray400, fontSize: 11),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
          StatusBadge(appt.status),
        ]),
      );
}

class _DoctorCard extends StatelessWidget {
  final DoctorModel doctor;
  const _DoctorCard({required this.doctor});
  @override
  Widget build(BuildContext context) => AppCard(
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => _BookAppointmentSheet(doctor: doctor))),
        child: Row(children: [
          AvatarCircle(
              initials: doctor.user.initials,
              size: 48,
              bg: kPrimaryLight,
              fg: kPrimary),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(doctor.user.fullName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                Text(_specialtyLabel(doctor.specialty),
                    style: const TextStyle(
                        color: kPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.access_time, size: 12, color: kGray400),
                  const SizedBox(width: 4),
                  Text('${doctor.consultationMinutes} min',
                      style: const TextStyle(color: kGray600, fontSize: 11)),
                  const SizedBox(width: 10),
                  Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                          color: doctor.isAccepting
                              ? const Color(0xFF22C55E)
                              : kRed,
                          shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text(doctor.isAccepting ? 'Disponible' : 'Indisponible',
                      style: TextStyle(
                          color: doctor.isAccepting
                              ? const Color(0xFF22C55E)
                              : kRed,
                          fontSize: 11)),
                ]),
              ])),
          const Icon(Icons.chevron_right, color: kGray400),
        ]),
      );
}

// ── Page prendre un ticket pour le patient ──────────────────────────────────
class _PatientTicketScreen extends StatefulWidget {
  const _PatientTicketScreen();
  @override
  State<_PatientTicketScreen> createState() => _PatientTicketScreenState();
}

class _PatientTicketScreenState extends State<_PatientTicketScreen> {
  List<ServiceModel> _all = [];
  List<ServiceModel> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  String? _selectedType;

  static const _types = [
    {'key': null,       'label': 'Tous',      'icon': Icons.apps},
    {'key': 'bank',     'label': 'Banque',    'icon': Icons.account_balance},
    {'key': 'post',     'label': 'Poste',     'icon': Icons.local_post_office},
    {'key': 'telecom',  'label': 'Télécom',   'icon': Icons.phone_android},
    {'key': 'cnss',     'label': 'CNSS',      'icon': Icons.security},
    {'key': 'hospital', 'label': 'Hôpital',   'icon': Icons.local_hospital},
    {'key': 'clinic',   'label': 'Clinique',  'icon': Icons.medical_services},
  ];

  static const _typeColors = {
    'bank':     Color(0xFF1BA87A),
    'post':     Color(0xFFF57C2B),
    'telecom':  Color(0xFF2D6BE4),
    'cnss':     Color(0xFF7F77DD),
    'hospital': Color(0xFFE24B4A),
    'clinic':   Color(0xFF0F6E56),
  };

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService().getServices();
      setState(() {
        _all = (res.data['services'] as List)
            .map((j) => ServiceModel.fromJson(j))
            .toList();
        _filtered = List.from(_all);
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = _all.where((s) {
        final matchName = s.name.toLowerCase().contains(q);
        final matchAddr = (s.address ?? '').toLowerCase().contains(q);
        final matchType = _selectedType == null || s.type == _selectedType;
        return (matchName || matchAddr) && matchType;
      }).toList();
    });
  }

  void _selectType(String? type) {
    setState(() => _selectedType = type);
    _filter();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: kGray100,
        body: CustomScrollView(slivers: [
          // Header with search
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [kPrimary, Color(0xFF1BA87A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Prendre un ticket',
                          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                      Text('Choisissez un service et évitez la file',
                          style: TextStyle(color: Colors.white70, fontSize: 13)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 16),
                // Search bar
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Rechercher un service ou une adresse...',
                      hintStyle: const TextStyle(color: kGray400, fontSize: 14),
                      prefixIcon: const Icon(Icons.search, color: kGray400),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: kGray400),
                              onPressed: () { _searchCtrl.clear(); _filter(); })
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ]),
            ),
          ),

          // Type filter chips
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _types.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final t = _types[i];
                    final key = t['key'] as String?;
                    final selected = _selectedType == key;
                    return GestureDetector(
                      onTap: () => _selectType(key),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected ? kPrimary : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: selected ? kPrimary : kGray200),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(t['icon'] as IconData,
                              size: 13,
                              color: selected ? Colors.white : kGray600),
                          const SizedBox(width: 5),
                          Text(t['label'] as String,
                              style: TextStyle(
                                  color: selected ? Colors.white : kGray600,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500)),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          // Results count
          if (!_loading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Text(
                  '${_filtered.length} service(s) trouvé(s)',
                  style: const TextStyle(color: kGray500, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
            ),

          // Services list
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            sliver: _loading
                ? SliverList(
                    delegate: SliverChildListDelegate(
                        List.generate(4, (_) => const ShimmerCard())))
                : _filtered.isEmpty
                    ? SliverToBoxAdapter(
                        child: EmptyState(
                          icon: '🏢',
                          title: _searchCtrl.text.isNotEmpty
                              ? 'Aucun résultat pour "${_searchCtrl.text}"'
                              : 'Aucun service disponible',
                          subtitle: 'Essayez une autre recherche ou catégorie',
                        ))
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) {
                            final s = _filtered[i];
                            final color = _typeColors[s.type] ?? kPrimary;
                            return AppCard(
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => _PatientTakeTicketScreen(service: s))),
                              child: Row(children: [
                                Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                      color: color.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(14)),
                                  child: Icon(Icons.business, color: color, size: 26),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                      Text(s.name,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700, fontSize: 15)),
                                      if ((s.address ?? '').isNotEmpty)
                                        Row(children: [
                                          const Icon(Icons.location_on_outlined,
                                              size: 11, color: kGray400),
                                          const SizedBox(width: 3),
                                          Expanded(
                                            child: Text(s.address!,
                                                style: const TextStyle(
                                                    color: kGray500, fontSize: 11),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis),
                                          ),
                                        ]),
                                      const SizedBox(height: 6),
                                      Row(children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                              color: color.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(20)),
                                          child: Text('${s.todayInQueue} en attente',
                                              style: TextStyle(
                                                  color: color,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600)),
                                        ),
                                        const SizedBox(width: 8),
                                        const Icon(Icons.access_time,
                                            size: 11, color: kGray400),
                                        const SizedBox(width: 3),
                                        Text('~${s.todayAvgWait} min',
                                            style: const TextStyle(
                                                color: kGray600, fontSize: 11)),
                                      ]),
                                    ])),
                                const Icon(Icons.chevron_right, color: kGray400),
                              ]),
                            );
                          },
                          childCount: _filtered.length,
                        )),
          ),
        ]),
      );
}

class _PatientTakeTicketScreen extends StatefulWidget {
  final ServiceModel service;
  const _PatientTakeTicketScreen({required this.service});
  @override
  State<_PatientTakeTicketScreen> createState() =>
      _PatientTakeTicketScreenState();
}

class _PatientTakeTicketScreenState extends State<_PatientTakeTicketScreen> {
  TicketModel? _ticket;
  bool _loading = false;
  Timer? _timer;
  late final Function(dynamic) _queueHandler;

  @override
  void initState() {
    super.initState();
    _queueHandler = (data) {
      if (data is Map && data['service_id'] == widget.service.id) {
        _refresh();
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
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
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
            ? 'Vous êtes le prochain !'
            : '$ahead personne(s) devant vous'),
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
            content: Text('Vous avez deja un ticket actif pour ce service.'),
            backgroundColor: kPrimary));
        return;
      }
      final msg = e.response?.data is Map
          ? (e.response!.data['error'] ?? 'Impossible de prendre un ticket.')
          : 'Impossible de prendre un ticket.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg), backgroundColor: kRed));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Impossible de prendre un ticket. Veuillez reessayer.'),
          backgroundColor: kRed));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    if (_ticket == null || !_ticket!.isActive) return;
    try {
      final res = await ApiService().getTicket(_ticket!.id);
      if (mounted)
        setState(() => _ticket = TicketModel.fromJson(res.data['ticket']));
    } catch (_) {}
  }

  Future<void> _cancel() async {
    if (_ticket == null) return;
    await ApiService().cancelTicket(_ticket!.id);
    if (mounted) setState(() => _ticket = null);
  }

  Future<void> _confirm() async {
    if (_ticket == null || _ticket!.confirmationCount >= 3) return;
    setState(() => _loading = true);
    try {
      final res = await ApiService().confirmTicket(_ticket!.id);
      if (mounted) setState(() => _ticket = TicketModel.fromJson(res.data['ticket']));
      if (!mounted) return;
      final left = 3 - _ticket!.confirmationCount;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(left > 0
            ? 'Présence confirmée (${_ticket!.confirmationCount}/3). Encore $left confirmation(s).'
            : 'Présence totalement confirmée ! Préparez-vous ✅'),
        backgroundColor: kPrimary,
      ));
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
              colors: [kPrimary, Color(0xFF1BA87A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: kPrimary.withOpacity(0.2),
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
                      service.address ?? 'Aucune adresse renseignée',
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
                'APERÇU DE LA FILE EN DIRECT',
                style: TextStyle(
                  color: kGray400,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  // Stat 1: Queue length
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('👥 En Attente', style: TextStyle(color: kGray500, fontSize: 11, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Text('${service.todayInQueue}', style: const TextStyle(color: kGray800, fontSize: 20, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 40, color: kGray200),
                  const SizedBox(width: 12),
                  // Stat 2: Guichets ouverts
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('🪟 Guichets', style: TextStyle(color: kGray500, fontSize: 11, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Text(
                          '${service.openGuichets} ouvert(s)',
                          style: TextStyle(
                            color: service.openGuichets > 0 ? const Color(0xFF1BA87A) : kRed,
                            fontSize: 16, fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 40, color: kGray200),
                  const SizedBox(width: 12),
                  // Stat 3: Approx Wait
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('⏰ Attente', style: TextStyle(color: kGray500, fontSize: 11, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Text('~$approxWait min', style: const TextStyle(color: kGray800, fontSize: 20, fontWeight: FontWeight.w800)),
                      ],
                    ),
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
          label: const Text('Prendre un ticket maintenant'),
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
                      colors: [kPrimary, Color(0xFF1BA87A)],
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
                  'NUMÉRO DE TICKET',
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
                          onTap: _refresh,
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
                                  t.ahead == 0 ? 'Suivant' : '${t.ahead}',
                                  style: TextStyle(
                                    color: t.ahead == 0 ? const Color(0xFF1BA87A) : kPrimary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 20,
                                  ),
                                ),
                                Text(
                                  t.ahead == 0 ? 'À vous !' : 'Devant vous',
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
                                'Attente Est.',
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
                
                // Tap to refresh hint
                TextButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh, size: 14, color: kGray500),
                  label: const Text(
                    'Appuyez pour actualiser',
                    style: TextStyle(color: kGray500, fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ),
                
                const SizedBox(height: 16),
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

      // ── Confirmation de présence (3 fois) ──────────────────────────────
      if (['waiting', 'called', 'confirmed'].contains(t.status) && t.confirmationCount < 3) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kPrimaryLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kPrimary.withOpacity(0.2)),
          ),
          child: Column(children: [
            Row(children: [
              const Icon(Icons.info_outline, color: kPrimary, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Confirmez votre présence (${t.confirmationCount}/3) pour accélérer votre passage',
                  style: const TextStyle(color: kPrimary, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              ...List.generate(3, (i) => Container(
                width: 12, height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < t.confirmationCount ? kPrimary : Colors.transparent,
                  border: Border.all(color: kPrimary, width: 2),
                ),
              )),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _confirm,
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text('Confirmer ma présence (${t.confirmationCount}/3)'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ]),
        ),
      ],

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
                  onPressed: _loading ? null : _confirm,
                  icon: const Icon(Icons.check_circle, size: 18),
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
          label: const Text('Annuler le ticket'),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              foregroundColor: kRed,
              side: const BorderSide(color: kRed)),
        ),
      ],
    ]);
  }
}

// ── Page recherche médecins ──────────────────────────────────────────────────
String _specialtyLabel(String specialty) => switch (specialty) {
      'All' => 'Toutes',
      'General Medicine' => 'Médecine générale',
      'Cardiology' => 'Cardiologie',
      'Dermatology' => 'Dermatologie',
      'Pediatrics' => 'Pédiatrie',
      'Gynecology' => 'Gynécologie',
      'Orthopedics' => 'Orthopédie',
      'Neurology' => 'Neurologie',
      'Ophthalmology' => 'Ophtalmologie',
      _ => specialty,
    };

class _FindDoctorScreen extends StatefulWidget {
  const _FindDoctorScreen();
  @override
  State<_FindDoctorScreen> createState() => _FindDoctorScreenState();
}

class _FindDoctorScreenState extends State<_FindDoctorScreen> {
  final _searchCtrl = TextEditingController();
  List<DoctorModel> _all = [];
  List<DoctorModel> _filtered = [];
  String? _selectedSpecialty;
  bool _loading = true;

  static const _specialties = [
    'All',
    'General Medicine',
    'Cardiology',
    'Dermatology',
    'Pediatrics',
    'Gynecology',
    'Orthopedics',
    'Neurology',
    'Ophthalmology',
  ];

  static const _specialtyIcons = {
    'General Medicine': Icons.medical_services,
    'Cardiology': Icons.favorite,
    'Dermatology': Icons.face,
    'Pediatrics': Icons.child_care,
    'Gynecology': Icons.pregnant_woman,
    'Orthopedics': Icons.accessibility_new,
    'Neurology': Icons.psychology,
    'Ophthalmology': Icons.visibility,
  };

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService().listDoctors();
      setState(() {
        _all = (res.data['doctors'] as List)
            .map((j) => DoctorModel.fromJson(j))
            .toList();
        _filtered = List.from(_all);
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = _all.where((d) {
        final matchName = d.user.fullName.toLowerCase().contains(q);
        final matchSpec = d.specialty.toLowerCase().contains(q);
        final matchSpecFilter = _selectedSpecialty == null ||
            _selectedSpecialty == 'All' ||
            d.specialty == _selectedSpecialty;
        return (matchName || matchSpec) && matchSpecFilter;
      }).toList();
    });
  }

  void _selectSpecialty(String s) {
    setState(() => _selectedSpecialty = s == 'All' ? null : s);
    _filter();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: kGray100,
        body: CustomScrollView(slivers: [
          // Header avec barre de recherche
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [kPrimary, Color(0xFF1BA87A)],
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
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.arrow_back_ios,
                            color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Médecins à Gabes',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700)),
                              Text('Trouvez et réservez votre rendez-vous',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 13)),
                            ]),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    // Barre de recherche
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 10,
                              offset: const Offset(0, 4))
                        ],
                      ),
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Rechercher par nom ou spécialité...',
                          hintStyle:
                              const TextStyle(color: kGray400, fontSize: 14),
                          prefixIcon: const Icon(Icons.search, color: kGray400),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon:
                                      const Icon(Icons.clear, color: kGray400),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    _filter();
                                  })
                              : null,
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ]),
            ),
          ),

          // Filtres spécialité
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _specialties.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final s = _specialties[i];
                    final selected =
                        (s == 'All' && _selectedSpecialty == null) ||
                            s == _selectedSpecialty;
                    return GestureDetector(
                      onTap: () => _selectSpecialty(s),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected ? kPrimary : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border:
                              Border.all(color: selected ? kPrimary : kGray200),
                        ),
                        child: Text(
                          _specialtyLabel(s),
                          style: TextStyle(
                            color: selected ? Colors.white : kGray600,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          // Résultats
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: _loading
                ? SliverList(
                    delegate: SliverChildListDelegate(
                        List.generate(4, (_) => const ShimmerCard())))
                : _filtered.isEmpty
                    ? SliverToBoxAdapter(
                        child: EmptyState(
                        icon: '👨‍⚕️',
                        title: _searchCtrl.text.isNotEmpty
                            ? 'Aucun résultat pour "${_searchCtrl.text}"'
                            : 'Aucun médecin trouvé',
                        subtitle: 'Essayez une autre recherche ou spécialité',
                      ))
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                        (_, i) => _FindDoctorCard(doctor: _filtered[i])
                            .animate(delay: (i * 50).ms)
                            .fadeIn()
                            .slideY(begin: 0.05),
                        childCount: _filtered.length,
                      )),
          ),
        ]),
      );
}

class _FindDoctorCard extends StatelessWidget {
  final DoctorModel doctor;
  const _FindDoctorCard({required this.doctor});

  static const _specColors = {
    'Cardiology': Color(0xFFE24B4A),
    'Dermatology': Color(0xFFF57C2B),
    'Pediatrics': Color(0xFF2D6BE4),
    'Gynecology': Color(0xFF7F77DD),
    'Orthopedics': Color(0xFF1BA87A),
    'Neurology': Color(0xFF0F6E56),
    'Ophthalmology': Color(0xFF378ADD),
    'General Medicine': Color(0xFF2D6BE4),
  };

  @override
  Widget build(BuildContext context) {
    final color = _specColors[doctor.specialty] ?? kPrimary;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            // Avatar
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(doctor.user.initials,
                    style: TextStyle(
                        color: color,
                        fontSize: 20,
                        fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(doctor.user.fullName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: kGray900)),
                  const SizedBox(height: 3),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(_specialtyLabel(doctor.specialty),
                          style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.location_on_outlined,
                        size: 12, color: kGray400),
                    const SizedBox(width: 3),
                    const Text('Gabes',
                        style: TextStyle(color: kGray400, fontSize: 11)),
                    const SizedBox(width: 10),
                    const Icon(Icons.access_time, size: 12, color: kGray400),
                    const SizedBox(width: 3),
                    Text('${doctor.consultationMinutes} min',
                        style: const TextStyle(color: kGray400, fontSize: 11)),
                  ]),
                ])),
            // Disponibilité
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: doctor.isAccepting
                      ? const Color(0xFFE4F7F0)
                      : const Color(0xFFFCEBEB),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color:
                          doctor.isAccepting ? const Color(0xFF1BA87A) : kRed,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(doctor.isAccepting ? 'Disponible' : 'Occupé',
                      style: TextStyle(
                        color:
                            doctor.isAccepting ? const Color(0xFF1BA87A) : kRed,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      )),
                ]),
              ),
            ]),
          ]),
          const SizedBox(height: 14),
          // Bouton rendez-vous
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: doctor.isAccepting
                  ? () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              _BookAppointmentSheet(doctor: doctor)))
                  : null,
              icon: const Icon(Icons.calendar_today, size: 16),
              label: const Text('Prendre rendez-vous'),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                textStyle:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Page prise de rendez-vous ────────────────────────────────────────────────
class _BookAppointmentSheet extends StatefulWidget {
  final DoctorModel doctor;
  const _BookAppointmentSheet({required this.doctor});
  @override
  State<_BookAppointmentSheet> createState() => _BookAppointmentSheetState();
}

class _BookAppointmentSheetState extends State<_BookAppointmentSheet> {
  final _reasonCtrl = TextEditingController();
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _loading = false;

  Future<void> _book() async {
    if (_selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Sélectionnez la date et l'heure")));
      return;
    }
    setState(() => _loading = true);
    try {
      final dt = DateTime(_selectedDate!.year, _selectedDate!.month,
          _selectedDate!.day, _selectedTime!.hour, _selectedTime!.minute);
      await ApiService().bookAppointment({
        'doctor_id': widget.doctor.id,
        'scheduled_at': dt.toIso8601String(),
        'reason': _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
      });
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Demande de rendez-vous envoyée'),
          backgroundColor: kPrimary));
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = (e.response?.data is Map)
          ? (e.response!.data['error'] ?? e.response!.data['message'] ?? 'Échec de la réservation')
          : 'Échec de la réservation';
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg.toString()), backgroundColor: kRed));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: kRed));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: kGray100,
        appBar: AppBar(
          title: const Text('Prendre rendez-vous'),
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            // Doctor card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [kPrimary, Color(0xFF1BA87A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                      color: Colors.white24, shape: BoxShape.circle),
                  child: Center(
                      child: Text(widget.doctor.user.initials,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700))),
                ),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(widget.doctor.user.fullName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      Text(_specialtyLabel(widget.doctor.specialty),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13)),
                      Text('${widget.doctor.consultationMinutes} min · Gabes',
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 12)),
                    ])),
              ]),
            ),
            const SizedBox(height: 20),

            // Date
            _SectionCard(
              title: 'Choisir la date',
              icon: Icons.calendar_today,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now().add(const Duration(days: 1)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 60)),
                  );
                  if (d != null) setState(() => _selectedDate = d);
                },
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(
                    _selectedDate == null
                        ? 'Choisir une date'
                        : '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}',
                    style: TextStyle(
                      color: _selectedDate != null ? kPrimary : kGray600,
                      fontWeight: _selectedDate != null
                          ? FontWeight.w600
                          : FontWeight.normal,
                    )),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  side: BorderSide(
                      color: _selectedDate != null ? kPrimary : kGray200),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Heure
            _SectionCard(
              title: "Choisir l'heure",
              icon: Icons.access_time,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final t = await showTimePicker(
                      context: context, initialTime: TimeOfDay.now());
                  if (t != null) setState(() => _selectedTime = t);
                },
                icon: const Icon(Icons.access_time, size: 16),
                label: Text(
                    _selectedTime == null
                        ? 'Choisir une heure'
                        : _selectedTime!.format(context),
                    style: TextStyle(
                      color: _selectedTime != null ? kPrimary : kGray600,
                      fontWeight: _selectedTime != null
                          ? FontWeight.w600
                          : FontWeight.normal,
                    )),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  side: BorderSide(
                      color: _selectedTime != null ? kPrimary : kGray200),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Raison
            _SectionCard(
              title: 'Motif (optionnel)',
              icon: Icons.notes,
              child: TextField(
                controller: _reasonCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Décrivez vos symptômes ou le motif...',
                  hintStyle: const TextStyle(color: kGray400, fontSize: 13),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: kGray200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: kGray200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: kPrimary),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 28),

            ElevatedButton.icon(
              onPressed: _loading ? null : _book,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.check_circle_outline),
              label: const Text('Confirmer le rendez-vous'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                textStyle:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ]),
        ),
      );
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _SectionCard(
      {required this.title, required this.icon, required this.child});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 16, color: kPrimary),
            const SizedBox(width: 6),
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: kGray900)),
          ]),
          const SizedBox(height: 10),
          child,
        ]),
      );
}
