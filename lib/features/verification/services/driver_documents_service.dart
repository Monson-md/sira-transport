import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/driver_document_model.dart';

class DriverDocumentsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> get _docsRef =>
      _firestore.collection('driver_documents');

  /// Envoie une pièce vers Firebase Storage puis crée le document
  /// Firestore correspondant (statut 'pending_review'). uploadedAt est fixé
  /// côté serveur via FieldValue.serverTimestamp().
  Future<void> uploadDocument({
    required String driverId,
    required String type,
    required File file,
  }) async {
    final storagePath =
        'driver_documents/$driverId/$type-${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = _storage.ref(storagePath);
    await ref.putFile(file);
    final downloadUrl = await ref.getDownloadURL();

    final docRef = _docsRef.doc();
    await docRef.set({
      'id': docRef.id,
      'driverId': driverId,
      'type': type,
      'storagePath': storagePath,
      'downloadUrl': downloadUrl,
      'status': 'pending_review',
      'uploadedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Flux temps réel des pièces envoyées par ce chauffeur.
  Stream<List<DriverDocumentModel>> watchMyDocuments(String driverId) {
    return _docsRef
        .where('driverId', isEqualTo: driverId)
        .orderBy('uploadedAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => DriverDocumentModel.fromMap(doc.data())).toList());
  }
}
