import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/models/user_model.dart';
import '../models/ride_model.dart';

/// Levée par [RideService.acceptRide] quand un autre chauffeur a déjà
/// accepté la course entre la lecture de la liste et l'appui sur le bouton.
class RideAlreadyTakenException implements Exception {
  final String message;

  const RideAlreadyTakenException([
    this.message = 'Cette course a déjà été acceptée par un autre chauffeur.',
  ]);

  @override
  String toString() => message;
}

class RideService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _ridesRef =>
      _firestore.collection('rides');

  /// Publie une nouvelle demande de course avec le statut 'pending'.
  /// createdAt est fixé côté serveur via FieldValue.serverTimestamp().
  Future<String> createRideRequest(RideModel ride) async {
    final docRef = _ridesRef.doc();
    final data = ride.toMap()
      ..['id'] = docRef.id
      ..['status'] = 'pending'
      ..['driverId'] = null
      ..['driverName'] = null
      ..['driverPhone'] = null
      ..['createdAt'] = FieldValue.serverTimestamp()
      ..['acceptedAt'] = null
      ..['completedAt'] = null
      ..['cancelledAt'] = null;

    await docRef.set(data);
    return docRef.id;
  }

  /// Flux temps réel des courses en attente pour un pays/ville donnés,
  /// destiné aux chauffeurs. Nécessite l'index composite décrit dans
  /// firestore.indexes.json (status + country + city + createdAt desc).
  ///
  /// Le filtrage par [vehicleType] (véhicule souhaité par le client, une
  /// course 'any' convenant à tout chauffeur) se fait côté client sur les
  /// 50 documents déjà remontés, pour ne pas exiger un second index
  /// composite ni changer la forme de la requête envoyée à Firestore.
  Stream<List<RideModel>> getAvailableRidesStream(
    String country,
    String city,
    String vehicleType,
  ) {
    return _ridesRef
        .where('status', isEqualTo: 'pending')
        .where('country', isEqualTo: country)
        .where('city', isEqualTo: city)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => RideModel.fromMap(doc.data()))
          .where((ride) => ride.vehicleType == vehicleType || ride.vehicleType == 'any')
          .toList();
    });
  }

  /// Un chauffeur accepte une course. Toujours en transaction : on relit le
  /// document, et on n'accepte que si status == 'pending' et driverId ==
  /// null, sinon un autre chauffeur est déjà passé avant nous.
  Future<void> acceptRide(String rideId, UserModel driver) async {
    final docRef = _ridesRef.doc(rideId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final data = snapshot.data();

      if (!snapshot.exists || data == null) {
        throw const RideAlreadyTakenException('Cette course n\'existe plus.');
      }

      final status = data['status'] as String?;
      final driverId = data['driverId'] as String?;
      if (status != 'pending' || driverId != null) {
        throw const RideAlreadyTakenException();
      }

      transaction.update(docRef, {
        'status': 'accepted',
        'driverId': driver.uid,
        'driverName': driver.name,
        'driverPhone': driver.phoneNumber,
        'acceptedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Le chauffeur marque la course comme terminée.
  Future<void> completeRide(String rideId) async {
    await _ridesRef.doc(rideId).update({
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Le client annule sa course tant qu'aucun chauffeur ne l'a acceptée.
  Future<void> cancelRide(String rideId) async {
    await _ridesRef.doc(rideId).update({
      'status': 'cancelled',
      'cancelledAt': FieldValue.serverTimestamp(),
    });
  }

  /// Suivi temps réel d'une course précise, côté client.
  Stream<RideModel> watchRide(String rideId) {
    return _ridesRef.doc(rideId).snapshots().map(
          (snapshot) => RideModel.fromMap(snapshot.data() ?? {}),
        );
  }

  /// Historique/courses d'un utilisateur : 'client' filtre sur clientId,
  /// tout autre rôle (chauffeur) filtre sur driverId. Nécessite l'index
  /// composite correspondant décrit dans firestore.indexes.json.
  Stream<List<RideModel>> myRidesStream(String userId, String role) {
    final field = role == 'client' ? 'clientId' : 'driverId';
    return _ridesRef
        .where(field, isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => RideModel.fromMap(doc.data())).toList());
  }
}
