import 'package:flutter/material.dart';
import '../../auth/models/user_model.dart';
import '../../auth/services/auth_service.dart';
import '../../auth/screens/profile_screen.dart';
import '../models/ride_model.dart';
import '../services/ride_service.dart';
import 'create_ride_screen.dart';
import 'ride_tracking_screen.dart';

class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  final _authService = AuthService();
  final _rideService = RideService();
  late final Future<UserModel?> _profileFuture;

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

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
  }

  void _openCreateRide() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreateRideScreen()),
    );
  }

  void _openTracking(String rideId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RideTrackingScreen(rideId: rideId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sira-Transport'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: _openProfile,
          ),
        ],
      ),
      body: FutureBuilder<UserModel?>(
        future: _profileFuture,
        builder: (context, profileSnapshot) {
          if (profileSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final profile = profileSnapshot.data;
          if (profile == null) {
            return const Center(
              child: Text('Impossible de charger votre profil.'),
            );
          }

          return StreamBuilder<List<RideModel>>(
            stream: _rideService.myRidesStream(profile.uid, 'client'),
            builder: (context, rideSnapshot) {
              final activeRide = (rideSnapshot.data ?? [])
                  .where((r) => r.status == 'pending' || r.status == 'accepted')
                  .firstOrNull;

              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Bonjour, ${profile.name} 👋',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 24),
                      if (activeRide != null)
                        _ActiveRideCard(
                          ride: activeRide,
                          onTap: () => _openTracking(activeRide.id),
                        )
                      else
                        Expanded(
                          child: Center(
                            child: Text(
                              'Vous n\'avez aucune course en cours.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                      if (activeRide == null)
                        FilledButton.icon(
                          onPressed: _openCreateRide,
                          icon: const Icon(Icons.add),
                          label: const Text('Publier une course'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(double.infinity, 52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _ActiveRideCard extends StatelessWidget {
  final RideModel ride;
  final VoidCallback onTap;

  const _ActiveRideCard({required this.ride, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAccepted = ride.status == 'accepted';

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isAccepted ? Icons.check_circle : Icons.hourglass_top,
                    color: isAccepted ? Colors.green : colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isAccepted
                          ? 'Un chauffeur a accepté votre course !'
                          : 'En attente d\'un chauffeur...',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 16),
              Text('${ride.departureNeighborhood} → ${ride.arrivalNeighborhood}'),
              const SizedBox(height: 4),
              Text(
                '${ride.offeredPrice} FCFA',
                style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.primary),
              ),
              const SizedBox(height: 4),
              Text(
                'Touchez pour suivre la course',
                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
