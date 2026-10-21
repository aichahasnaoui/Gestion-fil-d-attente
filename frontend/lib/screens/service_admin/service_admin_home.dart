import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import '../../constants.dart';
import '../../api_service.dart';
import '../../shared_widgets.dart';
import '../../socket_service.dart';

class ServiceAdminHome extends StatefulWidget {
  const ServiceAdminHome({super.key});
  @override
  State<ServiceAdminHome> createState() => _ServiceAdminHomeState();
}

class _ServiceAdminHomeState extends State<ServiceAdminHome> {
  int _tab = 0;
  @override
  Widget build(BuildContext context) {
    final screens = [
      const _AdminDashboard(),
      const _GuichetsScreen(),
      const _SettingsScreen(),
    ];
    return Scaffold(
      body: screens[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: Colors.white,
        indicatorColor: kPrimaryLight,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard, color: kPrimary),
              label: 'Tableau de bord'),
          NavigationDestination(
              icon: Icon(Icons.window_outlined),
              selectedIcon: Icon(Icons.window, color: kPrimary),
              label: 'Guichets'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings, color: kPrimary),
              label: 'Paramètres'),
        ],
      ),
    );
  }
}

// ── Dashboard ─────────────────────────────────────────────────────────────────
class _AdminDashboard extends StatefulWidget {
  const _AdminDashboard();
  @override
  State<_AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<_AdminDashboard> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _calling = false;
  bool _autoCall = false;
  Timer? _autoCallTimer;
  Timer? _noShowTimer;

  @override
  void initState() {
    super.initState();
    _load();
    SocketService().on('queue_update', (_) => _load());
    // Start auto-call and no-show check automatically
    _startAutoCall();
  }

