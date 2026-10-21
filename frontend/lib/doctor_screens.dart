import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'constants.dart';
import 'api_service.dart';
import 'models.dart';
import 'shared_widgets.dart';
import 'screens/shared/profile_screen.dart';
import 'screens/chat_screens.dart';
import 'socket_service.dart';
import 'providers/notification_provider.dart';
import 'utils/file_opener.dart';

// ─── Doctor Main Entry (Navigation) ──────────────────────────────────────────
class DoctorHome extends StatefulWidget {
  const DoctorHome({super.key});
  @override
  State<DoctorHome> createState() => _DoctorHomeState();
}

class _DoctorHomeState extends State<DoctorHome> {
  int _tab = 0;
  final GlobalKey<_DoctorDashboardState> _dashboardKey =
      GlobalKey<_DoctorDashboardState>();

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      DoctorDashboardScreen(key: _dashboardKey),
      const DoctorAppointmentsScreen(),
      const DoctorPatientsScreen(),
      const ConversationsScreen(),
      const DoctorPrescriptionsScreen(),
    ];
  }

  void _onTabSelected(int i) {
    setState(() => _tab = i);
    if (i == 0) {
      _dashboardKey.currentState?._load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _screens[_tab],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8),
            child: NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: _onTabSelected,
              backgroundColor: Colors.transparent,
              indicatorColor: kPrimary.withOpacity(0.1),
              elevation: 0,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard, color: kPrimary),
                  label: 'Accueil',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_today_outlined),
                  selectedIcon: Icon(Icons.calendar_today, color: kPrimary),
                  label: 'Rendez-vous',
                ),
                NavigationDestination(
                  icon: Icon(Icons.people_outline),
                  selectedIcon: Icon(Icons.people, color: kPrimary),
                  label: 'Patients',
                ),
                NavigationDestination(
                  icon: Icon(Icons.chat_bubble_outline),
                  selectedIcon: Icon(Icons.chat_bubble, color: kPrimary),
                  label: 'Messages',
                ),
                NavigationDestination(
                  icon: Icon(Icons.medication_outlined),
                  selectedIcon: Icon(Icons.medication, color: kPrimary),
                  label: 'Ordonnances',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Doctor Dashboard ────────────────────────────────────────────────────────
class DoctorDashboardScreen extends StatefulWidget {
  const DoctorDashboardScreen({super.key});
  @override
  State<DoctorDashboardScreen> createState() => _DoctorDashboardState();
}

class _DoctorDashboardState extends State<DoctorDashboardScreen> {
  UserModel? _user;
  List<AppointmentModel> _todayAppts = [];
  int _patientCount = 0;
  int _pendingCount = 0;
  bool _loading = true;
  late final Function(dynamic) _notificationHandler;

  @override
  void initState() {
    super.initState();
    _notificationHandler = (data) {
      final type = data is Map ? data['type'] : null;
      if (type == 'appointment_alert' || type == 'doctor_response') {
        _load();
      }
    };
    SocketService().on('notification', _notificationHandler);
    _load();
  }

  @override
  void dispose() {
    SocketService().off('notification', _notificationHandler);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final userRes = await ApiService().getMe();
      final apptsRes = await ApiService().getMyAppointments();
      final patientsRes = await ApiService().getMyPatients();

      final allAppts = (apptsRes.data['appointments'] as List)
          .map((j) => AppointmentModel.fromJson(j))
          .toList();

      final patientCount = (patientsRes.data['patients'] as List).length;

      // Filter for today's date (assuming scheduledAt is ISO string)
      final now = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(now);

      final user = UserModel.fromJson(userRes.data['user']);
      if (mounted) {
        context.read<NotificationProvider>().init(user.id);
      }

      setState(() {
        _user = user;
        _todayAppts =
            allAppts.where((a) => a.scheduledAt.startsWith(todayStr)).toList();
        _patientCount = patientCount;
        _pendingCount = allAppts.where((a) => a.status == 'pending').length;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            floating: false,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              title: Text(
                  'Bonjour, Dr ${_user?.fullName.split(' ').first ?? 'Docteur'}',
                  style: const TextStyle(
                      color: kGray900,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              background: Container(color: Colors.white),
            ),
            actions: [
              IconButton(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen())),
                icon:
                    const Icon(Icons.account_circle_outlined, color: kGray600),
              ),
              const SizedBox(width: 8),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stats Grid
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _StatCard(
                          title: "Aujourd'hui",
                          value: '${_todayAppts.length}',
                          subtitle: 'Rendez-vous',
                          icon: Icons.calendar_month,
                          color: kPrimary,
                        ),
                        const SizedBox(width: 12),
                        _StatCard(
                          title: 'En attente',
                          value: '$_pendingCount',
                          subtitle: 'Demandes',
                          icon: Icons.pending_actions,
                          color: kAmber,
                        ),
                        const SizedBox(width: 12),
                        _StatCard(
                          title: 'Patients',
                          value: '$_patientCount',
                          subtitle: 'Dossiers',
                          icon: Icons.people,
                          color: kSecondary,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const SectionHeader(title: "Planning du jour"),
                  if (_todayAppts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: EmptyState(
                        icon: '☕',
                        title: 'Journée calme',
                        subtitle: "Aucun rendez-vous prévu aujourd'hui.",
                      ),
                    )
                  else
                    ..._todayAppts.map((a) => _AppointmentStrip(appt: a)),

                  const SizedBox(height: 24),
                  const SectionHeader(title: "Actions rapides"),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _QuickAction(
                          label: 'Nouvelle ordonnance',
                          icon: Icons.add_moderator,
                          onTap: () {
                            // Find the DoctorHome state and change tab to Patients (2)
                            context
                                .findAncestorStateOfType<_DoctorHomeState>()
                                ?._onTabSelected(2);
                          },
                        ),
                        _QuickAction(
                          label: 'Gérer la file',
                          icon: Icons.reorder,
                          onTap: () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const DoctorQueueScreen()));
                          },
                        ),
                        _QuickAction(
                          label: 'Modifier le profil',
                          icon: Icons.edit_note,
                          onTap: () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const ProfileScreen()));
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title, value, subtitle;
  final IconData icon;
  final Color color;
  const _StatCard(
      {required this.title,
      required this.value,
      required this.subtitle,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.1), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(value,
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(title,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: kGray900)),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: kGray600)),
        ],
      ),
    );
  }
}

