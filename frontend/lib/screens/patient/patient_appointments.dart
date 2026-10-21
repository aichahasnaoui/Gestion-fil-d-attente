import 'package:flutter/material.dart';
import '../../constants.dart';
import '../../api_service.dart';
import '../../models.dart';
import '../../shared_widgets.dart';

class PatientAppointmentsScreen extends StatefulWidget {
  const PatientAppointmentsScreen({super.key});
  @override
  State<PatientAppointmentsScreen> createState() => _PatientApptsState();
}

class _PatientApptsState extends State<PatientAppointmentsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tc;
  List<AppointmentModel> _all = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tc = TabController(length: 4, vsync: this);
    _loadAndExpire();
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  Future<void> _loadAndExpire() async {
    setState(() => _loading = true);
    try {
      await ApiService().expirePastAppointments();
      final res = await ApiService().getMyAppointments();
      setState(() {
        _all = (res.data['appointments'] as List)
            .map((j) => AppointmentModel.fromJson(j))
            .toList();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  List<AppointmentModel> get _active => _all
      .where((a) => ['pending', 'accepted', 'confirmed'].contains(a.status))
      .toList();
  List<AppointmentModel> get _expired =>
      _all.where((a) => a.status == 'expired').toList();
  List<AppointmentModel> get _past =>
      _all.where((a) => a.status == 'completed').toList();
  List<AppointmentModel> get _cancelled => _all
      .where((a) => ['cancelled', 'rejected', 'no_show'].contains(a.status))
      .toList();

  Future<void> _showAttendedDialog(AppointmentModel a) async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Rendez-vous terminé',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Êtes-vous allé à ce rendez-vous ?',
              style: TextStyle(fontSize: 15)),
          const SizedBox(height: 8),
          Text('Dr. ${a.doctorName ?? 'Inconnu'}',
              style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w600)),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'rebook'),
            child: const Text('Non — Reprendre RDV', style: TextStyle(color: kGray600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Non — Annuler', style: TextStyle(color: kRed)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'attended'),
            style: ElevatedButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
            child: const Text('Oui, j\'y suis allé'),
          ),
        ],
      ),
    );

    if (result == null || !mounted) return;

    if (result == 'attended') {
      await ApiService().markAttended(a.id);
      _loadAndExpire();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Rendez-vous marqué comme terminé ✅'),
          backgroundColor: kPrimary));
    } else if (result == 'cancel') {
      await ApiService().cancelAppointment(a.id);
      _loadAndExpire();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Rendez-vous annulé'), backgroundColor: kRed));
    } else if (result == 'rebook') {
      await ApiService().cancelAppointment(a.id);
      _loadAndExpire();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Rendez-vous annulé. Recherchez le médecin pour reprendre.'),
          backgroundColor: kPrimary));
    }
  }

  Future<void> _confirm(AppointmentModel a) async {
    if (a.confirmationCount >= 3) return;
    try {
      await ApiService().confirmAppointment(a.id);
      _loadAndExpire();
      if (!mounted) return;
      final left = 3 - (a.confirmationCount + 1);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(left > 0
            ? 'Confirmé (${a.confirmationCount + 1}/3). Encore $left confirmation(s).'
            : 'Confirmation complète !'),
        backgroundColor: kPrimary,
      ));
    } catch (_) {}
  }

  Future<void> _cancel(AppointmentModel a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Annuler le rendez-vous'),
        content: const Text('Voulez-vous vraiment annuler ce rendez-vous ?'),
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
      await ApiService().cancelAppointment(a.id);
      _loadAndExpire();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Mes rendez-vous'),
          bottom: TabBar(
            controller: _tc,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Actifs (${_active.length})'),
              Tab(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Terminés'),
                  if (_expired.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: kRed, borderRadius: BorderRadius.circular(10)),
                      child: Text('${_expired.length}',
                          style: const TextStyle(color: Colors.white, fontSize: 10)),
                    ),
                  ]
                ]),
              ),
              Tab(text: 'Complétés (${_past.length})'),
              Tab(text: 'Annulés'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(controller: _tc, children: [
                _ApptList(appointments: _active, onConfirm: _confirm, onCancel: _cancel),
                _ExpiredList(appointments: _expired, onAction: _showAttendedDialog),
                _ApptList(appointments: _past),
                _ApptList(appointments: _cancelled),
              ]),
      );
}

// ── Expired ───────────────────────────────────────────────────────────────────
class _ExpiredList extends StatelessWidget {
  final List<AppointmentModel> appointments;
  final Function(AppointmentModel) onAction;
  const _ExpiredList({required this.appointments, required this.onAction});

  @override
  Widget build(BuildContext context) => appointments.isEmpty
      ? const EmptyState(
          icon: '✅',
          title: 'Aucun rendez-vous en attente',
          subtitle: 'Tous vos rendez-vous passés ont été traités')
      : ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: appointments.length,
          itemBuilder: (_, i) {
            final a = appointments[i];
            return _ExpiredCard(appt: a, onAction: () => onAction(a));
          });
}

