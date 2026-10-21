import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_service.dart';
import '../constants.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  List<dynamic> _conversations = [];
  String _role = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final userRes = await ApiService().getMe();
      final convRes = await ApiService().getConversations();
      if (!mounted) return;
      setState(() {
        _role = userRes.data['user']['role'] ?? '';
        _conversations = convRes.data['conversations'] ?? [];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      return DateFormat('dd MMM HH:mm', 'fr_FR').format(DateTime.parse(raw).toLocal());
    } catch (_) {
      return '';
    }
  }

  Future<void> _openNewConversation() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NewConversationSheet(),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = _role == 'patient' || _role == 'client';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: _openNewConversation,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Nouveau'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _conversations.isEmpty
              ? const _EmptyMessages()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _conversations.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final c = _conversations[i] as Map;
                      final name = _role == 'doctor'
                          ? (c['patient_name'] ?? 'Patient')
                          : (c['doctor_name'] ?? 'Medecin');
                      final record = c['record_title'];
                      return _ConversationTile(
                        title: name,
                        subject: c['subject'] ?? 'Conversation',
                        recordTitle: record is String ? record : null,
                        preview: c['last_message'] ?? '',
                        date: _formatDate(c['last_message_at'] ?? c['updated_at']),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatThreadScreen(
                                conversationId: c['id'],
                                title: name,
                              ),
                            ),
                          );
                          _load();
                        },
                      );
                    },
                  ),
                ),
    );
  }
}

class ChatThreadScreen extends StatefulWidget {
  final int conversationId;
  final String title;

  const ChatThreadScreen({
    super.key,
    required this.conversationId,
    required this.title,
  });

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  List<dynamic> _messages = [];
  Map<String, dynamic>? _conversation;
  int? _myId;
  bool _loading = true;
  bool _sending = false;
  bool _attaching = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final userRes = await ApiService().getMe();
      final msgRes = await ApiService().getConversationMessages(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _myId = userRes.data['user']['id'];
        _conversation = Map<String, dynamic>.from(msgRes.data['conversation']);
        _messages = msgRes.data['messages'] ?? [];
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final res = await ApiService().sendConversationMessage(widget.conversationId, body);
      _controller.clear();
      setState(() => _messages.add(res.data['message']));
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorText(e)), backgroundColor: kRed),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendAttachment() async {
    if (_sending || _attaching) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible de lire le fichier.'),
          backgroundColor: kRed,
        ),
      );
      return;
    }

    setState(() => _attaching = true);
    try {
      final fd = FormData.fromMap({
        'body': _controller.text.trim(),
        'file': MultipartFile.fromBytes(file.bytes!, filename: file.name),
      });
      final res = await ApiService().sendConversationAttachment(widget.conversationId, fd);
      _controller.clear();
      setState(() => _messages.add(res.data['message']));
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorText(e)), backgroundColor: kRed),
      );
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  String _errorText(Object e) {
    if (e is DioException && e.response?.data is Map) {
      return ((e.response!.data as Map)['error'] ?? 'Envoi impossible').toString();
    }
    return 'Envoi impossible';
  }

  String _time(String? raw) {
    if (raw == null) return '';
    try {
      return DateFormat('HH:mm', 'fr_FR').format(DateTime.parse(raw).toLocal());
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final recordTitle = _conversation?['record_title'];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        bottom: recordTitle is String && recordTitle.isNotEmpty
            ? PreferredSize(
                preferredSize: const Size.fromHeight(34),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Text(
                      'Dossier: $recordTitle',
                      style: const TextStyle(color: kGray600, fontSize: 12),
                    ),
                  ),
                ),
              )
            : null,
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final m = _messages[i] as Map;
                      final mine = m['sender_id'] == _myId;
                      return _MessageBubble(
                        mine: mine,
                        body: m['body'] ?? '',
                        attachmentUrl: m['attachment_url'],
                        attachmentType: m['attachment_type'],
                        attachmentName: m['attachment_name'],
                        time: _time(m['created_at']),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              color: Colors.white,
              child: Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Joindre une image ou un PDF',
                    onPressed: _attaching ? null : _sendAttachment,
                    icon: _attaching
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.attach_file),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Ecrire un message...',
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
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