class _AppointmentStrip extends StatelessWidget {
  final AppointmentModel appt;
  const _AppointmentStrip({required this.appt});

  @override
  Widget build(BuildContext context) {
    String time = '—:—';
    String amPm = '';

    try {
      final dt = DateTime.parse(appt.scheduledAt);
      time = DateFormat('hh:mm').format(dt);
      amPm = DateFormat('a').format(dt);
    } catch (_) {
      if (appt.scheduledAt.contains('T')) {
        time = appt.scheduledAt.split('T').last.substring(0, 5);
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kGray200, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
                color: kGray100, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                Text(time,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: kPrimary)),
                Text(amPm,
                    style: const TextStyle(fontSize: 10, color: kGray600)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(appt.patientName ?? 'Patient #${appt.patientId}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                Text(appt.reason ?? 'Consultation de routine',
                    style: const TextStyle(fontSize: 12, color: kGray600)),
              ],
            ),
          ),
          StatusBadge(appt.status),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _QuickAction(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kGray200, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(icon, color: kPrimary, size: 20),
            const SizedBox(width: 8),
            Text(label,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// ─── Doctor Appointments (Full List) ──────────────────────────────────────────
class DoctorAppointmentsScreen extends StatefulWidget {
  const DoctorAppointmentsScreen({super.key});
  @override
  State<DoctorAppointmentsScreen> createState() => _DoctorApptsState();
}

class _DoctorApptsState extends State<DoctorAppointmentsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tc;
  List<AppointmentModel> _appointments = [];
  bool _loading = true;
  late final Function(dynamic) _notificationHandler;

  @override
  void initState() {
    super.initState();
    _tc = TabController(length: 2, vsync: this);
    _notificationHandler = (data) {
      final type = data is Map ? data['type'] : null;
      if (type == 'appointment_alert') {
        _load();
      }
    };
    SocketService().on('notification', _notificationHandler);
    _load();
  }

  @override
  void dispose() {
    SocketService().off('notification', _notificationHandler);
    _tc.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService().getMyAppointments();
      setState(() {
        _appointments = (res.data['appointments'] as List)
            .map((j) => AppointmentModel.fromJson(j))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateStatus(AppointmentModel a, String status) async {
    await ApiService().updateAppointmentStatus(a.id, {'status': status});
    _load();
  }

  List<AppointmentModel> get _pending =>
      _appointments.where((a) => a.status == 'pending').toList();
  List<AppointmentModel> get _active => _appointments
      .where((a) => ['accepted', 'confirmed'].contains(a.status))
      .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rendez-vous'),
        bottom: TabBar(
          controller: _tc,
          indicatorColor: kPrimary,
          labelColor: kPrimary,
          unselectedLabelColor: kGray600,
          tabs: [
            Tab(text: 'En attente (${_pending.length})'),
            Tab(text: 'Confirmés (${_active.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tc,
              children: [
                _AppointmentListView(
                  appointments: _pending,
                  onAction: (a, s) => _updateStatus(a, s),
                ),
                _AppointmentListView(
                  appointments: _active,
                  onAction: (a, s) => _updateStatus(a, s),
                  isConfirmed: true,
                ),
              ],
            ),
    );
  }
}

class _AppointmentListView extends StatelessWidget {
  final List<AppointmentModel> appointments;
  final Function(AppointmentModel, String) onAction;
  final bool isConfirmed;
  const _AppointmentListView(
      {required this.appointments,
      required this.onAction,
      this.isConfirmed = false});

  @override
  Widget build(BuildContext context) {
    if (appointments.isEmpty) {
      return const EmptyState(
          icon: '📅',
          title: 'Aucun rendez-vous',
          subtitle: 'Aucun rendez-vous dans cette catégorie.');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: appointments.length,
      itemBuilder: (_, i) => _EnhancedApptCard(
        appt: appointments[i],
        onAction: onAction,
        isConfirmed: isConfirmed,
      ),
    );
  }
}

class _EnhancedApptCard extends StatelessWidget {
  final AppointmentModel appt;
  final Function(AppointmentModel, String) onAction;
  final bool isConfirmed;
  const _EnhancedApptCard(
      {required this.appt, required this.onAction, required this.isConfirmed});

  @override
  Widget build(BuildContext context) {
    final date = appt.scheduledAt.split('T').first;
    final time = appt.scheduledAt.split('T').last.substring(0, 5);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AvatarCircle(initials: 'P', size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(appt.patientName ?? 'Patient #${appt.patientId}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    Text('$date à $time',
                        style: const TextStyle(color: kGray600, fontSize: 12)),
                  ],
                ),
              ),
              StatusBadge(appt.status),
            ],
          ),
          if (appt.reason != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              width: double.infinity,
              decoration: BoxDecoration(
                  color: kGray100, borderRadius: BorderRadius.circular(8)),
              child: Text(appt.reason!,
                  style: const TextStyle(fontSize: 13, color: kGray900)),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              if (!isConfirmed) ...[
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => onAction(appt, 'accepted'),
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 44)),
                    child: const Text('Accepter'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () => onAction(appt, 'rejected'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(80, 44),
                    foregroundColor: kRed,
                    side: const BorderSide(color: kRed),
                  ),
                  child: const Text('Refuser'),
                ),
              ] else ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => WritePrescriptionScreen(
                                  appointmentId: appt.id,
                                  patientId: appt.patientId)));
                    },
                    icon: const Icon(Icons.medication_outlined, size: 18),
                    label: const Text('Ordonnance'),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => onAction(appt, 'completed'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: kSecondary,
                        minimumSize: const Size(0, 44)),
                    child: const Text('Terminer'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Doctor Patients ──────────────────────────────────────────────────────────
class DoctorPatientsScreen extends StatefulWidget {
  const DoctorPatientsScreen({super.key});
  @override
  State<DoctorPatientsScreen> createState() => _DoctorPatientsState();
}

class _DoctorPatientsState extends State<DoctorPatientsScreen> {
  List<dynamic> _patients = [];
  List<dynamic> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_onSearch);
  }

  void _onSearch() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = _patients
          .where((p) => (p['full_name'] as String).toLowerCase().contains(q))
          .toList();
    });
  }

  Future<void> _load() async {
    try {
      final res = await ApiService().getMyPatients();
      setState(() {
        _patients = res.data['patients'];
        _filtered = _patients;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes patients')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Rechercher un patient...',
                prefixIcon: const Icon(Icons.search, color: kGray400),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? const EmptyState(
                        icon: '👥',
                        title: 'Aucun patient',
                        subtitle: 'Aucun résultat trouvé.')
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final p = _filtered[i];
                          return AppCard(
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        PatientDetailScreen(patient: p))),
                            child: Row(
                              children: [
                                AvatarCircle(
                                    initials: (p['full_name'] as String)
                                        .substring(0, 1)
                                        .toUpperCase(),
                                    size: 48),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(p['full_name'],
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15)),
                                      const SizedBox(height: 4),
                                      Text(
                                          'Blood: ${p['blood_type'] ?? 'N/A'}  •  ID: #${p['id']}',
                                          style: const TextStyle(
                                              color: kGray600, fontSize: 12)),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right,
                                    color: kGray400),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ─── Doctor Prescriptions (History) ───────────────────────────────────────────
class DoctorPrescriptionsScreen extends StatefulWidget {
  const DoctorPrescriptionsScreen({super.key});
  @override
  State<DoctorPrescriptionsScreen> createState() => _DoctorPrescHistoryState();
}

class _DoctorPrescHistoryState extends State<DoctorPrescriptionsScreen> {
  List<PrescriptionModel> _prescriptions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService().getMyPrescriptions();
      setState(() {
        _prescriptions = (res.data['prescriptions'] as List)
            .map((j) => PrescriptionModel.fromJson(j))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historique des ordonnances')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _prescriptions.isEmpty
              ? const EmptyState(
                  icon: '💊',
                  title: 'Aucune ordonnance',
                  subtitle: "Vous n'avez pas encore rédigé d'ordonnance.")
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _prescriptions.length,
                  itemBuilder: (_, i) {
                    final pr = _prescriptions[i];
                    return AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Ordonnance #${pr.id}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: kPrimary)),
                              Text(pr.createdAt?.substring(0, 10) ?? '',
                                  style: const TextStyle(
                                      color: kGray600, fontSize: 12)),
                            ],
                          ),
                          const Divider(height: 24),
                          ...pr.medications.take(2).map((m) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text('• ${m['name']} (${m['dose']})',
                                    style: const TextStyle(fontSize: 13)),
                              )),
                          if (pr.medications.length > 2)
                            Text(
                                '+ ${pr.medications.length - 2} médicament(s)',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: kGray600,
                                    fontStyle: FontStyle.italic)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.person_outline,
                                  size: 14, color: kGray600),
                              const SizedBox(width: 4),
                              Text(pr.patientName ?? 'Patient #${pr.patientId}',
                                  style: const TextStyle(
                                      fontSize: 12, color: kGray600)),
                              const Spacer(),
                              TextButton(
                                  onPressed: () {},
                                  child: const Text('Voir le PDF',
                                      style: TextStyle(fontSize: 13))),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

// ─── Patient Detail ──────────────────────────────────────────────────────────
class PatientDetailScreen extends StatefulWidget {
  final Map<String, dynamic> patient;
  const PatientDetailScreen({super.key, required this.patient});
  @override
  State<PatientDetailScreen> createState() => _PatientDetailState();
}

class _PatientDetailState extends State<PatientDetailScreen> {
  List<RecordModel> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    try {
      final res = await ApiService().getPatientRecords(widget.patient['id']);
      setState(() {
        _records = (res.data['records'] as List)
            .map((j) => RecordModel.fromJson(j))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openRecord(RecordModel record) {
    final baseUrl = kBaseUrl.replaceAll('/api', '');
    final url = record.fileUrl.startsWith('http')
        ? record.fileUrl
        : '$baseUrl${record.fileUrl}';
    openExternalFile(url, fileName: record.title);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.patient;
    return Scaffold(
      appBar: AppBar(title: Text(p['full_name'])),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: kPrimary, borderRadius: BorderRadius.circular(20)),
              child: Row(
                children: [
                  AvatarCircle(
                      initials: (p['full_name'] as String)
                          .substring(0, 1)
                          .toUpperCase(),
                      size: 60,
                      bg: Colors.white.withOpacity(0.2),
                      fg: Colors.white),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p['full_name'],
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        Text('Groupe sanguin : ${p['blood_type'] ?? 'N/A'}',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 13)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4)),
                          child: const Text('Patient vérifié',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 10)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(title: 'Résumé médical'),
                  _DetailRow(Icons.phone, 'Téléphone', p['phone'] ?? '—'),
                  _DetailRow(
                      Icons.healing,
                      'Pathologies',
                      (p['chronic_conditions'] as List?)?.join(', ') ??
                          'Aucune indiquée'),
                  _DetailRow(Icons.warning_amber, 'Allergies',
                      (p['allergies'] as List?)?.join(', ') ?? 'Aucune indiquée'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionHeader(title: 'Dossiers médicaux partagés'),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_records.isEmpty)
              const EmptyState(
                  icon: '📁',
                  title: 'Aucun dossier',
                  subtitle: "Ce patient n'a pas encore partagé de dossier.")
            else
              ..._records.map((r) => AppCard(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: kGray100,
                              borderRadius: BorderRadius.circular(10)),
                          child: Icon(
                              r.fileType == 'pdf'
                                  ? Icons.picture_as_pdf
                                  : Icons.description,
                              color: kGray600),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14)),
                              Text(
                                  '${r.recordType.toUpperCase()} • ${r.uploadedAt.substring(0, 10)}',
                                  style: const TextStyle(
                                      color: kGray600, fontSize: 11)),
                            ],
                          ),
                        ),
                        IconButton(
                            tooltip: 'Ouvrir le dossier',
                            onPressed: () => _openRecord(r),
                            icon: const Icon(Icons.open_in_new_rounded,
                                color: kPrimary)),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _DetailRow(this.icon, this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Icon(icon, size: 16, color: kGray400),
            const SizedBox(width: 12),
            Text('$label:',
                style: const TextStyle(color: kGray600, fontSize: 13)),
            const SizedBox(width: 8),
            Expanded(
                child: Text(value,
                    style: const TextStyle(
                        fontWeight: FontWeight.w500, fontSize: 13))),
          ],
        ),
      );
}

// ─── Write Prescription ────────────────────────────────────────────────────────
class WritePrescriptionScreen extends StatefulWidget {
  final int appointmentId, patientId;
  const WritePrescriptionScreen(
      {super.key, required this.appointmentId, required this.patientId});
  @override
  State<WritePrescriptionScreen> createState() => _WritePrescState();
}

class _WritePrescState extends State<WritePrescriptionScreen> {
  final _instrCtrl = TextEditingController();
  final _meds = <Map<String, String>>[];
  bool _saving = false;

  void _addMed() => setState(() =>
      _meds.add({'name': '', 'dose': '', 'frequency': '', 'duration': ''}));

  Future<void> _save() async {
    if (_meds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ajoutez au moins un médicament')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiService().createPrescription({
        'appointment_id': widget.appointmentId,
        'medications': _meds,
        'instructions': _instrCtrl.text,
      });
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ordonnance enregistrée avec succès')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Erreur lors de l'enregistrement"), backgroundColor: kRed));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle ordonnance')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SectionHeader(title: 'Médicaments'),
            ..._meds.asMap().entries.map((e) => AppCard(
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Médicament #${e.key + 1}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: kPrimary)),
                          IconButton(
                            onPressed: () =>
                                setState(() => _meds.removeAt(e.key)),
                            icon:
                                const Icon(Icons.close, size: 18, color: kRed),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      TextField(
                        decoration: const InputDecoration(
                            labelText: 'Nom du médicament',
                            hintText: 'ex. Paracetamol'),
                        onChanged: (v) => _meds[e.key]['name'] = v,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              decoration: const InputDecoration(
                                  labelText: 'Dosage', hintText: '500mg'),
                              onChanged: (v) => _meds[e.key]['dose'] = v,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              decoration: const InputDecoration(
                                  labelText: 'Fréquence', hintText: '2 fois par jour'),
                              onChanged: (v) => _meds[e.key]['frequency'] = v,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: const InputDecoration(
                            labelText: 'Durée', hintText: '7 jours'),
                        onChanged: (v) => _meds[e.key]['duration'] = v,
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _addMed,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Ajouter un médicament'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48)),
            ),
            const SizedBox(height: 24),
            const SectionHeader(title: 'Instructions du médecin'),
            TextField(
              controller: _instrCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Ajoutez des conseils ou précautions...',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Finaliser et enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: const EmptyState(
            icon: '🔔',
            title: 'Aucune notification',
            subtitle: 'Nous vous préviendrons en cas de nouveauté.'),
      );
}

// ─── Doctor Queue Management ──────────────────────────────────────────────────
class DoctorQueueScreen extends StatefulWidget {
  const DoctorQueueScreen({super.key});
  @override
  State<DoctorQueueScreen> createState() => _DoctorQueueState();
}

class _DoctorQueueState extends State<DoctorQueueScreen> {
  bool _loading = true;
  Map<String, dynamic>? _data;
  int? _serviceId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService().getMe();
      final dp = res.data['user']['doctor_profile'] as Map<String, dynamic>?;
      final sid = dp?['service_id'] as int?;
      if (sid != null) {
        final qRes = await ApiService().getQueueStatus(sid);
        setState(() {
          _serviceId = sid;
          _data = qRes.data;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('File en direct')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _data == null
              ? const EmptyState(
                  icon: '🏥',
                  title: 'Aucun service',
                  subtitle: "Votre profil n'est lié à aucune file de service.")
              : Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      AppCard(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const Text('Ticket en cours',
                                style:
                                    TextStyle(color: kGray600, fontSize: 14)),
                            const SizedBox(height: 8),
                            Text('${_data!['current_number']}',
                                style: const TextStyle(
                                    fontSize: 48,
                                    fontWeight: FontWeight.bold,
                                    color: kPrimary)),
                            const Divider(height: 32),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _QueueStat('Total émis',
                                    '${_data!['total_issued']}'),
                                _QueueStat('Attente moy.',
                                    '${_data!['avg_wait_minutes']}m'),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () async {
                          // Call next logic
                        },
                        icon: const Icon(Icons.skip_next),
                        label: const Text('Appeler le patient suivant'),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _QueueStat extends StatelessWidget {
  final String label, value;
  const _QueueStat(this.label, this.value);
  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: kGray900)),
          Text(label, style: const TextStyle(fontSize: 12, color: kGray600)),
        ],
      );
}
