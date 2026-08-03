import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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
    // Un chauffeur démarre 'pending' (pièces à valider) ; un client
    // n'a pas de vérification à faire, donc 'approved' d'emblée. Ce champ
    // est ensuite verrouillé par firestore.rules : seule une Cloud
    // Function admin peut le faire passer à 'approved'/'rejected'.
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
      verificationStatus: isDriver ? 'pending' : 'approved',
    );

    // 3. Enregistrement instantané dans la collection "users" de Firestore
    await _firestore.collection('users').doc(uid).set(newUser.toMap());

    // 4. Email de vérification, envoyé immédiatement pour que l'écran de
    // blocage (AuthGate) ait tout de suite quelque chose à faire vérifier.
    await userCredential.user!.sendEmailVerification();

    return userCredential;
  }

  // ---------------- Vérification de l'email ----------------

  Future<void> sendEmailVerification() async {
    await _auth.currentUser?.sendEmailVerification();
  }

  /// Recharge l'utilisateur Firebase Auth et renvoie son état de
  /// vérification à jour (emailVerified est mis en cache localement par
  /// le SDK, il faut un reload() pour voir un changement fait ailleurs).
  Future<bool> reloadAndCheckEmailVerified() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  // ---------------- Vérification du numéro par SMS ----------------

  /// Démarre la vérification Firebase Phone Auth. `onCodeSent` reçoit le
  /// verificationId à renvoyer ensuite à [confirmPhoneVerification].
  Future<void> startPhoneVerification({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(FirebaseAuthException e) onFailed,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      // La détection auto-SMS Android n'est pas utilisée : on garde une
      // saisie manuelle du code pour un comportement identique sur toutes
      // les plateformes.
      verificationCompleted: (_) {},
      verificationFailed: onFailed,
      codeSent: (verificationId, _) => onCodeSent(verificationId),
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  /// Rattache le numéro vérifié par SMS au compte existant (linkWithCredential),
  /// puis marque phoneVerified = true dans Firestore. L'écriture n'est
  /// acceptée par firestore.rules que parce que le token d'auth — rafraîchi
  /// ici — prouve désormais ce numéro (request.auth.token.phone_number).
  Future<void> confirmPhoneVerification({
    required String verificationId,
    required String smsCode,
    required String phoneNumber,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Aucun utilisateur connecté.');

    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    await user.linkWithCredential(credential);
    await user.getIdToken(true);

    await _firestore.collection('users').doc(user.uid).update({
      'phoneNumber': phoneNumber,
      'phoneVerified': true,
    });
  }

  // Connexion de l'utilisateur
  Future<UserCredential> signInWithEmail(String email, String password) async {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  // Déconnexion
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // ---------------- Profil ----------------

  /// Modifie le quartier (et, pour un chauffeur, le modèle de véhicule) du
  /// profil connecté. Jamais le rôle : firestore.rules l'interdit de toute
  /// façon (request.resource.data.role == resource.data.role).
  Future<void> updateProfile({
    required String neighborhood,
    String? vehicleModel,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final data = <String, dynamic>{'neighborhood': neighborhood};
    if (vehicleModel != null) data['vehicleModel'] = vehicleModel;

    await _firestore.collection('users').doc(uid).update(data);
  }

  /// Supprime définitivement le compte connecté (profil Firestore, pièces
  /// chauffeur et compte Firebase Auth). Passe par une Cloud Function
  /// (Admin SDK) plutôt que par un `delete` client : firestore.rules
  /// n'autorise aucune suppression depuis l'app, et la suppression du
  /// compte Auth lui-même n'est de toute façon accessible qu'au SDK admin.
  Future<void> deleteAccount() async {
    await FirebaseFunctions.instance.httpsCallable('deleteMyAccount').call();
    // Le compte Auth est déjà supprimé côté serveur ; on force l'état
    // local à jour immédiatement plutôt que d'attendre l'expiration du
    // token, pour qu'AuthGate redirige tout de suite vers la connexion.
    await _auth.signOut();
  }

  // ---------------- Notifications push ----------------

  /// Enregistre le token FCM de l'appareil sur le profil de l'utilisateur
  /// connecté. Appelé par NotificationService à la connexion et à chaque
  /// rafraîchissement de token (onTokenRefresh).
  Future<void> updateFcmToken(String token) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _firestore.collection('users').doc(uid).update({'fcmToken': token});
  }

  /// Efface le token FCM du profil, pour ne plus recevoir de notifications
  /// sur cet appareil après déconnexion.
  Future<void> clearFcmToken() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _firestore.collection('users').doc(uid).update({'fcmToken': null});
  }

  // Récupérer les données Firestore de l'utilisateur connecté
  Future<UserModel?> getUserData(String uid) async {
    final DocumentSnapshot doc =
        await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return UserModel.fromMap(doc.data() as Map<String, dynamic>);
  }
}