  void _startAutoCall() {
    _autoCall = true;
    // Check no-shows every 2 minutes
    _noShowTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
      try { await ApiService().serviceAdminCheckNoShows(); } catch (_) {}
    });
    // Call next every 5 minutes
    _autoCallTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      final queue = _data?['queue'] as Map<String, dynamic>?;
      if (queue != null && (queue['is_open'] as bool) && (queue['waiting'] as int) > 0) {
        await _callNext(silent: true);
      }
    });
  }

  @override
  void dispose() {
    SocketService().off('queue_update');
    _autoCallTimer?.cancel();
    _noShowTimer?.cancel();
    super.dispose();
  }

  void _toggleAutoCall() {
    // Auto-call is always active — this just shows status
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Appel automatique actif (toutes les 5 min) ✅'), backgroundColor: kPrimary));
  }

  Future<void> _load() async {
    try {
      final res = await ApiService().getServiceAdminDashboard();
      if (mounted) setState(() { _data = res.data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _callNext({bool silent = false}) async {
    if (!silent) setState(() => _calling = true);
    try {
      final res = await ApiService().serviceAdminCallNext();
      final t = res.data['ticket'];
      if (!mounted) return;
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Ticket ${t['ticket_number']} appelé ✅'),
          backgroundColor: kPrimary,
        ));
      }
      _load();
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        final msg = e.toString().contains('No waiting') ? 'Aucun ticket en attente' : e.toString();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: kRed));
      }
    } finally {
      if (mounted && !silent) setState(() => _calling = false);
    }
  }

  Future<void> _toggleQueue() async {
    try {
      await ApiService().serviceAdminToggleQueue();
      _load();
    } catch (_) {}
  }

  Future<void> _cancelCurrent() async {
    final queue = _data?['queue'] as Map<String, dynamic>?;
    if (queue == null) return;
    final currentNumber = queue['current_number'] as int;
    if (currentNumber == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucun ticket en cours'), backgroundColor: kGray600));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Annuler le ticket en cours'),
        content: Text('Annuler le ticket $currentNumber (absent / no-show) ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Non')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Oui, annuler', style: TextStyle(color: kRed))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService().serviceAdminCancelCurrent();
      _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ticket annulé (absent)'), backgroundColor: kRed));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: kRed));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_data == null) return const Scaffold(body: Center(child: Text('Erreur de chargement')));

    final service = _data!['service'] as Map<String, dynamic>;
    final queue   = _data!['queue']   as Map<String, dynamic>;
    final openG   = _data!['open_guichets'] as int;
    final isOpen  = queue['is_open'] as bool;

    return Scaffold(
      backgroundColor: kGray100,
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF2D6BE4), Color(0xFF378ADD)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 28),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.admin_panel_settings, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(service['name'], style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                    const Text('Admin du service', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ])),
                  GestureDetector(
                    onTap: _toggleQueue,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isOpen ? Colors.white24 : Colors.red.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white38),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(isOpen ? Icons.lock_open : Icons.lock, color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                        Text(isOpen ? 'Ouverte' : 'Fermée',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () async {
                      final storage = const FlutterSecureStorage();
                      await storage.delete(key: kAccessToken);
                      await storage.delete(key: kRefreshToken);
                      SocketService().disconnect();
                      if (!context.mounted) return;
                      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.logout, color: Colors.white, size: 18),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                Center(child: Column(children: [
                  const Text('TICKET EN COURS', style: TextStyle(color: Colors.white60, fontSize: 11, letterSpacing: 1.5)),
                  const SizedBox(height: 4),
                  Text(
                    queue['current_number'].toString().padLeft(3, '0'),
                    style: const TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.w900, height: 1),
                  ),
                  Text('$openG guichet(s) ouvert(s) · ~${queue['avg_wait_minutes']} min/ticket',
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ])),
              ]),
            ).animate().fadeIn(duration: 400.ms),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(delegate: SliverChildListDelegate([
              GridView.count(
                crossAxisCount: 2, shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10, mainAxisSpacing: 10,
                childAspectRatio: 1.7,
                children: [
                  _StatCard('En attente',  '${queue['waiting']}',   kAmber,     Icons.hourglass_empty),
                  _StatCard('Appelés',     '${(queue['called'] as int) + (queue['confirmed'] as int)}',    kSecondary, Icons.campaign),
                  _StatCard('Servis',      '${queue['served']}',    kPrimary,   Icons.check_circle_outline),
                  _StatCard('Annulés',     '${queue['cancelled']}', kRed,       Icons.cancel_outlined),
                ],
              ).animate().fadeIn(delay: 100.ms),

              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: kGray200)),
                child: Row(children: [
                  const Icon(Icons.confirmation_number_outlined, color: kPrimary),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Tickets émis aujourd\'hui', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text('${queue['total_issued']} / ${service['max_daily_tickets']} maximum',
                        style: const TextStyle(color: kGray600, fontSize: 13)),
                  ])),
                  SizedBox(
                    width: 48, height: 48,
                    child: CircularProgressIndicator(
                      value: (queue['total_issued'] as int) / ((service['max_daily_tickets'] as int? ?? 200)),
                      backgroundColor: kGray200, color: kPrimary, strokeWidth: 5,
                    ),
                  ),
                ]),
              ),

              const SizedBox(height: 16),

              // Auto-call status (always active)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFE4F7F0),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kPrimary.withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.autorenew, color: kPrimary, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Appel automatique actif',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: kPrimary)),
                      Text('Appel toutes les 5 min · Vérif. absents toutes les 2 min',
                          style: TextStyle(fontSize: 11, color: kGray600)),
                    ]),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(20)),
                    child: const Text('AUTO', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                ]),
              ),
            ])),
          ),
        ]),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final Color color;
  final IconData icon;
  const _StatCard(this.label, this.value, this.color, this.icon);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: kGray200)),
    child: Row(children: [
      Container(padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 18)),
      const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: const TextStyle(color: kGray600, fontSize: 11)),
      ]),
    ]),
  );
}

// ── Guichets ──────────────────────────────────────────────────────────────────
class _GuichetsScreen extends StatefulWidget {
  const _GuichetsScreen();
  @override
  State<_GuichetsScreen> createState() => _GuichetsScreenState();
}

class _GuichetsScreenState extends State<_GuichetsScreen> {
  List<dynamic> _guichets = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final res = await ApiService().getGuichets();
      setState(() { _guichets = res.data['guichets']; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _toggle(int id) async {
    try {
      final res = await ApiService().toggleGuichet(id);
      final openCount = res.data['open_guichets'] as int;
      final avgWait   = res.data['avg_wait_minutes'] as int;
      _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$openCount guichet(s) ouvert(s) · ~$avgWait min/ticket'),
        backgroundColor: kPrimary,
      ));
    } catch (_) {}
  }