class _NewConversationSheet extends StatefulWidget {
  const _NewConversationSheet();

  @override
  State<_NewConversationSheet> createState() => _NewConversationSheetState();
}

class _NewConversationSheetState extends State<_NewConversationSheet> {
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  List<dynamic> _doctors = [];
  List<dynamic> _records = [];
  int? _doctorId;
  int? _recordId;
  PlatformFile? _attachment;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final doctorsRes = await ApiService().listDoctors();
      final recordsRes = await ApiService().getMyRecords();
      if (!mounted) return;
      setState(() {
        _doctors = doctorsRes.data['doctors'] ?? [];
        _records = recordsRes.data['records'] ?? [];
        if (_doctors.isNotEmpty) _doctorId = _doctors.first['id'];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final message = _messageCtrl.text.trim();
    if (_doctorId == null || (message.isEmpty && _attachment == null) || _sending) return;
    setState(() => _sending = true);
    try {
      if (_attachment == null) {
        await ApiService().createConversation({
          'doctor_id': _doctorId,
          'record_id': _recordId,
          'subject': _subjectCtrl.text.trim(),
          'message': message,
        }..removeWhere((_, value) => value == null || value == ''));
      } else {
        final file = _attachment!;
        final fd = FormData.fromMap({
          'doctor_id': _doctorId,
          if (_recordId != null) 'record_id': _recordId,
          if (_subjectCtrl.text.trim().isNotEmpty) 'subject': _subjectCtrl.text.trim(),
          'message': message,
          'file': MultipartFile.fromBytes(file.bytes!, filename: file.name),
        });
        await ApiService().createConversationWithFile(fd);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorText(e)), backgroundColor: kRed),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible de lire le fichier.'),
          backgroundColor: kRed,
        ),
      );
      return;
    }
    setState(() => _attachment = file);
  }

  Future<void> _uploadRecordFromDevice() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible de lire le fichier.'),
          backgroundColor: kRed,
        ),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      final ext = file.extension?.toLowerCase();
      final fd = FormData.fromMap({
        'file': MultipartFile.fromBytes(file.bytes!, filename: file.name),
        'record_type': ext == 'pdf' ? 'report' : 'image',
        'title': file.name,
      });
      final uploadRes = await ApiService().uploadRecord(fd);
      final recordsRes = await ApiService().getMyRecords();
      final created = uploadRes.data['record'] as Map?;
      if (!mounted) return;
      setState(() {
        _records = recordsRes.data['records'] ?? [];
        _recordId = created?['id'];
        if (_subjectCtrl.text.trim().isEmpty && created?['title'] is String) {
          _subjectCtrl.text = created!['title'];
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorText(e)), backgroundColor: kRed),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _errorText(Object e) {
    if (e is DioException && e.response?.data is Map) {
      return ((e.response!.data as Map)['error'] ?? 'Creation impossible').toString();
    }
    return 'Creation impossible';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: _loading
          ? const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Nouveau message',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context, false),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: _doctorId,
                    decoration: const InputDecoration(labelText: 'Medecin'),
                    items: _doctors.map((d) {
                      final user = d['user'] as Map?;
                      return DropdownMenuItem<int>(
                        value: d['id'],
                        child: Text(user?['full_name'] ?? 'Medecin'),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _doctorId = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: _recordId,
                    decoration: const InputDecoration(labelText: 'Dossier medical'),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Sans dossier specifique'),
                      ),
                      ..._records.map((r) => DropdownMenuItem<int?>(
                            value: r['id'],
                            child: Text(r['title'] ?? 'Dossier'),
                          )),
                    ],
                    onChanged: (v) => setState(() => _recordId = v),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _sending ? null : _uploadRecordFromDevice,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text('Ajouter un dossier depuis l\'appareil'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _subjectCtrl,
                    decoration: const InputDecoration(labelText: 'Sujet'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _messageCtrl,
                    minLines: 4,
                    maxLines: 6,
                    decoration: const InputDecoration(labelText: 'Message'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _pickAttachment,
                    icon: const Icon(Icons.attach_file),
                    label: Text(_attachment == null
                        ? 'Joindre une image ou un PDF'
                        : _attachment!.name),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send_outlined),
                    label: Text(_sending ? 'Envoi...' : 'Envoyer'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final String title;
  final String subject;
  final String? recordTitle;
  final String preview;
  final String date;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.title,
    required this.subject,
    required this.recordTitle,
    required this.preview,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: kGray200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: kPrimaryLight,
                child: Icon(Icons.chat_bubble_outline, color: kPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.w700, color: kGray900),
                          ),
                        ),
                        Text(date, style: const TextStyle(color: kGray400, fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(subject, style: const TextStyle(color: kGray700, fontSize: 13)),
                    if (recordTitle != null) ...[
                      const SizedBox(height: 3),
                      Text('Dossier: $recordTitle', style: const TextStyle(color: kPrimary, fontSize: 12)),
                    ],
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: kGray500, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final bool mine;
  final String body;
  final String? attachmentUrl;
  final String? attachmentType;
  final String? attachmentName;
  final String time;

  const _MessageBubble({
    required this.mine,
    required this.body,
    required this.attachmentUrl,
    required this.attachmentType,
    required this.attachmentName,
    required this.time,
  });

  bool get _hasAttachment => attachmentUrl != null && attachmentUrl!.isNotEmpty;
  bool get _isImage => ['png', 'jpg', 'jpeg'].contains((attachmentType ?? '').toLowerCase());

  String get _fullAttachmentUrl =>
      '${kBaseUrl.replaceAll('/api', '')}$attachmentUrl';

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? kPrimary : Colors.white,
          border: Border.all(color: mine ? kPrimary : kGray200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (_hasAttachment) ...[
              _AttachmentPreview(
                url: _fullAttachmentUrl,
                name: attachmentName ?? 'Piece jointe',
                isImage: _isImage,
                mine: mine,
              ),
              if (body.isNotEmpty) const SizedBox(height: 8),
            ],
            if (body.isNotEmpty)
              Text(
                body,
                style: TextStyle(color: mine ? Colors.white : kGray900, height: 1.35),
              ),
            const SizedBox(height: 4),
            Text(
              time,
              style: TextStyle(color: mine ? Colors.white70 : kGray400, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  final String url;
  final String name;
  final bool isImage;
  final bool mine;

  const _AttachmentPreview({
    required this.url,
    required this.name,
    required this.isImage,
    required this.mine,
  });

  @override
  Widget build(BuildContext context) {
    if (!isImage) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.picture_as_pdf_outlined, color: mine ? Colors.white : kRed),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: mine ? Colors.white : kGray900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _ChatImageViewer(title: name, imageUrl: url),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          url,
          width: 220,
          height: 160,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 220,
            height: 120,
            color: mine ? Colors.white24 : kGray100,
            child: Icon(Icons.broken_image_outlined,
                color: mine ? Colors.white70 : kGray500),
          ),
        ),
      ),
    );
  }
}

class _ChatImageViewer extends StatelessWidget {
  final String title;
  final String imageUrl;

  const _ChatImageViewer({required this.title, required this.imageUrl});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(title),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: Image.network(imageUrl, fit: BoxFit.contain),
          ),
        ),
      );
}

class _EmptyMessages extends StatelessWidget {
  const _EmptyMessages();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 52, color: kGray400),
            SizedBox(height: 12),
            Text(
              'Aucune conversation',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            SizedBox(height: 6),
            Text(
              'Les echanges lies aux dossiers medicaux apparaitront ici.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kGray600),
            ),
          ],
        ),
      ),
    );
  }
}
