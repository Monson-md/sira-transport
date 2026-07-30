import 'package:cloud_firestore/cloud_firestore.dart';

class RideModel {
  final String id;
  final String clientId;
  final String clientName;
  final String clientPhone;
  final String type; // 'colis' ou 'passager'
  final String departureNeighborhood;
  final String departureLandmark;
  final String arrivalNeighborhood;
  final String arrivalLandmark;
  final int offeredPrice; // Prix proposé en FCFA (toujours un entier)
  final String status; // 'pending', 'accepted', 'completed', 'cancelled'
  final String? driverId;
  final String? driverName;
  final String? driverPhone;
  final String vehicleType; // 'moto', 'taxi' ou 'any' (souhait du client)
  final String country;
  final String city;
  final int platformFee; // Commission plateforme en FCFA — 0 tant que la V2 payante n'existe pas
  final DateTime? createdAt;
  final DateTime? acceptedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;

  const RideModel({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.clientPhone,
    required this.type,
    required this.departureNeighborhood,
    required this.departureLandmark,
    required this.arrivalNeighborhood,
    required this.arrivalLandmark,
    required this.offeredPrice,
    this.status = 'pending',
    this.driverId,
    this.driverName,
    this.driverPhone,
    required this.vehicleType,
    required this.country,
    required this.city,
    this.platformFee = 0,
    this.createdAt,
    this.acceptedAt,
    this.completedAt,
    this.cancelledAt,
  });

  // Convertir un document Firestore en objet de notre modèle
  factory RideModel.fromMap(Map<String, dynamic> map) {
    return RideModel(
      id: map['id'] ?? '',
      clientId: map['clientId'] ?? '',
      clientName: map['clientName'] ?? '',
      clientPhone: map['clientPhone'] ?? '',
      type: map['type'] ?? 'passager',
      departureNeighborhood: map['departureNeighborhood'] ?? '',
      departureLandmark: map['departureLandmark'] ?? '',
      arrivalNeighborhood: map['arrivalNeighborhood'] ?? '',
      arrivalLandmark: map['arrivalLandmark'] ?? '',
      offeredPrice: (map['offeredPrice'] as num?)?.toInt() ?? 0,
      status: map['status'] ?? 'pending',
      driverId: map['driverId'],
      driverName: map['driverName'],
      driverPhone: map['driverPhone'],
      vehicleType: map['vehicleType'] ?? 'any',
      country: map['country'] ?? '',
      city: map['city'] ?? '',
      platformFee: (map['platformFee'] as num?)?.toInt() ?? 0,
      createdAt: _timestampToDate(map['createdAt']),
      acceptedAt: _timestampToDate(map['acceptedAt']),
      completedAt: _timestampToDate(map['completedAt']),
      cancelledAt: _timestampToDate(map['cancelledAt']),
    );
  }

  static DateTime? _timestampToDate(dynamic value) {
    return value is Timestamp ? value.toDate() : null;
  }

  // Convertir notre objet en Map pour l'enregistrer dans Firestore.
  // Les champs de date sont sérialisés tels quels : c'est au service d'y
  // substituer FieldValue.serverTimestamp() au moment de l'écriture.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'clientId': clientId,
      'clientName': clientName,
      'clientPhone': clientPhone,
      'type': type,
      'departureNeighborhood': departureNeighborhood,
      'departureLandmark': departureLandmark,
      'arrivalNeighborhood': arrivalNeighborhood,
      'arrivalLandmark': arrivalLandmark,
      'offeredPrice': offeredPrice,
      'status': status,
      'driverId': driverId,
      'driverName': driverName,
      'driverPhone': driverPhone,
      'vehicleType': vehicleType,
      'country': country,
      'city': city,
      'platformFee': platformFee,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'acceptedAt': acceptedAt != null ? Timestamp.fromDate(acceptedAt!) : null,
      'completedAt': completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      'cancelledAt': cancelledAt != null ? Timestamp.fromDate(cancelledAt!) : null,
    };
  }
}
