import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'constants.dart';
import 'storage_service.dart';

class ApiService {
  static final ApiService _i = ApiService._();
  factory ApiService() => _i;
  ApiService._();

  final _storage = StorageService();
  late final Dio _dio;
  VoidCallback? onSessionExpired;

  void init() {
    _dio = Dio(BaseOptions(
        baseUrl: kBaseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Content-Type': 'application/json'}));

    if (kDebugMode) {
      print('ApiService initialized with baseUrl: $kBaseUrl');
    }
    _dio.interceptors.add(
      InterceptorsWrapper(onRequest: (o, h) async {
        final t = await _storage.read(kAccessToken);
        if (t != null) o.headers['Authorization'] = 'Bearer $t';
        h.next(o);
      }, onError: (e, h) async {
        final isRefreshCall = e.requestOptions.path.contains('/auth/refresh');
        if (e.response?.statusCode == 401 && !isRefreshCall) {
          if (await _refreshToken()) {
            final t = await _storage.read(kAccessToken);
            e.requestOptions.headers['Authorization'] = 'Bearer $t';
            return h.resolve(await _dio.fetch(e.requestOptions));
          } else {
            await _storage.delete(kAccessToken);
            await _storage.delete(kRefreshToken);
            onSessionExpired?.call();
          }
        }
        h.next(e);
      }),
    );
  }

  Future<bool> _refreshToken() async {
    try {
      final r = await _storage.read(kRefreshToken);
      if (r == null) return false;
      final res = await _dio.post('/auth/refresh',
          options: Options(headers: {'Authorization': 'Bearer $r'}));
      await _storage.write(kAccessToken, res.data['access_token']);
      return true;
    } catch (_) {
      return false;
    }
  }

  // Auth
  Future<Response> register(Map<String, dynamic> b) {
    if (kDebugMode) {
      print('API CALL: register, data: $b');
    }
    return _dio.post('/auth/register', data: b);
  }
  Future<Response> login(Map<String, dynamic> b) {
    if (kDebugMode) {
      print('API CALL: login, data: $b');
    }
    return _dio.post('/auth/login', data: b);
  }
  Future<Response> forgotPassword(String phone) => _dio.post('/auth/forgot-password', data: {'phone': phone});
  Future<Response> resetPassword(Map b) => _dio.post('/auth/reset-password', data: b);

  // Users
  Future<Response> getMe() => _dio.get('/users/me');
  Future<Response> updateMe(Map b) => _dio.patch('/users/me', data: b);
  Future<Response> upsertPatientProfile(Map b) => _dio.put('/users/me/patient-profile', data: b);
  Future<Response> updateDoctorProfile(Map b) => _dio.patch('/users/me/doctor-profile', data: b);

  // Services
  Future<Response> getServicesPublic() => _dio.get('/services/public');
  Future<Response> getServices({String? type, String? wilaya}) =>
      _dio.get('/services', queryParameters: {'type': type, 'wilaya': wilaya}..removeWhere((k, v) => v == null));
  Future<Response> getService(int id) => _dio.get('/services/$id');
  Future<Response> getQueueStatus(int id) => _dio.get('/services/$id/queue-status');

  // Tickets
  Future<Response> issueTicket(int serviceId) => _dio.post('/tickets', data: {'service_id': serviceId});
  Future<Response> getMyTickets() => _dio.get('/tickets/my');
  Future<Response> getTicket(int id) => _dio.get('/tickets/$id');
  Future<Response> confirmTicket(int id) => _dio.post('/tickets/$id/confirm');
  Future<Response> cancelTicket(int id) => _dio.post('/tickets/$id/cancel');
  Future<Response> getLiveQueue(int serviceId) => _dio.get('/tickets/queue/$serviceId');

  // Appointments
  Future<Response> bookAppointment(Map b) => _dio.post('/appointments', data: b);
  Future<Response> getMyAppointments() => _dio.get('/appointments/my');
  Future<Response> expirePastAppointments() => _dio.post('/appointments/expire-past');
  Future<Response> markAttended(int id) => _dio.post('/appointments/$id/attended');
  Future<Response> updateAppointmentStatus(int id, Map b) => _dio.patch('/appointments/$id/status', data: b);
  Future<Response> confirmAppointment(int id) => _dio.post('/appointments/$id/confirm');
  Future<Response> cancelAppointment(int id, {String reason = ''}) => _dio.post('/appointments/$id/cancel', data: {'reason': reason});

  // Doctors
  Future<Response> listDoctors({String? specialty, String? serviceId, String? wilaya}) =>
      _dio.get('/doctors', queryParameters: {'specialty': specialty, 'service_id': serviceId, 'wilaya': wilaya}..removeWhere((k, v) => v == null));
  Future<Response> getMyPatients() => _dio.get('/doctors/me/patients');

  // Records
  Future<Response> getMyRecords() => _dio.get('/records/my');
  Future<Response> deleteRecord(int id) => _dio.delete('/records/$id');
  Future<Response> uploadRecord(FormData fd) => _dio.post('/records/upload', data: fd);
  Future<Response> getPatientRecords(int pid) => _dio.get('/records/patient/$pid');
  Future<Response> getMyPrescriptions() => _dio.get('/prescriptions/my');
  Future<Response> createPrescription(Map b) => _dio.post('/prescriptions', data: b);

  // Service Admin
  Future<Response> getServiceAdminDashboard() => _dio.get('/service-admin/dashboard');
  Future<Response> serviceAdminToggleQueue() => _dio.patch('/service-admin/queue/toggle');
  Future<Response> serviceAdminCallNext() => _dio.post('/service-admin/call-next');
  Future<Response> serviceAdminCheckNoShows() => _dio.post('/service-admin/check-no-shows');
  Future<Response> serviceAdminCancelCurrent() => _dio.post('/service-admin/cancel-current');
  Future<Response> getGuichets() => _dio.get('/service-admin/guichets');
  Future<Response> addGuichet() => _dio.post('/service-admin/guichets');
  Future<Response> toggleGuichet(int id) => _dio.patch('/service-admin/guichets/$id/toggle');
  Future<Response> deleteGuichet(int id) => _dio.delete('/service-admin/guichets/$id');
  Future<Response> updateServiceSettings(Map b) => _dio.patch('/service-admin/service', data: b);
  Future<Response> getPublicGuichets(int sid) => _dio.get('/services/$sid/guichets');

  // Notifications
  Future<Response> getNotifications() => _dio.get('/notifications');
  Future<Response> readAllNotifications() => _dio.post('/notifications/read-all');
  Future<Response> readNotification(int id) => _dio.patch('/notifications/$id/read');

  // Chat / Conversations
  Future<Response> getConversations() => _dio.get('/chat/conversations');
  Future<Response> createConversation(Map b) => _dio.post('/chat/conversations', data: b);
  Future<Response> createConversationWithFile(FormData fd) => _dio.post('/chat/conversations', data: fd);
  Future<Response> getConversationMessages(int id) => _dio.get('/chat/conversations/$id/messages');
  Future<Response> sendConversationMessage(int id, String body) => _dio.post('/chat/conversations/$id/messages', data: {'body': body});
  Future<Response> sendConversationAttachment(int id, FormData fd) => _dio.post('/chat/conversations/$id/messages', data: fd);
}
