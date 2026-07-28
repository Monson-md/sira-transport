import 'package:flutter/material.dart';
import '../../auth/models/user_model.dart';
import '../../auth/services/auth_service.dart';
import '../../auth/screens/profile_screen.dart';
import '../models/ride_model.dart';
import '../services/ride_service.dart';
import 'create_ride_screen.dart';

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

          return StreamBuilder<RideModel?>(
            stream: _rideService.getActiveRideStream(profile.uid),
            builder: (context, rideSnapshot) {
              final activeRide = rideSnapshot.data;

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
                        _ActiveRideCard(ride: activeRide)
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

class _ActiveRideCard extends StatelessWidget {
  final RideModel ride;

  const _ActiveRideCard({required this.ride});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAccepted = ride.status == 'accepted';

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
              ],
            ),
            const SizedBox(height: 16),
            Text('${ride.departureNeighborhood} → ${ride.arrivalNeighborhood}'),
            const SizedBox(height: 4),
            Text(
              '${ride.offeredPrice.toInt()} FCFA',
              style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.primary),
            ),
            if (isAccepted && ride.driverId != null) ...[
              const SizedBox(height: 16),
              _DriverContact(driverId: ride.driverId!),
            ],
          ],
        ),
      ),
    );
  }
}

class _DriverContact extends StatelessWidget {
  final String driverId;

  const _DriverContact({required this.driverId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserModel?>(
      future: AuthService().getUserData(driverId),
      builder: (context, snapshot) {
        final driver = snapshot.data;
        if (driver == null) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.two_wheeler_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(driver.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(driver.phoneNumber),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
