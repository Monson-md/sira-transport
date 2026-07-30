import 'package:cloud_firestore/cloud_firestore.dart';

/// Les 4 pièces attendues d'un chauffeur avant validation de son compte.
const List<String> kDriverDocumentTypes = [
  'identity',
  'license',
  'vehicle_registration',
  'vehicle_photo',
];

const Map<String, String> kDriverDocumentLabels = {
  'identity': "Pièce d'identité",
  'license': 'Permis de conduire',
  'vehicle_registration': 'Carte grise',
  'vehicle_photo': 'Photo du véhicule',
};

class DriverDocumentModel {
  final String id;
  final String driverId;
  final String type;
  final String storagePath;
  final String downloadUrl;
  final String status; // 'pending_review' | 'approved' | 'rejected'
  final DateTime? uploadedAt;

  const DriverDocumentModel({
    required this.id,
    required this.driverId,
    required this.type,
    required this.storagePath,
    required this.downloadUrl,
    required this.status,
    this.uploadedAt,
  });

  factory DriverDocumentModel.fromMap(Map<String, dynamic> map) {
    return DriverDocumentModel(
      id: map['id'] ?? '',
      driverId: map['driverId'] ?? '',
      type: map['type'] ?? '',
      storagePath: map['storagePath'] ?? '',
      downloadUrl: map['downloadUrl'] ?? '',
      status: map['status'] ?? 'pending_review',
      uploadedAt: map['uploadedAt'] is Timestamp
          ? (map['uploadedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'driverId': driverId,
      'type': type,
      'storagePath': storagePath,
      'downloadUrl': downloadUrl,
      'status': status,
      'uploadedAt': uploadedAt != null ? Timestamp.fromDate(uploadedAt!) : null,
    };
  }
}