class _ExpiredCard extends StatelessWidget {
  final AppointmentModel appt;
  final VoidCallback onAction;
  const _ExpiredCard({required this.appt, required this.onAction});

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      const months = ['Jan','Fév','Mar','Avr','Mai','Jun','Jul','Aoû','Sep','Oct','Nov','Déc'];
      return '${dt.day} ${months[dt.month - 1]} à ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso.length > 16 ? iso.substring(0, 16) : iso;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF57C2B).withOpacity(0.4)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(12)),
                child: Center(
                  child: Text(
                    (appt.doctorName ?? 'Dr').trim().split(' ').take(2)
                        .map((w) => w.isNotEmpty ? w[0] : '').join().toUpperCase(),
                    style: const TextStyle(color: Color(0xFFF57C2B), fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Dr. ${appt.doctorName ?? 'Inconnu'}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                if (appt.doctorSpecialty != null && appt.doctorSpecialty!.isNotEmpty)
                  Text(appt.doctorSpecialty!, style: const TextStyle(color: kGray600, fontSize: 11)),
                Row(children: [
                  const Icon(Icons.access_time, size: 11, color: kGray400),
                  const SizedBox(width: 3),
                  Text(_formatDate(appt.scheduledAt), style: const TextStyle(color: kGray600, fontSize: 11)),
                ]),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(20)),
                child: const Text('Terminé', style: TextStyle(color: Color(0xFFF57C2B), fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: const Color(0xFFFFF8F0),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFF57C2B).withOpacity(0.3))),
              child: const Row(children: [
                Icon(Icons.help_outline, color: Color(0xFFF57C2B), size: 16),
                SizedBox(width: 8),
                Expanded(child: Text(
                  'Ce rendez-vous est passé. Êtes-vous allé chez le médecin ?',
                  style: TextStyle(color: Color(0xFFF57C2B), fontSize: 12, fontWeight: FontWeight.w500),
                )),
              ]),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: const Text('Indiquer ma présence'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF57C2B),
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              ),
            ),
          ]),
        ),
      );
}

// ── Regular list ──────────────────────────────────────────────────────────────
class _ApptList extends StatelessWidget {
  final List<AppointmentModel> appointments;
  final Function(AppointmentModel)? onConfirm;
  final Function(AppointmentModel)? onCancel;
  const _ApptList({required this.appointments, this.onConfirm, this.onCancel});

  @override
  Widget build(BuildContext context) => appointments.isEmpty
      ? const EmptyState(icon: '📅', title: 'Aucun rendez-vous', subtitle: "Rien pour l'instant")
      : ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: appointments.length,
          itemBuilder: (_, i) => _ApptCard(
            appt: appointments[i],
            onConfirm: onConfirm != null ? () => onConfirm!(appointments[i]) : null,
            onCancel: onCancel != null ? () => onCancel!(appointments[i]) : null,
          ));
}

class _ApptCard extends StatelessWidget {
  final AppointmentModel appt;
  final VoidCallback? onConfirm, onCancel;
  const _ApptCard({required this.appt, this.onConfirm, this.onCancel});

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      const months = ['Jan','Fév','Mar','Avr','Mai','Jun','Jul','Aoû','Sep','Oct','Nov','Déc'];
      return '${dt.day} ${months[dt.month - 1]} à ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso.length > 16 ? iso.substring(0, 16) : iso;
    }
  }

  @override
  Widget build(BuildContext context) => AppCard(
        borderColor: appt.status == 'accepted' ? kPrimary.withOpacity(0.3) : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: kPrimaryLight, borderRadius: BorderRadius.circular(12)),
              child: Center(
                child: Text(
                  (appt.doctorName ?? 'Dr').trim().split(' ').take(2)
                      .map((w) => w.isNotEmpty ? w[0] : '').join().toUpperCase(),
                  style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Dr. ${appt.doctorName ?? 'Inconnu'}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              if (appt.doctorSpecialty != null && appt.doctorSpecialty!.isNotEmpty)
                Text(appt.doctorSpecialty!, style: const TextStyle(color: kPrimary, fontSize: 11)),
              Row(children: [
                const Icon(Icons.access_time, size: 11, color: kGray400),
                const SizedBox(width: 3),
                Text(_formatDate(appt.scheduledAt), style: const TextStyle(color: kGray600, fontSize: 11)),
              ]),
            ])),
            StatusBadge(appt.status),
          ]),

          if (appt.reason != null && appt.reason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Motif : ${appt.reason}', style: const TextStyle(color: kGray600, fontSize: 12)),
          ],

          if (appt.status == 'accepted') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: kPrimaryLight, borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.info_outline, color: kPrimary, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  'Confirmez votre arrivée (${appt.confirmationCount}/3)',
                  style: const TextStyle(color: kPrimary, fontSize: 12, fontWeight: FontWeight.w500),
                )),
                ConfirmDots(filled: appt.confirmationCount),
              ]),
            ),
          ],

          if (onConfirm != null || onCancel != null) ...[
            const SizedBox(height: 12),
            Row(children: [
              if (onConfirm != null && appt.status == 'accepted' && appt.confirmationCount < 3)
                Expanded(child: ElevatedButton.icon(
                  onPressed: onConfirm,
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text("Confirmer l'arrivée"),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
                )),
              if (onConfirm != null && appt.status == 'accepted' && appt.confirmationCount < 3)
                const SizedBox(width: 8),
              if (onCancel != null)
                Expanded(child: OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      foregroundColor: kRed,
                      side: const BorderSide(color: kRed)),
                  child: const Text('Annuler'),
                )),
            ]),
          ],
        ]),
      );
}
