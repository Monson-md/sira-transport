import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../auth/services/auth_service.dart';
import '../models/driver_document_model.dart';
import '../services/driver_documents_service.dart';

const Map<String, String> _kStatusLabels = {
  'pending_review': 'En cours de vérification',
  'approved': 'Validé',
  'rejected': 'Refusé — à renvoyer',
};

/// Écran d'envoi des pièces d'un chauffeur (identité, permis, carte grise,
/// photo du véhicule) vers Firebase Storage + collection driver_documents.
class DriverDocumentsScreen extends StatefulWidget {
  const DriverDocumentsScreen({super.key});

  @override
  State<DriverDocumentsScreen> createState() => _DriverDocumentsScreenState();
}

class _DriverDocumentsScreenState extends State<DriverDocumentsScreen> {
  final _authService = AuthService();
  final _documentsService = DriverDocumentsService();
  final _picker = ImagePicker();

  final Set<String> _uploadingTypes = {};

  Future<void> _pickAndUpload(String type, ImageSource source) async {
    final uid = _authService.currentUser?.uid;
    if (uid == null) return;

    final picked = await _picker.pickImage(source: source, imageQuality: 80);
    if (picked == null) return;

    setState(() => _uploadingTypes.add(type));
    try {
      await _documentsService.uploadDocument(
        driverId: uid,
        type: type,
        file: File(picked.path),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${kDriverDocumentLabels[type]} envoyé.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _uploadingTypes.remove(type));
    }
  }

  void _showSourcePicker(String type) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Prendre une photo'),
              onTap: () {
                Navigator.of(context).pop();
                _pickAndUpload(type, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir dans la galerie'),
              onTap: () {
                Navigator.of(context).pop();
                _pickAndUpload(type, ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = _authService.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Mon dossier')),
      body: uid == null
          ? const Center(child: Text('Impossible de charger votre compte.'))
          : StreamBuilder<List<DriverDocumentModel>>(
              stream: _documentsService.watchMyDocuments(uid),
              builder: (context, snapshot) {
                final docs = snapshot.data ?? [];
                // Le document le plus récent de chaque type (la liste est
                // déjà triée par uploadedAt décroissant).
                final latestByType = <String, DriverDocumentModel>{};
                for (final doc in docs) {
                  latestByType.putIfAbsent(doc.type, () => doc);
                }

                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      'Envoyez vos 4 pièces pour activer votre compte chauffeur. '
                      "C'est ce contrôle qui rassure les clients.",
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 20),
                    ...kDriverDocumentTypes.map(
                      (type) => _DocumentTile(
                        label: kDriverDocumentLabels[type]!,
                        document: latestByType[type],
                        isUploading: _uploadingTypes.contains(type),
                        onUpload: () => _showSourcePicker(type),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  final String label;
  final DriverDocumentModel? document;
  final bool isUploading;
  final VoidCallback onUpload;

  const _DocumentTile({
    required this.label,
    required this.document,
    required this.isUploading,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final canUpload = document == null || document!.status == 'rejected';

    Color statusColor;
    String statusText;
    if (document == null) {
      statusColor = colorScheme.error;
      statusText = 'Manquante';
    } else {
      statusText = _kStatusLabels[document!.status] ?? document!.status;
      statusColor = switch (document!.status) {
        'approved' => Colors.green,
        'rejected' => colorScheme.error,
        _ => colorScheme.primary,
      };
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(statusText, style: TextStyle(color: statusColor, fontSize: 12.5)),
                ],
              ),
            ),
            if (isUploading)
              const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (canUpload)
              OutlinedButton(
                onPressed: onUpload,
                child: Text(document == null ? 'Ajouter' : 'Renvoyer'),
              )
            else
              const Icon(Icons.check_circle_outline, color: Colors.green),
          ],
        ),
      ),
    );
  }
}
