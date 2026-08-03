import 'package:flutter/material.dart';
import '../../notifications/services/notification_service.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import 'phone_verification_screen.dart';

const Map<String, String> _kRoleLabels = {
  'client': 'Client (Vendeur / Passager)',
  'driver_moto': 'Conducteur Moto-Taxi',
  'driver_taxi': 'Conducteur Taxi Voiture',
};

const Map<String, String> _kVerificationLabels = {
  'pending': 'En attente de validation',
  'approved': 'Compte vérifié',
  'rejected': 'Vérification refusée',
};

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _authService = AuthService();
  late final Future<UserModel?> _profileFuture;
  bool _isSigningOut = false;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
  }

  Future<UserModel?> _loadProfile() async {
    final uid = _authService.currentUser?.uid;
    if (uid == null) return null;
    return _authService.getUserData(uid);
  }

  Future<void> _signOut() async {
    setState(() => _isSigningOut = true);
    try {
      await NotificationService().unsubscribeCurrentTopic();
      await _authService.signOut();
      // AuthGate réagit automatiquement via authStateChanges() et affiche
      // l'écran de connexion ; on referme cet écran de profil s'il était empilé.
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la déconnexion : ${e.toString()}')),
      );
      setState(() => _isSigningOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil')),
      body: FutureBuilder<UserModel?>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final profile = snapshot.data;
          if (profile == null) {
            return const Center(
              child: Text('Impossible de charger votre profil.'),
            );
          }

          final isDriver =
              profile.role == 'driver_moto' || profile.role == 'driver_taxi';

          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    profile.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                Center(
                  child: Text(
                    '⭐ ${profile.rating.toStringAsFixed(1)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                const SizedBox(height: 20),
                if (isDriver)
                  Center(
                    child: Chip(
                      label: Text(_kVerificationLabels[profile.verificationStatus] ??
                          profile.verificationStatus),
                      backgroundColor: profile.verificationStatus == 'approved'
                          ? Colors.green.withValues(alpha: 0.15)
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      profile.phoneVerified ? Icons.verified : Icons.error_outline,
                      color: profile.phoneVerified
                          ? Colors.green
                          : Theme.of(context).colorScheme.error,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        profile.phoneVerified
                            ? 'Numéro WhatsApp vérifié'
                            : 'Numéro WhatsApp non vérifié',
                      ),
                    ),
                    if (!profile.phoneVerified)
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PhoneVerificationScreen(
                                initialPhoneNumber: profile.phoneNumber,
                              ),
                            ),
                          );
                        },
                        child: const Text('Vérifier'),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _InfoTile(
                  icon: Icons.badge_outlined,
                  label: 'Rôle',
                  value: _kRoleLabels[profile.role] ?? profile.role,
                ),
                _InfoTile(
                  icon: Icons.phone_outlined,
                  label: 'Numéro WhatsApp',
                  value: profile.phoneNumber,
                ),
                _InfoTile(
                  icon: Icons.public_outlined,
                  label: 'Pays',
                  value: profile.country,
                ),
                _InfoTile(
                  icon: Icons.location_city_outlined,
                  label: 'Ville',
                  value: profile.city,
                ),
                _InfoTile(
                  icon: Icons.map_outlined,
                  label: 'Quartier',
                  value: profile.neighborhood,
                ),
                if (isDriver)
                  _InfoTile(
                    icon: Icons.two_wheeler_outlined,
                    label: 'Véhicule',
                    value: (profile.vehicleModel == null || profile.vehicleModel!.isEmpty)
                        ? 'Non renseigné'
                        : profile.vehicleModel!,
                  ),
                const SizedBox(height: 32),
                OutlinedButton.icon(
                  onPressed: _isSigningOut ? null : _signOut,
                  icon: _isSigningOut
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.logout),
                  label: const Text('Se déconnecter'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    side: BorderSide(color: Theme.of(context).colorScheme.error),
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
