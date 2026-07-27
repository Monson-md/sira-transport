import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Obtenir l'utilisateur actuellement connecté
  User? get currentUser => _auth.currentUser;

  // Inscription : création du compte Firebase Auth + enregistrement Firestore
  Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
    required String name,
    required String phoneNumber,
    required String role,
    required String country,
    required String city,
    required String neighborhood,
    String? vehicleModel,
  }) async {
    // 1. Création de l'utilisateur dans Firebase Auth
    final UserCredential userCredential =
        await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final String uid = userCredential.user!.uid;
    final bool isDriver = role == 'driver_moto' || role == 'driver_taxi';

    // 2. Création de l'objet UserModel
    final UserModel newUser = UserModel(
      uid: uid,
      name: name,
      phoneNumber: phoneNumber,
      role: role,
      country: country,
      city: city,
      neighborhood: neighborhood,
      vehicleModel: isDriver ? vehicleModel : null,
      rating: 5.0, // Initialisation à 5 étoiles
    );

    // 3. Enregistrement instantané dans la collection "users" de Firestore
    await _firestore.collection('users').doc(uid).set(newUser.toMap());

    return userCredential;
  }

  // Connexion de l'utilisateur
  Future<UserCredential> signInWithEmail(String email, String password) async {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  // Déconnexion
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // Récupérer les données Firestore de l'utilisateur connecté
  Future<UserModel?> getUserData(String uid) async {
    final DocumentSnapshot doc =
        await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return UserModel.fromMap(doc.data() as Map<String, dynamic>);
  }
}
