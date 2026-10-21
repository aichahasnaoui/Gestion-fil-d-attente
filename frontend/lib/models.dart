class UserModel {
  final int id;
  final String fullName, email, phone, role;
  final String? avatarUrl;
  final bool isVerified;
  UserModel(
      {required this.id,
      required this.fullName,
      required this.email,
      required this.phone,
      required this.role,
      this.avatarUrl,
      required this.isVerified});
  factory UserModel.fromJson(Map<String, dynamic> j) => UserModel(
      id: j['id'],
      fullName: j['full_name'] ?? '',
      email: j['email'] ?? '',
      phone: j['phone'] ?? '',
      role: j['role'] ?? 'client',
      avatarUrl: j['avatar_url'],
      isVerified: j['is_verified'] ?? false);
  String get initials {
    final p = fullName.trim().split(' ');
    if (fullName.trim().isEmpty) return '?';
    return p.length >= 2
        ? '${p[0][0]}${p[1][0]}'.toUpperCase()
        : fullName.substring(0, fullName.length.clamp(1, 2)).toUpperCase();
  }
}

class TicketModel {
  final int id, queueId, serviceId, userId, ticketNumber, confirmationCount;
  final String status, qrCode, issuedAt;
  final int? estimatedWaitMin;
  final String? serviceName, serviceLogo;
  int ahead;
  TicketModel(
      {required this.id,
      required this.queueId,
      required this.serviceId,
      required this.userId,
      required this.ticketNumber,
      required this.status,
      required this.qrCode,
      required this.issuedAt,
      required this.confirmationCount,
      this.estimatedWaitMin,
      this.serviceName,
      this.serviceLogo,
      this.ahead = 0});
  factory TicketModel.fromJson(Map<String, dynamic> j) => TicketModel(
      id: j['id'],
      queueId: j['queue_id'],
      serviceId: j['service_id'] ?? 0,
      userId: j['user_id'],
      ticketNumber: j['ticket_number'],
      status: j['status'] ?? 'waiting',
      qrCode: j['qr_code'] ?? '',
      issuedAt: j['issued_at'] ?? '',
      confirmationCount: j['confirmation_count'] ?? 0,
      estimatedWaitMin: j['estimated_wait_min'],
      serviceName: j['service_name'],
      serviceLogo: j['service_logo'],
      ahead: j['ahead'] ?? 0);
  bool get isActive => ['waiting', 'called', 'confirmed'].contains(status);
  bool get needsConfirmation =>
      ahead <= 4 &&
      confirmationCount < 3 &&
      ['waiting', 'called'].contains(status);
}

class AppointmentModel {
  final int id, patientId, doctorId, confirmationCount;
  final String scheduledAt, status, createdAt;
  final String? reason, doctorNotes, patientName, doctorName, doctorSpecialty;
  AppointmentModel(
      {required this.id,
      required this.patientId,
      required this.doctorId,
      required this.scheduledAt,
      required this.status,
      required this.createdAt,
      this.reason,
      this.doctorNotes,
      this.patientName,
      this.doctorName,
      this.doctorSpecialty,
      required this.confirmationCount});
  factory AppointmentModel.fromJson(Map<String, dynamic> j) => AppointmentModel(
      id: j['id'],
      patientId: j['patient_id'],
      doctorId: j['doctor_id'],
      scheduledAt: j['scheduled_at'] ?? '',
      status: j['status'] ?? 'pending',
      createdAt: j['created_at'] ?? '',
      reason: j['reason'],
      doctorNotes: j['doctor_notes'],
      patientName: j['patient_name'],
      doctorName: j['doctor_name'],
      doctorSpecialty: j['doctor_specialty'],
      confirmationCount: j['confirmation_count'] ?? 0);

  bool get isExpired => status == 'expired';
  bool get isPast {
    try { return DateTime.parse(scheduledAt).isBefore(DateTime.now()); }
    catch (_) { return false; }
  }
}

