import 'package:flutter/material.dart';
import '../../../core/config/feature_flags.dart';
import '../../notifications/services/notification_service.dart';
import '../../places/screens/places_screen.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import 'email_verification_screen.dart';
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
  late Future<UserModel?> _profileFuture;
  bool _isSigningOut = false;
  bool _isDeletingAccount = false;

  bool get _emailVerified => _authService.currentUser?.emailVerified ?? false;

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

  Future<void> _editProfile(UserModel profile) async {
    final isDriver = profile.role == 'driver_moto' || profile.role == 'driver_taxi';
    final neighborhoodController = TextEditingController(text: profile.neighborhood);
    final vehicleController = TextEditingController(text: profile.vehicleModel ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifier mon profil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: neighborhoodController,
              decoration: const InputDecoration(labelText: 'Quartier'),
            ),
            if (isDriver) ...[
              const SizedBox(height: 12),
              TextField(
                controller: vehicleController,
                decoration: const InputDecoration(labelText: 'Modèle du véhicule'),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final neighborhood = neighborhoodController.text.trim();
    final vehicleModel = vehicleController.text.trim();

    if (neighborhood.isEmpty || (isDriver && vehicleModel.isEmpty)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ces champs ne peuvent pas être vides.')),
      );
      return;
    }

    try {
      await _authService.updateProfile(
        neighborhood: neighborhood,
        vehicleModel: isDriver ? vehicleModel : null,
      );
      if (!mounted) return;
      setState(() => _profileFuture = _loadProfile());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil mis à jour.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : ${e.toString()}')),
      );
    }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: const Text(
          'Tu ne recevras plus de notifications de course sur cet appareil '
          'tant que tu ne te reconnectes pas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );

    if (confirmed == true) await _signOut();
  }

  Future<void> _signOut() async {
    setState(() => _isSigningOut = true);
    try {
      await NotificationService().unsubscribeCurrentTopic();
      await _authService.clearFcmToken();
      await _authService.signOut();
      // AuthGate réagit automatiquement via authStateChanges() et affiche
      // l'écran de connexion ; on referme cet écran de profil s'il était
      // empilé, pour ne laisser aucun retour arrière possible dessus.
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

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer mon compte ?'),
        content: const Text(
          'Cette action est définitive : ton profil et tes pièces seront '
          'supprimés et tu ne pourras plus te connecter avec ce compte. '
          'Ton historique de courses reste visible par les autres parties.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer définitivement'),
          ),
        ],
      ),
    );

    if (confirmed == true) await _deleteAccount();
  }

  Future<void> _deleteAccount() async {
    setState(() => _isDeletingAccount = true);
    try {
      await NotificationService().unsubscribeCurrentTopic();
      await _authService.deleteAccount();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la suppression : ${e.toString()}')),
      );
      setState(() => _isDeletingAccount = false);
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
                    '⭐ ${profile.rating.toStringAsFixed(1)} '
                    '(${profile.ratingCount} avis)',
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
                    // Le bouton de vérification SMS n'apparaît que si le flux
                    // Phone Auth est activé (V2) ; en V1 phoneVerified reste
                    // un champ informatif affiché ci-dessous.
                    if (kSmsVerificationEnabled && !profile.phoneVerified)
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      _emailVerified ? Icons.verified : Icons.mail_outline,
                      color: _emailVerified
                          ? Colors.green
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _emailVerified
                            ? 'Email de secours vérifié'
                            : 'Email de secours non vérifié (facultatif)',
                      ),
                    ),
                    if (!_emailVerified)
                      TextButton(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => EmailVerificationScreen(
                                email: _authService.currentUser?.email ?? '',
                              ),
                            ),
                          );
                          if (mounted) setState(() {});
                        },
                        child: const Text('Ajouter'),
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
                if (isDriver) ...[
                  _InfoTile(
                    icon: Icons.two_wheeler_outlined,
                    label: 'Véhicule',
                    value: (profile.vehicleModel == null || profile.vehicleModel!.isEmpty)
                        ? 'Non renseigné'
                        : profile.vehicleModel!,
                  ),
                  _InfoTile(
                    icon: Icons.pin_outlined,
                    label: 'Plaque d\'immatriculation',
                    value: (profile.vehiclePlate == null || profile.vehiclePlate!.isEmpty)
                        ? 'Non renseignée'
                        : profile.vehiclePlate!,
                  ),
                ],
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _editProfile(profile),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Modifier quartier / véhicule'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 46),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                if (!isDriver) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PlacesScreen()),
                    ),
                    icon: const Icon(Icons.place_outlined),
                    label: const Text('Mes lieux'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: (_isSigningOut || _isDeletingAccount) ? null : _confirmSignOut,
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
                const SizedBox(height: 20),
                Center(
                  child: TextButton(
                    onPressed:
                        (_isSigningOut || _isDeletingAccount) ? null : _confirmDeleteAccount,
                    child: _isDeletingAccount
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            'Supprimer mon compte',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              decoration: TextDecoration.underline,
                            ),
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
