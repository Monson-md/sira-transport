import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Icônes proposées pour un lieu favori (users/{uid}/places/{placeId}).
const List<String> kPlaceIcons = ['home', 'work', 'market', 'school', 'other'];

const Map<String, String> kPlaceIconLabels = {
  'home': 'Maison',
  'work': 'Travail',
  'market': 'Marché',
  'school': 'École',
  'other': 'Autre',
};

/// Icône Material correspondant à un [Place.icon]. 'other' et toute valeur
/// inconnue (données créées par une version future de l'app) retombent sur
/// une icône générique plutôt que de planter.
IconData placeIconData(String icon) {
  switch (icon) {
    case 'home':
      return Icons.home_outlined;
    case 'work':
      return Icons.work_outline;
    case 'market':
      return Icons.storefront_outlined;
    case 'school':
      return Icons.school_outlined;
    default:
      return Icons.place_outlined;
  }
}

/// Lieu habituel enregistré par un client (users/{uid}/places/{placeId}),
/// pour remplir départ/arrivée d'une course sans retaper quartier + repère.
class Place {
  final String id;
  final String label;
  final String icon; // 'home' | 'work' | 'market' | 'school' | 'other'
  final String neighborhood;
  final String landmark;
  final String city;
  final String country;
  final int usageCount;
  final DateTime? lastUsedAt;
  final DateTime? createdAt;

  const Place({
    required this.id,
    required this.label,
    required this.icon,
    required this.neighborhood,
    required this.landmark,
    required this.city,
    required this.country,
    this.usageCount = 0,
    this.lastUsedAt,
    this.createdAt,
  });

  factory Place.fromMap(String id, Map<String, dynamic> map) {
    return Place(
      id: id,
      label: map['label'] ?? '',
      icon: map['icon'] ?? 'other',
      neighborhood: map['neighborhood'] ?? '',
      landmark: map['landmark'] ?? '',
      city: map['city'] ?? '',
      country: map['country'] ?? '',
      usageCount: (map['usageCount'] as num?)?.toInt() ?? 0,
      lastUsedAt: map['lastUsedAt'] is Timestamp
          ? (map['lastUsedAt'] as Timestamp).toDate()
          : null,
      createdAt: map['createdAt'] is Timestamp
          ? (map['createdAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'label': label,
      'icon': icon,
      'neighborhood': neighborhood,
      'landmark': landmark,
      'city': city,
      'country': country,
      'usageCount': usageCount,
      'lastUsedAt': lastUsedAt != null ? Timestamp.fromDate(lastUsedAt!) : null,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
    };
  }
}
