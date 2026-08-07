import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/place.dart';

/// Levée par [PlaceService.addPlace] au-delà de [PlaceService.maxPlaces].
class PlaceLimitReachedException implements Exception {
  final String message;

  const PlaceLimitReachedException([
    this.message =
        'Tu as déjà 8 lieux enregistrés, le maximum. Supprimes-en un pour en ajouter un autre.',
  ]);

  @override
  String toString() => message;
}

/// Suggestion d'enregistrer un couple quartier + repère comme lieu, après
/// que le client en soit parti au moins 3 fois. Voir
/// [PlaceService.suggestionFor].
class PlaceSuggestion {
  final String neighborhood;
  final String landmark;
  final String city;
  final String country;

  const PlaceSuggestion({
    required this.neighborhood,
    required this.landmark,
    required this.city,
    required this.country,
  });
}

class PlaceService {
  static const int maxPlaces = 8;
  static const int _suggestionThreshold = 3;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>>? _placesRef() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    return _firestore.collection('users').doc(uid).collection('places');
  }

  /// Lieux du client connecté, du plus utilisé au moins utilisé.
  Stream<List<Place>> myPlaces() {
    final ref = _placesRef();
    if (ref == null) return const Stream.empty();
    return ref.orderBy('usageCount', descending: true).snapshots().map(
          (snapshot) =>
              snapshot.docs.map((doc) => Place.fromMap(doc.id, doc.data())).toList(),
        );
  }

  Future<void> addPlace({
    required String label,
    required String icon,
    required String neighborhood,
    required String landmark,
    required String city,
    required String country,
  }) async {
    final ref = _placesRef();
    if (ref == null) return;

    // Max 8 lieux : la collection est toujours petite, un simple get()
    // suffit (pas besoin d'agrégation).
    final existing = await ref.get();
    if (existing.docs.length >= maxPlaces) {
      throw const PlaceLimitReachedException();
    }

    await ref.add({
      'label': label,
      'icon': icon,
      'neighborhood': neighborhood,
      'landmark': landmark,
      'city': city,
      'country': country,
      'usageCount': 0,
      'lastUsedAt': null,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updatePlace({
    required String placeId,
    required String label,
    required String icon,
    required String neighborhood,
    required String landmark,
  }) async {
    final ref = _placesRef();
    if (ref == null) return;
    await ref.doc(placeId).update({
      'label': label,
      'icon': icon,
      'neighborhood': neighborhood,
      'landmark': landmark,
    });
  }

  Future<void> deletePlace(String placeId) async {
    final ref = _placesRef();
    if (ref == null) return;
    await ref.doc(placeId).delete();
  }

  /// Incrémente l'usage d'un lieu au moment où il remplit un champ de
  /// course — toujours via FieldValue.increment, jamais lecture puis
  /// écriture (deux appuis rapprochés ne doivent pas s'écraser l'un
  /// l'autre).
  Future<void> markUsed(String placeId) async {
    final ref = _placesRef();
    if (ref == null) return;
    await ref.doc(placeId).update({
      'usageCount': FieldValue.increment(1),
      'lastUsedAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------------- Proposition automatique ----------------

  /// Id déterministe (donc lisible sans requête) pour un couple quartier +
  /// repère, utilisé à la fois pour vérifier et pour enregistrer un refus
  /// dans users/{uid}/dismissedSuggestions.
  String _suggestionId(String neighborhood, String landmark) {
    String slug(String v) => v.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return '${slug(neighborhood)}__${slug(landmark)}';
  }

  /// À appeler à la fin d'une course. Retourne une suggestion si :
  /// - le client est parti de ce couple quartier + repère au moins 3 fois,
  /// - ce couple n'est pas déjà un lieu enregistré,
  /// - le client n'a pas déjà refusé cette suggestion.
  /// Ne propose donc jamais deux fois la même chose (harcèlement interdit
  /// par la consigne).
  Future<PlaceSuggestion?> suggestionFor({
    required String neighborhood,
    required String landmark,
    required String city,
    required String country,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;

    final placesRef = _placesRef();
    if (placesRef != null) {
      final places = await placesRef.get();
      final alreadySaved = places.docs.any((doc) =>
          doc.data()['neighborhood'] == neighborhood && doc.data()['landmark'] == landmark);
      if (alreadySaved) return null;
    }

    final suggestionId = _suggestionId(neighborhood, landmark);
    final dismissed = await _firestore
        .collection('users')
        .doc(uid)
        .collection('dismissedSuggestions')
        .doc(suggestionId)
        .get();
    if (dismissed.exists) return null;

    final countSnapshot = await _firestore
        .collection('rides')
        .where('clientId', isEqualTo: uid)
        .where('departureNeighborhood', isEqualTo: neighborhood)
        .where('departureLandmark', isEqualTo: landmark)
        .count()
        .get();
    if ((countSnapshot.count ?? 0) < _suggestionThreshold) return null;

    return PlaceSuggestion(
      neighborhood: neighborhood,
      landmark: landmark,
      city: city,
      country: country,
    );
  }

  /// Le client refuse la suggestion : on ne la reproposera plus jamais
  /// pour ce couple précis.
  Future<void> dismissSuggestion(String neighborhood, String landmark) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('dismissedSuggestions')
        .doc(_suggestionId(neighborhood, landmark))
        .set({
      'neighborhood': neighborhood,
      'landmark': landmark,
      'dismissedAt': FieldValue.serverTimestamp(),
    });
  }
}
