import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../ride/screens/client_home_screen.dart';
import '../../ride/screens/driver_dashboard_screen.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import 'email_verification_screen.dart';
import 'login_screen.dart';

/// Point d'entrée de l'application : redirige vers l'écran de connexion
/// ou vers le tableau de bord adapté au rôle de l'utilisateur connecté.
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

        if (!user.emailVerified) {
          return EmailVerificationScreen(email: user.email ?? '');
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
  late final Future<UserModel?> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _authService.getUserData(widget.uid);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserModel?>(
      future: _profileFuture,
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

        final isDriver = profile.role == 'driver_moto' || profile.role == 'driver_taxi';
        return isDriver ? const DriverDashboardScreen() : const ClientHomeScreen();
      },
    );
  }
}
