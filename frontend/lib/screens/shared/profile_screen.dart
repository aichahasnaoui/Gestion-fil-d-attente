import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../constants.dart';
import '../../api_service.dart';
import '../../models.dart';
import '../../shared_widgets.dart';
import '../../socket_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _userData;
  bool _loading = true;
  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService().getMe();
      setState(() {
        _userData = Map<String, dynamic>.from(res.data['user']);
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

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
    await _storage.deleteAll();
    SocketService().disconnect();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_userData == null) return const Scaffold(body: Center(child: Text('Erreur de chargement')));

    final user = UserModel.fromJson(_userData!);
    final role = user.role;
    final doctorProfile = _userData!['doctor_profile'] as Map<String, dynamic>?;

    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          // Avatar + name
          Center(
            child: Column(children: [
              AvatarCircle(initials: user.initials, size: 80, bg: kPrimaryLight, fg: kPrimary),
              const SizedBox(height: 12),
              Text(user.fullName,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kGray900)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: kPrimaryLight, borderRadius: BorderRadius.circular(20)),
                child: Text(_roleLabel(role),
                    style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ]),
          ),
          const SizedBox(height: 24),

          // Basic info
          AppCard(
            child: Column(children: [
              _InfoTile(icon: Icons.email_outlined, label: 'Email', value: user.email),
              const Divider(height: 1),
              _InfoTile(icon: Icons.phone_outlined, label: 'Téléphone', value: user.phone),
              const Divider(height: 1),
              _InfoTile(
                icon: Icons.verified_outlined,
                label: 'Statut',
                value: user.isVerified ? 'Vérifié ✓' : 'Non vérifié',
                valueColor: user.isVerified ? const Color(0xFF22C55E) : kRed,
              ),
            ]),
          ),

          // Doctor-specific info
          if (role == 'doctor' && doctorProfile != null) ...[
            const SizedBox(height: 12),
            AppCard(
              child: Column(children: [
                _InfoTile(
                  icon: Icons.local_hospital_outlined,
                  label: 'Spécialité',
                  value: _specialtyLabel(doctorProfile['specialty'] ?? ''),
                ),
                const Divider(height: 1),
                _InfoTile(
                  icon: Icons.access_time,
                  label: 'Durée consultation',
                  value: '${doctorProfile['consultation_minutes'] ?? 20} min',
                ),
                const Divider(height: 1),
                _InfoTile(
                  icon: Icons.circle,
                  label: 'Accepte des RDV',
                  value: (doctorProfile['is_accepting'] == true) ? 'Oui' : 'Non',
                  valueColor: (doctorProfile['is_accepting'] == true)
                      ? const Color(0xFF22C55E)
                      : kRed,
                ),
                if ((doctorProfile['bio'] ?? '').toString().isNotEmpty) ...[
                  const Divider(height: 1),
                  _InfoTile(icon: Icons.notes, label: 'Bio', value: doctorProfile['bio']),
                ],
              ]),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _showEditDoctorProfile(doctorProfile),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Modifier le profil médical'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
            ),
          ],

          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout, color: kRed),
            label: const Text('Se déconnecter'),
            style: OutlinedButton.styleFrom(
                foregroundColor: kRed,
                side: const BorderSide(color: kRed),
                minimumSize: const Size(double.infinity, 52)),
          ),
        ]),
      ),
    );
  }

  void _showEditDoctorProfile(Map<String, dynamic> profile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EditDoctorProfileSheet(
        profile: profile,
        onSaved: _load,
      ),
    );
  }
}

class _EditDoctorProfileSheet extends StatefulWidget {
  final Map<String, dynamic> profile;
  final VoidCallback onSaved;
  const _EditDoctorProfileSheet({required this.profile, required this.onSaved});
  @override
  State<_EditDoctorProfileSheet> createState() => _EditDoctorProfileSheetState();
}

class _EditDoctorProfileSheetState extends State<_EditDoctorProfileSheet> {
  late String _specialty;
  late int _consultMin;
  late bool _isAccepting;
  late final TextEditingController _bioCtrl;
  bool _saving = false;

  static const _specialties = [
    'General Medicine', 'Cardiology', 'Dermatology', 'Pediatrics',
    'Gynecology', 'Orthopedics', 'Neurology', 'Ophthalmology',
  ];

  @override
  void initState() {
    super.initState();
    _specialty   = widget.profile['specialty'] ?? 'General Medicine';
    _consultMin  = widget.profile['consultation_minutes'] ?? 20;
    _isAccepting = widget.profile['is_accepting'] ?? true;
    _bioCtrl     = TextEditingController(text: widget.profile['bio'] ?? '');
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ApiService().updateDoctorProfile({
        'specialty': _specialty,
        'consultation_minutes': _consultMin,
        'is_accepting': _isAccepting,
        'bio': _bioCtrl.text.trim(),
      });
      widget.onSaved();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil mis à jour'), backgroundColor: kPrimary));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la mise à jour'), backgroundColor: kRed));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Modifier le profil médical',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              value: _specialty,
              decoration: const InputDecoration(labelText: 'Spécialité', prefixIcon: Icon(Icons.local_hospital_outlined)),
              items: _specialties.map((s) => DropdownMenuItem(value: s, child: Text(_specialtyLabel(s)))).toList(),
              onChanged: (v) => setState(() => _specialty = v!),
            ),
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.access_time, color: kPrimary, size: 16),
              const SizedBox(width: 8),
              Text('Durée : $_consultMin min',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            ]),
            Slider(
              value: _consultMin.toDouble(), min: 10, max: 60, divisions: 10,
              activeColor: kPrimary, label: '$_consultMin min',
              onChanged: (v) => setState(() => _consultMin = v.round()),
            ),
            SwitchListTile(
              value: _isAccepting,
              onChanged: (v) => setState(() => _isAccepting = v),
              title: const Text('Accepter les rendez-vous'),
              activeColor: kPrimary,
              contentPadding: EdgeInsets.zero,
            ),
            TextField(
              controller: _bioCtrl, maxLines: 3,
              decoration: const InputDecoration(labelText: 'Bio', hintText: 'Décrivez votre expérience...'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Enregistrer'),
            ),
            const SizedBox(height: 16),
          ]),
        ),
      );
}

String _roleLabel(String role) => switch (role) {
  'patient'   => 'Patient',
  'client'    => 'Client',
  'doctor'    => 'Médecin',
  'assistant' => 'Assistant',
  _           => role,
};

String _specialtyLabel(String s) => switch (s) {
  'General Medicine' => 'Médecine générale',
  'Cardiology'       => 'Cardiologie',
  'Dermatology'      => 'Dermatologie',
  'Pediatrics'       => 'Pédiatrie',
  'Gynecology'       => 'Gynécologie',
  'Orthopedics'      => 'Orthopédie',
  'Neurology'        => 'Neurologie',
  'Ophthalmology'    => 'Ophtalmologie',
  _                  => s,
};

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color? valueColor;
  const _InfoTile({required this.icon, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          Icon(icon, color: kGray400, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(color: kGray600, fontSize: 13))),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.end,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: valueColor ?? kGray900)),
          ),
        ]),
      );
}
