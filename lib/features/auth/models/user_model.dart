class UserModel {
  final String uid;
  final String name;
  final String phoneNumber;
  final String role; // 'client', 'driver_moto' ou 'driver_taxi'
  final String country; // Ex: 'Mali', 'Côte d\'Ivoire'
  final String city; // Ex: 'Bamako', 'Abidjan'
  final String neighborhood; // Quartier de résidence, ex: 'Kabala', 'Cocody'

  // Attribut spécifique aux conducteurs
  final String? vehicleModel; // Optionnel pour le client, requis pour un chauffeur
  final double rating; // Système de notation par étoiles ⭐
  final int ratingCount; // Nombre de notes reçues (verrouillé côté règles)

  // 'pending' (chauffeur en attente de validation des pièces), 'approved'
  // (client toujours, ou chauffeur validé), 'rejected'. Ne peut être changé
  // qu'une fois créé, et seulement par une Cloud Function admin.
  final String verificationStatus;

  // Devient true uniquement après vérification SMS (Firebase Phone Auth +
  // linkWithCredential) : voir PhoneVerificationService.
  final bool phoneVerified;

  UserModel({
    required this.uid,
    required this.name,
    required this.phoneNumber,
    required this.role,
    required this.country,
    required this.city,
    required this.neighborhood,
    this.vehicleModel,
    this.rating = 5.0, // Tout le monde commence avec 5 étoiles !
    this.ratingCount = 0,
    required this.verificationStatus,
    this.phoneVerified = false,
  });

  // Convertir un document Firestore en objet de notre modèle
  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      name: map['name'] ?? '',
      phoneNumber: map['phoneNumber'] ?? '',
      role: map['role'] ?? 'client',
      country: map['country'] ?? '',
      city: map['city'] ?? '',
      neighborhood: map['neighborhood'] ?? '',
      vehicleModel: map['vehicleModel'],
      rating: (map['rating'] ?? 5.0).toDouble(),
      ratingCount: (map['ratingCount'] as num?)?.toInt() ?? 0,
      verificationStatus: map['verificationStatus'] ?? 'approved',
      phoneVerified: map['phoneVerified'] ?? false,
    );
  }

  // Convertir notre objet en Map pour l'enregistrer dans Firestore
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'phoneNumber': phoneNumber,
      'role': role,
      'country': country,
      'city': city,
      'neighborhood': neighborhood,
      'vehicleModel': vehicleModel,
      'rating': rating,
      'ratingCount': ratingCount,
      'verificationStatus': verificationStatus,
      'phoneVerified': phoneVerified,
    };
  }
}
