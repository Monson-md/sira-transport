import 'package:flutter/material.dart';
import '../../auth/models/user_model.dart';
import '../../auth/services/auth_service.dart';
import '../../auth/screens/profile_screen.dart';
import '../models/ride_model.dart';
import '../services/ride_service.dart';

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  final _authService = AuthService();
  final _rideService = RideService();

  late final Future<UserModel?> _profileFuture;

  /// Ids des courses en cours d'acceptation ou de finalisation, pour désactiver leur bouton.
  final Set<String> _pendingActionRideIds = {};

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

  Future<void> _acceptRide(RideModel ride, String driverId) async {
    setState(() => _pendingActionRideIds.add(ride.id));
    try {
      await _rideService.acceptRide(ride.id, driverId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Course acceptée : ${ride.arrivalNeighborhood}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _pendingActionRideIds.remove(ride.id));
    }
  }

  Future<void> _completeRide(RideModel ride) async {
    setState(() => _pendingActionRideIds.add(ride.id));
    try {
      await _rideService.completeRide(ride.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Course marquée comme terminée !')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _pendingActionRideIds.remove(ride.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Courses disponibles'),
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

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              StreamBuilder<List<RideModel>>(
                stream: _rideService.getAcceptedRidesForDriver(profile.uid),
                builder: (context, snapshot) {
                  final acceptedRides = snapshot.data ?? [];
                  if (acceptedRides.isEmpty) return const SizedBox.shrink();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Ma course en cours',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      ...acceptedRides.map(
                        (ride) => _RideCard(
                          ride: ride,
                          actionLabel: 'Terminer la course',
                          isActionLoading: _pendingActionRideIds.contains(ride.id),
                          onAction: () => _completeRide(ride),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  );
                },
              ),
              const Text(
                'Courses disponibles',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              StreamBuilder<List<RideModel>>(
                stream: _rideService.getAvailableRidesStream(profile.country, profile.city),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('Erreur de chargement des courses.')),
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final rides = snapshot.data ?? [];
                  if (rides.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'Aucune course en attente pour le moment à ${profile.city}.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    );
                  }

                  return Column(
                    children: rides
                        .map(
                          (ride) => _RideCard(
                            ride: ride,
                            actionLabel: 'Accepter la course',
                            isActionLoading: _pendingActionRideIds.contains(ride.id),
                            onAction: () => _acceptRide(ride, profile.uid),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RideCard extends StatelessWidget {
  final RideModel ride;
  final String actionLabel;
  final bool isActionLoading;
  final VoidCallback onAction;

  const _RideCard({
    required this.ride,
    required this.actionLabel,
    required this.isActionLoading,
    required this.onAction,
  });

  String get _formattedPrice {
    final digits = ride.offeredPrice.toInt().toString();
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      final positionFromEnd = digits.length - i;
      buffer.write(digits[i]);
      if (positionFromEnd > 1 && positionFromEnd % 3 == 1) {
        buffer.write(' ');
      }
    }
    return '$buffer FCFA';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isColis = ride.type == 'colis';

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: colorScheme.primaryContainer,
                  child: Text(isColis ? '📦' : '👥', style: const TextStyle(fontSize: 18)),
                ),
                const SizedBox(width: 10),
                Text(
                  isColis ? 'Colis' : 'Passager',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                Text(
                  _formattedPrice,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _LocationRow(
              icon: Icons.my_location_outlined,
              iconColor: colorScheme.primary,
              neighborhood: ride.departureNeighborhood,
              landmark: ride.departureLandmark,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4, horizontal: 10),
              child: SizedBox(
                height: 16,
                child: VerticalDivider(width: 1),
              ),
            ),
            _LocationRow(
              icon: Icons.flag_outlined,
              iconColor: colorScheme.tertiary,
              neighborhood: ride.arrivalNeighborhood,
              landmark: ride.arrivalLandmark,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: isActionLoading ? null : onAction,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: isActionLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String neighborhood;
  final String landmark;

  const _LocationRow({
    required this.icon,
    required this.iconColor,
    required this.neighborhood,
    required this.landmark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(neighborhood, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                landmark,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
