import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../auth/models/user_model.dart';
import '../../auth/services/auth_service.dart';
import '../../auth/screens/profile_screen.dart';
import '../models/ride_model.dart';
import '../services/ride_service.dart';

String _vehicleTypeForRole(String role) {
  switch (role) {
    case 'driver_moto':
      return 'moto';
    case 'driver_taxi':
      return 'taxi';
    default:
      return 'any';
  }
}

String _formattedPrice(int price) {
  final digits = price.toString();
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

String _timeAgo(DateTime? date) {
  if (date == null) return 'à l\'instant';
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'à l\'instant';
  if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
  return 'il y a ${diff.inDays} j';
}

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
  final Set<String> _pendingActionRideIds = {};

  /// Courses retirées localement dès qu'un autre chauffeur les a prises,
  /// en attendant que le flux Firestore se resynchronise.
  final Set<String> _dismissedRideIds = {};

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

  Future<void> _acceptRide(RideModel ride, UserModel driver) async {
    setState(() => _pendingActionRideIds.add(ride.id));
    try {
      await _rideService.acceptRide(ride.id, driver);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Course acceptée : ${ride.arrivalNeighborhood}')),
      );
    } on RideAlreadyTakenException catch (e) {
      if (!mounted) return;
      setState(() => _dismissedRideIds.add(ride.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
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
                stream: _rideService.myRidesStream(profile.uid, 'driver'),
                builder: (context, snapshot) {
                  final myRides = snapshot.data ?? [];
                  final currentRide = myRides.where((r) => r.status == 'accepted').firstOrNull;
                  if (currentRide == null) return const SizedBox.shrink();

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
                      _AcceptedRideCard(
                        ride: currentRide,
                        isActionLoading: _pendingActionRideIds.contains(currentRide.id),
                        onComplete: () => _completeRide(currentRide),
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
                stream: _rideService.getAvailableRidesStream(
                  profile.country,
                  profile.city,
                  _vehicleTypeForRole(profile.role),
                ),
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

                  final rides = (snapshot.data ?? [])
                      .where((r) => !_dismissedRideIds.contains(r.id))
                      .toList();

                  if (rides.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.local_shipping_outlined,
                            size: 40,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Aucune course en attente pour le moment.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: rides
                        .map(
                          (ride) => _AvailableRideCard(
                            ride: ride,
                            isActionLoading: _pendingActionRideIds.contains(ride.id),
                            onAccept: () => _acceptRide(ride, profile),
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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _AvailableRideCard extends StatelessWidget {
  final RideModel ride;
  final bool isActionLoading;
  final VoidCallback onAccept;

  const _AvailableRideCard({
    required this.ride,
    required this.isActionLoading,
    required this.onAccept,
  });

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
                  _formattedPrice(ride.offeredPrice),
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
            const SizedBox(height: 8),
            Text(
              _timeAgo(ride.createdAt),
              style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: isActionLoading ? null : onAccept,
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
                  : const Text('Accepter la course'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AcceptedRideCard extends StatelessWidget {
  final RideModel ride;
  final bool isActionLoading;
  final VoidCallback onComplete;

  const _AcceptedRideCard({
    required this.ride,
    required this.isActionLoading,
    required this.onComplete,
  });

  Future<void> _call(BuildContext context) async {
    final uri = Uri(scheme: 'tel', path: ride.clientPhone.replaceAll(' ', ''));
    final launched = await launchUrl(uri);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de lancer l\'appel.')),
      );
    }
  }

  Future<void> _openWhatsApp(BuildContext context) async {
    final digitsOnly = ride.clientPhone.replaceAll(RegExp(r'[^\d]'), '');
    final uri = Uri.parse('https://wa.me/$digitsOnly');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d\'ouvrir WhatsApp.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isColis = ride.type == 'colis';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                const SizedBox(width: 8),
                Text(
                  isColis ? 'Colis · Acceptée' : 'Passager · Acceptée',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  _formattedPrice(ride.offeredPrice),
                  style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _LocationRow(
              icon: Icons.my_location_outlined,
              iconColor: colorScheme.primary,
              neighborhood: ride.departureNeighborhood,
              landmark: ride.departureLandmark,
            ),
            const SizedBox(height: 8),
            _LocationRow(
              icon: Icons.flag_outlined,
              iconColor: colorScheme.tertiary,
              neighborhood: ride.arrivalNeighborhood,
              landmark: ride.arrivalLandmark,
            ),
            const SizedBox(height: 12),
            Text(ride.clientName, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _call(context),
                    icon: const Icon(Icons.call, size: 18),
                    label: const Text('Appeler'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openWhatsApp(context),
                    icon: const Icon(Icons.chat, size: 18),
                    label: const Text('WhatsApp'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: isActionLoading ? null : onComplete,
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
                  : const Text('Terminer la course'),
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