  Future<void> _add() async {
    try {
      await ApiService().addGuichet();
      _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Guichet ajouté ✅'), backgroundColor: kPrimary));
    } catch (_) {}
  }

  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer le guichet'),
        content: const Text('Voulez-vous vraiment supprimer ce guichet ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Non')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Supprimer', style: TextStyle(color: kRed))),
        ],
      ),
    );
    if (ok != true) return;
    await ApiService().deleteGuichet(id);
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Gestion des guichets'),
      actions: [
        IconButton(icon: const Icon(Icons.add_circle_outline, color: kPrimary),
            onPressed: _add, tooltip: 'Ajouter un guichet'),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _guichets.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const EmptyState(icon: '🪟', title: 'Aucun guichet',
                    subtitle: 'Ajoutez des guichets pour gérer la file'),
                const SizedBox(height: 16),
                ElevatedButton.icon(onPressed: _add,
                    icon: const Icon(Icons.add), label: const Text('Ajouter un guichet'),
                    style: ElevatedButton.styleFrom(minimumSize: const Size(200, 48))),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _guichets.length,
                itemBuilder: (_, i) {
                  final g = _guichets[i];
                  final isOpen = g['is_open'] as bool;
                  return AppCard(
                    child: Row(children: [
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          color: isOpen ? kPrimaryLight : kRedLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.window, color: isOpen ? kPrimary : kRed, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(g['name'], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        Text(isOpen ? 'Ouvert — traite les tickets' : 'Fermé — pas de service',
                            style: TextStyle(color: isOpen ? kPrimary : kRed, fontSize: 12)),
                      ])),
                      Switch(value: isOpen, activeColor: kPrimary, onChanged: (_) => _toggle(g['id'])),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: kRed, size: 20),
                        onPressed: () => _delete(g['id']),
                      ),
                    ]),
                  );
                }),
  );
}

// ── Settings ──────────────────────────────────────────────────────────────────
class _SettingsScreen extends StatefulWidget {
  const _SettingsScreen();
  @override
  State<_SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<_SettingsScreen> {
  final _maxCtrl = TextEditingController();
  bool _loading = true, _saving = false;
  Map<String, dynamic>? _service;
  final _storage = const FlutterSecureStorage();

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Déconnexion'),
        content: const Text('Voulez-vous vraiment vous déconnecter ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Se déconnecter', style: TextStyle(color: kRed))),
        ],
      ),
    );
    if (ok != true) return;
    await _storage.delete(key: kAccessToken);
    await _storage.delete(key: kRefreshToken);
    SocketService().disconnect();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final res = await ApiService().getServiceAdminDashboard();
      final s = res.data['service'] as Map<String, dynamic>;
      setState(() { _service = s; _maxCtrl.text = '${s['max_daily_tickets']}'; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ApiService().updateServiceSettings({'max_daily_tickets': int.tryParse(_maxCtrl.text) ?? 200});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paramètres mis à jour ✅'), backgroundColor: kPrimary));
    } catch (e) {
      if (!mounted) return;
      String msg = 'Erreur lors de la mise à jour';
      if (e is DioException) {
        msg = (e.response?.data is Map)
            ? (e.response!.data['error'] ?? msg)
            : msg;
      }
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: kRed));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Paramètres du service')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF2D6BE4), Color(0xFF378ADD)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(children: [
                  const Icon(Icons.business, color: Colors.white, size: 32),
                  const SizedBox(width: 16),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_service?['name'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                    Text(_service?['address'] ?? '', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ])),
                ]),
              ),
              const SizedBox(height: 24),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Icons.confirmation_number_outlined, color: kPrimary, size: 18),
                    SizedBox(width: 8),
                    Text('Nombre maximum de tickets par jour', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  ]),
                  const SizedBox(height: 4),
                  const Text('Définissez la capacité journalière de votre service.',
                      style: TextStyle(color: kGray600, fontSize: 12)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _maxCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Nombre max de tickets',
                      prefixIcon: const Icon(Icons.numbers),
                      suffixText: 'tickets/jour',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: kAmberLight, borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kAmber.withOpacity(0.3))),
                child: const Row(children: [
                  Icon(Icons.info_outline, color: kAmber, size: 18),
                  SizedBox(width: 10),
                  Expanded(child: Text(
                    'Le temps d\'attente est calculé automatiquement selon le nombre de guichets ouverts. '
                    'Plus de guichets ouverts = attente plus courte pour les clients.',
                    style: TextStyle(color: kAmber, fontSize: 12),
                  )),
                ]),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: const Text('Enregistrer les paramètres'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 54),
                  backgroundColor: const Color(0xFF2D6BE4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout, color: kRed),
                label: const Text('Se déconnecter'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 54),
                  foregroundColor: kRed,
                  side: const BorderSide(color: kRed),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ]),
          ),
  );
}
