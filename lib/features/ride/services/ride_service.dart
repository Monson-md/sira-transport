import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/ride_model.dart';

class RideService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _ridesRef =>
      _firestore.collection('rides');

  /// Publie une nouvelle demande de course avec le statut 'pending'.
  Future<String> createRideRequest(RideModel ride) async {
    final docRef = _ridesRef.doc();
    final data = ride.toMap();
    data['id'] = docRef.id;
    await docRef.set(data);
    return docRef.id;
  }

  /// Flux temps réel des courses en attente pour un pays et une ville donnés,
  /// destiné aux chauffeurs.
  Stream<List<RideModel>> getAvailableRidesStream(String country, String city) {
    return _ridesRef
        .where('country', isEqualTo: country)
        .where('city', isEqualTo: city)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
      final rides =
          snapshot.docs.map((doc) => RideModel.fromMap(doc.data())).toList();
      // Tri côté client pour éviter de dépendre d'un index composite.
      rides.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return rides;
    });
  }

  /// Un chauffeur accepte une course : statut -> 'accepted' + driverId attaché.
  Future<void> acceptRide(String rideId, String driverId) async {
    await _ridesRef.doc(rideId).update({
      'status': 'accepted',
      'driverId': driverId,
    });
  }

  /// Le chauffeur marque la course comme terminée.
  Future<void> completeRide(String rideId) async {
    await _ridesRef.doc(rideId).update({'status': 'completed'});
  }

  /// Flux temps réel des courses acceptées par un chauffeur donné,
  /// pour lui permettre de les marquer comme terminées.
  Stream<List<RideModel>> getAcceptedRidesForDriver(String driverId) {
    return _ridesRef
        .where('driverId', isEqualTo: driverId)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .map((snapshot) {
      final rides =
          snapshot.docs.map((doc) => RideModel.fromMap(doc.data())).toList();
      rides.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return rides;
    });
  }

  /// Flux temps réel de la course active (en attente ou acceptée) d'un client,
  /// pour lui permettre de suivre son statut en direct.
  Stream<RideModel?> getActiveRideStream(String clientId) {
    return _ridesRef.where('clientId', isEqualTo: clientId).snapshots().map((snapshot) {
      final rides = snapshot.docs
          .map((doc) => RideModel.fromMap(doc.data()))
          .where((ride) => ride.status == 'pending' || ride.status == 'accepted')
          .toList();
      rides.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return rides.isEmpty ? null : rides.first;
    });
  }
}
