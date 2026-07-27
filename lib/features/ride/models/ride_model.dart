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
  final double offeredPrice; // Prix proposé en FCFA
  final String status; // 'pending', 'accepted', 'completed', 'cancelled'
  final String? driverId; // Renseigné quand un chauffeur accepte la course
  final String country;
  final String city;
  final DateTime createdAt;

  RideModel({
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
    required this.country,
    required this.city,
    required this.createdAt,
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
      offeredPrice: (map['offeredPrice'] ?? 0).toDouble(),
      status: map['status'] ?? 'pending',
      driverId: map['driverId'],
      country: map['country'] ?? '',
      city: map['city'] ?? '',
      createdAt: map['createdAt'] is Timestamp
          ? (map['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  // Convertir notre objet en Map pour l'enregistrer dans Firestore
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
      'country': country,
      'city': city,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
