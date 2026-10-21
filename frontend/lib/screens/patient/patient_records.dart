import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import '../../constants.dart';
import '../../api_service.dart';
import '../../models.dart';
import '../../shared_widgets.dart';

class PatientRecordsScreen extends StatefulWidget {
  const PatientRecordsScreen({super.key});
  @override
  State<PatientRecordsScreen> createState() => _PatientRecordsState();
}

class _PatientRecordsState extends State<PatientRecordsScreen> {
  List<RecordModel> _records = [];
  bool _loading = true;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService().getMyRecords();
      setState(() {
        _records = (res.data['records'] as List)
            .map((j) => RecordModel.fromJson(j))
            .toList();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _upload() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final PlatformFile file = result.files.first;

    if (!mounted) return;
    final String? type = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Type de dossier'),
        children: ['image', 'analysis', 'report', 'other']
            .map((t) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, t),
                  child: Text(_recordTypeLabel(t)),
                ))
            .toList(),
      ),
    );
    if (type == null) return;

    setState(() => _uploading = true);
    try {
      if (file.bytes == null) {
        throw Exception('Impossible de lire le fichier. Veuillez réessayer.');
      }
      final multipartFile = MultipartFile.fromBytes(file.bytes!, filename: file.name);
      final fd = FormData.fromMap({
        'file': multipartFile,
        'record_type': type,
        'title': file.name,
      });
      await ApiService().uploadRecord(fd);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Dossier ajouté avec succès ✅'), backgroundColor: kPrimary));
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = (e.response?.data is Map)
          ? (e.response!.data['error'] ?? "Échec de l'ajout")
          : "Échec de l'ajout (${e.response?.statusCode})";
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg.toString()), backgroundColor: kRed));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: kRed));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _delete(RecordModel r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer le dossier'),
        content: Text('Supprimer "${r.title}" ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Non')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Supprimer', style: TextStyle(color: kRed))),
        ],
      ),
    );
    if (ok != true) return;
    await ApiService().deleteRecord(r.id);
    _load();
  }

  void _viewImage(RecordModel r) {
    final imageUrl = '${kBaseUrl.replaceAll('/api', '')}${r.fileUrl}';
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _ImageViewerScreen(title: r.title, imageUrl: imageUrl),
    ));
  }

  bool _isImage(RecordModel r) =>
      ['jpg', 'jpeg', 'png'].contains(r.fileType.toLowerCase()) ||
      r.recordType == 'image';

  IconData _iconFor(String type) => switch (type) {
        'image'        => Icons.image_outlined,
        'analysis'     => Icons.science_outlined,
        'prescription' => Icons.medication_outlined,
        'report'       => Icons.description_outlined,
        _              => Icons.attach_file,
      };

  Color _colorFor(String type) => switch (type) {
        'image'        => kSecondary,
        'analysis'     => kPurple,
        'prescription' => kPrimary,
        'report'       => kAmber,
        _              => kGray600,
      };

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Dossiers médicaux'),
          actions: [
            if (_uploading)
              const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)))
            else
              IconButton(
                icon: const Icon(Icons.upload_file_outlined),
                onPressed: _upload,
                tooltip: 'Ajouter un dossier',
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _records.isEmpty
                ? const EmptyState(
                    icon: '📁',
                    title: 'Aucun dossier',
                    subtitle: 'Ajoutez vos images médicales, analyses et rapports',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _records.length,
                    itemBuilder: (_, i) {
                      final r = _records[i];
                      final color = _colorFor(r.recordType);
                      final isImg = _isImage(r);
                      final imageUrl = '${kBaseUrl.replaceAll('/api', '')}${r.fileUrl}';

                      return AppCard(
                        onTap: isImg ? () => _viewImage(r) : null,
                        child: Row(children: [
                          // Thumbnail for images, icon for others
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: isImg
                                ? Image.network(
                                    imageUrl,
                                    width: 56,
                                    height: 56,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 56, height: 56,
                                      color: color.withOpacity(0.1),
                                      child: Icon(_iconFor(r.recordType), color: color, size: 26),
                                    ),
                                    loadingBuilder: (_, child, progress) =>
                                        progress == null
                                            ? child
                                            : Container(
                                                width: 56, height: 56,
                                                color: kGray100,
                                                child: const Center(
                                                    child: SizedBox(width: 20, height: 20,
                                                        child: CircularProgressIndicator(strokeWidth: 2))),
                                              ),
                                  )
                                : Container(
                                    width: 56, height: 56,
                                    decoration: BoxDecoration(
                                        color: color.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12)),
                                    child: Icon(_iconFor(r.recordType), color: color, size: 26),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(r.title,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 2),
                                Text('${_recordTypeLabel(r.recordType)} · ${r.uploadedAt.substring(0, 10)}',
                                    style: const TextStyle(color: kGray600, fontSize: 12)),
                                if (isImg)
                                  const Text('Appuyez pour voir',
                                      style: TextStyle(color: kPrimary, fontSize: 11,
                                          fontWeight: FontWeight.w500)),
                                if (r.isShared)
                                  const Text('Partagé avec le médecin',
                                      style: TextStyle(color: kPrimary, fontSize: 11,
                                          fontWeight: FontWeight.w500)),
                              ])),
                          PopupMenuButton<String>(
                            onSelected: (v) { if (v == 'delete') _delete(r); },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Supprimer', style: TextStyle(color: kRed))),
                            ],
                            child: const Icon(Icons.more_vert, color: kGray400),
                          ),
                        ]),
                      );
                    }),
      );
}

// ── Full screen image viewer ──────────────────────────────────────────────────
class _ImageViewerScreen extends StatelessWidget {
  final String title, imageUrl;
  const _ImageViewerScreen({required this.title, required this.imageUrl});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(title, style: const TextStyle(color: Colors.white)),
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image, color: Colors.white54, size: 64),
                  SizedBox(height: 12),
                  Text('Impossible de charger l\'image',
                      style: TextStyle(color: Colors.white54)),
                ],
              ),
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : const CircularProgressIndicator(color: Colors.white),
            ),
          ),
        ),
      );
}

String _recordTypeLabel(String type) => switch (type) {
      'image'        => 'Image',
      'analysis'     => 'Analyse',
      'prescription' => 'Ordonnance',
      'report'       => 'Rapport',
      'other'        => 'Autre',
      _              => type,
    };
