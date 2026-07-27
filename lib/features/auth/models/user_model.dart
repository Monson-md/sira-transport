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
    };
  }
}
