import 'package:flutter/material.dart';
import '../../auth/models/user_model.dart';
import '../../auth/services/auth_service.dart';
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

  /// Ids des courses en cours d'acceptation, pour désactiver leur bouton.
  final Set<String> _acceptingRideIds = {};

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

  Future<void> _acceptRide(RideModel ride, String driverId) async {
    setState(() => _acceptingRideIds.add(ride.id));
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
      if (mounted) setState(() => _acceptingRideIds.remove(ride.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Courses disponibles')),
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
            stream: _rideService.getAvailableRidesStream(profile.country, profile.city),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text('Erreur de chargement des courses.'),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final rides = snapshot.data ?? [];
              if (rides.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Aucune course en attente pour le moment à ${profile.city}.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: rides.length,
                itemBuilder: (context, index) {
                  final ride = rides[index];
                  final isAccepting = _acceptingRideIds.contains(ride.id);
                  return _RideCard(
                    ride: ride,
                    isAccepting: isAccepting,
                    onAccept: () => _acceptRide(ride, profile.uid),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _RideCard extends StatelessWidget {
  final RideModel ride;
  final bool isAccepting;
  final VoidCallback onAccept;

  const _RideCard({
    required this.ride,
    required this.isAccepting,
    required this.onAccept,
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
              onPressed: isAccepting ? null : onAccept,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: isAccepting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Accepter la course'),
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
