import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'constants.dart';
import 'api_service.dart';
import 'models.dart';
import 'storage_service.dart';
import 'socket_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  final _storage = StorageService();

  @override
  void dispose() {
    _identCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final res = await ApiService().login({
        'email_or_phone': _identCtrl.text.trim(),
        'password': _passCtrl.text,
      });
      await _storage.write(kAccessToken, res.data['access_token']);
      await _storage.write(kRefreshToken, res.data['refresh_token']);
      SocketService().connect(res.data['access_token']);
      final role = res.data['user']['role'];
      if (!mounted) return;
      final routes = {
        'patient': '/patient/home',
        'client': '/client/home',
        'doctor': '/doctor/home',
        'service_admin': '/service-admin/home',
      };
      Navigator.pushReplacementNamed(context, routes[role] ?? '/client/home');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Identifiants invalides. Veuillez réessayer.'),
          backgroundColor: kRed));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF2FBF8),
        body: SafeArea(
            child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 18),
                  Center(
                    child: Column(children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Color(0xFFDDEFE8)),
                          boxShadow: [
                            BoxShadow(
                                color: kPrimary.withOpacity(0.10),
                                blurRadius: 18,
                                offset: const Offset(0, 8))
                          ],
                        ),
                        child: const Icon(Icons.medical_services_rounded,
                            color: kPrimary, size: 30),
                      ),
                      const SizedBox(height: 14),
                      const Text('Bienvenue',
                          style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: kGray900)),
                    ]),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Color(0xFFDDEFE8)),
                      boxShadow: [
                        BoxShadow(
                            color: kPrimary.withOpacity(0.08),
                            blurRadius: 28,
                            offset: const Offset(0, 14))
                      ],
                    ),
                    child: Column(children: [
                      TextFormField(
                        controller: _identCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                            labelText: 'Email ou numéro de téléphone',
                            prefixIcon: Icon(Icons.person_outline)),
                        validator: (v) => v!.isEmpty ? 'Obligatoire' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _passCtrl,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: 'Mot de passe',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_obscure
                                ? Icons.visibility_off
                                : Icons.visibility),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) =>
                            v!.length < 6 ? 'Minimum 6 caractères' : null,
                      ),
                      const SizedBox(height: 8),
                      Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => Navigator.pushNamed(
                                context, '/forgot-password'),
                            child: const Text('Mot de passe oublié ?',
                                style: TextStyle(color: kPrimary)),
                          )),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 54),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          backgroundColor: kPrimary,
                        ),
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Text('Se connecter',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 24),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text("Vous n'avez pas de compte ? ",
                        style: TextStyle(color: kGray600)),
                    GestureDetector(
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const RegisterScreen())),
                      child: const Text("S'inscrire",
                          style: TextStyle(
                              color: kPrimary, fontWeight: FontWeight.w700)),
                    ),
                  ]),
                ],
              )),
        )),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  int? _userId;
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _newPassCtrl.dispose();
    super.dispose();
  }

  String _errorMessage(Object e, String fallback) {
    if (e is DioException && e.response?.data is Map) {
      return ((e.response!.data as Map)['error'] ?? fallback).toString();
    }
    return fallback;
  }

  Future<void> _requestOtp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final res = await ApiService().forgotPassword(_phoneCtrl.text.trim());
      if (!mounted) return;
      setState(() {
        _userId = res.data['user_id'];
        final otp = res.data['otp_code'];
        if (otp != null) _otpCtrl.text = otp.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Code de verification envoye.'),
        backgroundColor: kPrimary,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_errorMessage(e, 'Demande impossible')),
        backgroundColor: kRed,
      ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate() || _userId == null) return;
    setState(() => _loading = true);
    try {
      await ApiService().resetPassword({
        'user_id': _userId,
        'code': _otpCtrl.text.trim(),
        'new_password': _newPassCtrl.text,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Mot de passe modifie. Connectez-vous.'),
        backgroundColor: kPrimary,
      ));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_errorMessage(e, 'Reinitialisation impossible')),
        backgroundColor: kRed,
      ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasOtp = _userId != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Mot de passe oublie')),
      backgroundColor: const Color(0xFFF2FBF8),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  readOnly: hasOtp,
                  decoration: const InputDecoration(
                    labelText: 'Numero de telephone',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: (v) =>
                      v!.trim().length >= 8 ? null : 'Entrez un telephone valide',
                ),
                if (hasOtp) ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _otpCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Code OTP',
                      prefixIcon: Icon(Icons.pin_outlined),
                    ),
                    validator: (v) =>
                        v!.trim().length == 6 ? null : 'Code a 6 chiffres',
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _newPassCtrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Nouveau mot de passe',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                            _obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) =>
                        v!.length >= 6 ? null : 'Minimum 6 caracteres',
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed:
                      _loading ? null : (hasOtp ? _resetPassword : _requestOtp),
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text(hasOtp ? 'Modifier le mot de passe' : 'Envoyer le code'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();

  String _role = 'client';
  String _specialty = 'General Medicine';
  int _consultMin = 20;
  bool _loading = false;

  // Service admin fields
  List<ServiceModel> _services = [];
  int? _selectedSid;
  bool _loadingSvc = false;

  final _storage = StorageService();

  static const _specialties = [
    'General Medicine',
    'Cardiology',
    'Dermatology',
    'Pediatrics',
    'Gynecology',
    'Orthopedics',
    'Neurology',
    'Ophthalmology',
  ];
  static const _specialtyLabels = {
    'General Medicine': 'Médecine générale',
    'Cardiology': 'Cardiologie',
    'Dermatology': 'Dermatologie',
    'Pediatrics': 'Pédiatrie',
    'Gynecology': 'Gynécologie',
    'Orthopedics': 'Orthopédie',
    'Neurology': 'Neurologie',
    'Ophthalmology': 'Ophtalmologie',
  };

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadServices() async {
    setState(() => _loadingSvc = true);
    try {
      final res = await ApiService().getServicesPublic();
      setState(() {
        _services = (res.data['services'] as List)
            .map((j) => ServiceModel.fromJson(j))
            .toList();
        _loadingSvc = false;
      });
    } catch (_) {
      setState(() => _loadingSvc = false);
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    // Validate service_admin must pick a service
    if (_role == 'service_admin' && _selectedSid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Veuillez sélectionner un service'),
          backgroundColor: kRed));
      return;
    }

    setState(() => _loading = true);
    try {
      final body = <String, dynamic>{
        'full_name': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'password': _passCtrl.text,
        'role': _role,
      };
      if (_role == 'doctor') {
        body['specialty'] = _specialty;
        body['consultation_minutes'] = _consultMin;
        body['bio'] = _bioCtrl.text.trim();
      }
      if (_role == 'service_admin') {
        body['service_id'] = _selectedSid;
      }

      final res = await ApiService().register(body);
      await _storage.write(kAccessToken, res.data['access_token']);
      await _storage.write(kRefreshToken, res.data['refresh_token']);
      SocketService().connect(res.data['access_token']);
      if (!mounted) return;
      final role = res.data['user']['role'];
      final routes = {
        'patient': '/patient/home',
        'client': '/client/home',
        'doctor': '/doctor/home',
        'service_admin': '/service-admin/home',
      };
      Navigator.pushNamedAndRemoveUntil(
          context, routes[role] ?? '/client/home', (_) => false);
    } catch (e) {
      if (!mounted) return;
      String msg = "Inscription échouée.";
      if (e is DioException) {
        msg = (e.response?.data is Map)
            ? (e.response!.data['error'] ?? msg)
            : msg;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg), backgroundColor: kRed));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(title: const Text('Créer un compte')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
              key: _formKey,
              child: Column(children: [
                const SizedBox(height: 8),

                // Image for patient
                if (_role == 'patient') ...[
                  Center(
                      child: Image.asset('assets/images/doctors.png',
                          height: 180, fit: BoxFit.contain)),
                  const SizedBox(height: 16),
                ],

                // Role selector
                Row(
                    children: ['patient', 'client', 'doctor', 'service_admin']
                        .map((r) => Expanded(
                                child: Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _role = r;
                                    _selectedSid = null;
                                  });
                                  if (r == 'service_admin') _loadServices();
                                },
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: _role == r ? kPrimary : kGray100,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color:
                                            _role == r ? kPrimary : kGray200),
                                  ),
                                  child: Text(_roleLabel(r),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: _role == r
                                              ? Colors.white
                                              : kGray600,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500)),
                                ),
                              ),
                            )))
                        .toList()),
                const SizedBox(height: 20),

                // Common fields
                TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Nom complet',
                        prefixIcon: Icon(Icons.person_outline)),
                    validator: (v) => v!.isEmpty ? 'Obligatoire' : null),
                const SizedBox(height: 14),
                TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined)),
                    validator: (v) =>
                        v!.contains('@') ? null : 'Entrez un email valide'),
                const SizedBox(height: 14),
                TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                        labelText: 'Numéro de téléphone',
                        prefixIcon: Icon(Icons.phone_outlined)),
                    validator: (v) =>
                        v!.length >= 8 ? null : 'Entrez un téléphone valide'),
                const SizedBox(height: 14),
                TextFormField(
                    controller: _passCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Mot de passe',
                        prefixIcon: Icon(Icons.lock_outline)),
                    validator: (v) =>
                        v!.length >= 6 ? null : 'Minimum 6 caractères'),

                // ── Doctor fields ───────────────────────────────────────────────────
                if (_role == 'doctor') ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: kPrimaryLight,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: kPrimary.withOpacity(0.2)),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(children: [
                            Icon(Icons.medical_services,
                                color: kPrimary, size: 16),
                            SizedBox(width: 6),
                            Text('Informations médicales',
                                style: TextStyle(
                                    color: kPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                          ]),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            value: _specialty,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Spécialité',
                              prefixIcon:
                                  const Icon(Icons.local_hospital_outlined),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      const BorderSide(color: kGray200)),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      const BorderSide(color: kGray200)),
                            ),
                            items: _specialties
                                .map((s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(_specialtyLabels[s] ?? s)))
                                .toList(),
                            onChanged: (v) => setState(() => _specialty = v!),
                          ),
                          const SizedBox(height: 14),
                          Row(children: [
                            const Icon(Icons.access_time,
                                color: kPrimary, size: 16),
                            const SizedBox(width: 6),
                            Text('Durée : $_consultMin min',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: kGray900)),
                          ]),
                          Slider(
                            value: _consultMin.toDouble(),
                            min: 10,
                            max: 60,
                            divisions: 10,
                            activeColor: kPrimary,
                            label: '$_consultMin min',
                            onChanged: (v) =>
                                setState(() => _consultMin = v.round()),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _bioCtrl,
                            maxLines: 3,
                            decoration: InputDecoration(
                              labelText: 'Bio (optionnel)',
                              hintText: 'Décrivez votre expérience...',
                              prefixIcon: const Icon(Icons.notes_outlined),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      const BorderSide(color: kGray200)),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      const BorderSide(color: kGray200)),
                            ),
                          ),
                        ]),
                  ),
                ],

                // ── Service Admin fields ────────────────────────────────────────────
                if (_role == 'service_admin') ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDF2FD),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: const Color(0xFF2D6BE4).withOpacity(0.2)),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(children: [
                            Icon(Icons.admin_panel_settings,
                                color: Color(0xFF2D6BE4), size: 16),
                            SizedBox(width: 6),
                            Text('Informations du service',
                                style: TextStyle(
                                    color: Color(0xFF2D6BE4),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                          ]),
                          const SizedBox(height: 4),
                          const Text(
                              'Sélectionnez le service que vous allez gérer.',
                              style: TextStyle(color: kGray600, fontSize: 12)),
                          const SizedBox(height: 14),
                          _loadingSvc
                              ? const Center(
                                  child: Padding(
                                      padding: EdgeInsets.all(8),
                                      child: CircularProgressIndicator()))
                              : _services.isEmpty
                                  ? Column(children: [
                                      const Text('Aucun service disponible',
                                          style: TextStyle(color: kRed)),
                                      TextButton.icon(
                                        onPressed: _loadServices,
                                        icon:
                                            const Icon(Icons.refresh, size: 16),
                                        label: const Text('Recharger'),
                                      ),
                                    ])
                                  : DropdownButtonFormField<int>(
                                      value: _selectedSid,
                                      decoration: InputDecoration(
                                        labelText: 'Service à gérer',
                                        prefixIcon:
                                            const Icon(Icons.business_outlined),
                                        filled: true,
                                        fillColor: Colors.white,
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: const BorderSide(
                                                color: kGray200)),
                                        enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: const BorderSide(
                                                color: kGray200)),
                                      ),
                                      hint: const Text('Choisir un service'),
                                      isExpanded: true,
                                      items: _services
                                          .map((s) => DropdownMenuItem(
                                                value: s.id,
                                                child: Text(
                                                    '${s.name} (${s.type})',
                                                    overflow:
                                                        TextOverflow.ellipsis),
                                              ))
                                          .toList(),
                                      onChanged: (v) =>
                                          setState(() => _selectedSid = v),
                                      validator: (_) => _selectedSid == null
                                          ? 'Sélectionnez un service'
                                          : null,
                                    ),
                        ]),
                  ),
                ],

                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _loading ? null : _register,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('Créer le compte'),
                ),
              ])),
        ),
      );
}

String _roleLabel(String role) => switch (role) {
      'patient' => 'Patient',
      'client' => 'Client',
      'doctor' => 'Médecin',
      'service_admin' => 'Admin',
      _ => role,
    };
