import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/config/feature_flags.dart';
import '../../notifications/services/notification_service.dart';
import '../../ride/screens/client_home_screen.dart';
import '../../ride/screens/driver_dashboard_screen.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'phone_verification_gate_screen.dart';

/// Point d'entrée de l'application : redirige vers l'écran de connexion
/// ou vers le tableau de bord adapté au rôle de l'utilisateur connecté.
///
/// Le passage obligatoire est le numéro WhatsApp vérifié par SMS
/// (phoneVerified, voir _RoleBasedHomeState), pas l'email : pour ce
/// public, un email de vérification en anglais qui finit en spam bloque
/// plus qu'il ne protège. L'email reste vérifiable, mais en option depuis
/// le profil (voir EmailVerificationScreen et ProfileScreen).
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return const LoginScreen();
        }

        return _RoleBasedHome(uid: user.uid);
      },
    );
  }
}

class _RoleBasedHome extends StatefulWidget {
  final String uid;

  const _RoleBasedHome({required this.uid});

  @override
  State<_RoleBasedHome> createState() => _RoleBasedHomeState();
}

class _RoleBasedHomeState extends State<_RoleBasedHome> {
  final _authService = AuthService();

  // NotificationService ne doit être (ré)enregistré qu'une fois par
  // connexion, pas à chaque émission du stream (ex: mise à jour du profil
  // ailleurs, comme une approbation chauffeur).
  bool _registered = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserModel?>(
      // currentUserStream combine authStateChanges() et le document
      // Firestore : un changement de verificationStatus (approbation d'un
      // chauffeur) met donc à jour ce tableau de bord en temps réel, sans
      // reconnexion.
      stream: _authService.currentUserStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final profile = snapshot.data;
        if (profile == null) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Impossible de charger votre profil.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => _authService.signOut(),
                      child: const Text('Se déconnecter'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // Numéro WhatsApp vérifié par SMS = passage obligatoire uniquement
        // quand kSmsVerificationEnabled est actif. En V1 (flag à false), le
        // SMS est désactivé (Firebase Blaze indisponible), phoneVerified reste
        // informatif et n'empêche plus l'accès au tableau de bord. En V2, dès
        // que phoneVerified passe à true (PhoneVerificationGateScreen écrit
        // dans Firestore), ce flux réémet et bascule automatiquement sur le
        // tableau de bord, sans navigation explicite à gérer.
        if (kSmsVerificationEnabled && !profile.phoneVerified) {
          return PhoneVerificationGateScreen(phoneNumber: profile.phoneNumber);
        }

        if (!_registered) {
          _registered = true;
          NotificationService().registerForCurrentUser(profile);
        }

        final isDriver = profile.role == 'driver_moto' || profile.role == 'driver_taxi';
        return isDriver ? const DriverDashboardScreen() : const ClientHomeScreen();
      },
    );
  }
}