class ServiceModel {
  final int id, todayInQueue, todayAvgWait, maxDailyTickets, todayTotalIssued, openGuichets;
  final String name, type;
  final String? address, wilaya, logoUrl;
  final bool isActive;
  ServiceModel(
      {required this.id,
      required this.name,
      required this.type,
      this.address,
      this.wilaya,
      this.logoUrl,
      required this.todayInQueue,
      required this.todayAvgWait,
      this.maxDailyTickets = 200,
      this.todayTotalIssued = 0,
      this.openGuichets = 0,
      required this.isActive});
  factory ServiceModel.fromJson(Map<String, dynamic> j) => ServiceModel(
      id: j['id'],
      name: j['name'] ?? '',
      type: j['type'] ?? 'other',
      address: j['address'],
      wilaya: j['wilaya'],
      logoUrl: j['logo_url'],
      todayInQueue: j['today_in_queue'] ?? 0,
      todayAvgWait: j['today_avg_wait'] ?? 0,
      maxDailyTickets: j['max_daily_tickets'] ?? 200,
      todayTotalIssued: j['today_total_issued'] ?? 0,
      openGuichets: j['open_guichets'] ?? 0,
      isActive: j['is_active'] ?? true);
  int get remainingTickets => (maxDailyTickets - todayTotalIssued).clamp(0, maxDailyTickets);
}

class NotificationModel {
  final int id;
  final String type, title, body, sentAt;
  final bool isRead;
  final Map<String, dynamic>? data;
  NotificationModel(
      {required this.id,
      required this.type,
      required this.title,
      required this.body,
      required this.sentAt,
      required this.isRead,
      this.data});
  factory NotificationModel.fromJson(Map<String, dynamic> j) =>
      NotificationModel(
          id: j['id'],
          type: j['type'] ?? 'system',
          title: j['title'] ?? '',
          body: j['body'] ?? '',
          sentAt: j['sent_at'] ?? '',
          isRead: j['is_read'] ?? false,
          data:
              j['data'] != null ? Map<String, dynamic>.from(j['data']) : null);
}

class RecordModel {
  final int id;
  final String recordType, title, fileUrl, fileType, uploadedAt;
  final String? notes;
  final bool isShared;
  RecordModel(
      {required this.id,
      required this.recordType,
      required this.title,
      required this.fileUrl,
      required this.fileType,
      required this.uploadedAt,
      this.notes,
      required this.isShared});
  factory RecordModel.fromJson(Map<String, dynamic> j) => RecordModel(
      id: j['id'],
      recordType: j['record_type'] ?? 'other',
      title: j['title'] ?? '',
      fileUrl: j['file_url'] ?? '',
      fileType: j['file_type'] ?? '',
      uploadedAt: j['uploaded_at'] ?? '',
      notes: j['notes'],
      isShared: j['is_shared_with_doctor'] ?? false);
}

class DoctorModel {
  final int id;
  final int? serviceId;
  final int consultationMinutes;
  final String specialty, bio;
  final bool isAccepting;
  final UserModel user;
  DoctorModel(
      {required this.id,
      this.serviceId,
      required this.specialty,
      required this.bio,
      required this.consultationMinutes,
      required this.isAccepting,
      required this.user});
  factory DoctorModel.fromJson(Map<String, dynamic> j) => DoctorModel(
      id: j['id'],
      serviceId: j['service_id'],
      specialty: j['specialty'] ?? 'General',
      bio: j['bio'] ?? '',
      consultationMinutes: j['consultation_minutes'] ?? 20,
      isAccepting: j['is_accepting'] ?? true,
      user: UserModel.fromJson(j['user'] ?? {}));
}

class PrescriptionModel {
  final int id, appointmentId, doctorId, patientId;
  final List<dynamic> medications;
  final String? instructions, createdAt, patientName;
  PrescriptionModel(
      {required this.id,
      required this.appointmentId,
      required this.doctorId,
      required this.patientId,
      required this.medications,
      this.instructions,
      this.createdAt,
      this.patientName});
  factory PrescriptionModel.fromJson(Map<String, dynamic> j) =>
      PrescriptionModel(
          id: j['id'],
          appointmentId: j['appointment_id'],
          doctorId: j['doctor_id'],
          patientId: j['patient_id'],
          medications: j['medications'] ?? [],
          instructions: j['instructions'],
          createdAt: j['created_at'],
          patientName: j['patient_name']);
}
