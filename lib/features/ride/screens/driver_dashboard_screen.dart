import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/tts_service.dart';
import '../../auth/models/user_model.dart';
import '../../auth/services/auth_service.dart';
import '../../auth/screens/profile_screen.dart';
import '../../notifications/services/notification_service.dart';
import '../../verification/screens/driver_documents_screen.dart';
import '../models/ride_model.dart';
import '../services/ride_service.dart';
import 'ride_chat_screen.dart';
import 'ride_history_screen.dart';

const Map<String, String> _kVerificationMessages = {
  'pending': 'Ton dossier est en cours de contrôle. Tu recevras les courses '
      'dès qu\'il sera validé — en général sous 24 h.',
  'rejected': 'Ta vérification a été refusée. Renvoie les pièces demandées '
      'pour recevoir des courses.',
};

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

const List<String> _kUnitsFr = [
  'zéro', 'un', 'deux', 'trois', 'quatre', 'cinq', 'six', 'sept', 'huit', 'neuf',
  'dix', 'onze', 'douze', 'treize', 'quatorze', 'quinze', 'seize', 'dix-sept',
  'dix-huit', 'dix-neuf',
];

const List<String> _kTensFr = ['', '', 'vingt', 'trente', 'quarante', 'cinquante', 'soixante'];

/// Nombre de 0 à 99 en toutes lettres, avec les irrégularités du français
/// (soixante-dix, quatre-vingts, quatre-vingt-onze...).
String _twoDigitsToFrenchWords(int n) {
  if (n < 20) return _kUnitsFr[n];
  if (n < 70) {
    final tens = n ~/ 10;
    final rem = n % 10;
    final tensWord = _kTensFr[tens];
    if (rem == 0) return tensWord;
    if (rem == 1) return '$tensWord et un';
    return '$tensWord-${_kUnitsFr[rem]}';
  }
  if (n < 80) {
    final rem = n - 60;
    if (rem == 11) return 'soixante et onze';
    return 'soixante-${_kUnitsFr[rem]}';
  }
  final rem = n - 80;
  if (rem == 0) return 'quatre-vingts';
  return 'quatre-vingt-${_kUnitsFr[rem]}';
}

/// Nombre de 0 à 999 en toutes lettres ("cent" ne prend un 's' que s'il
/// n'est suivi de rien, ex: "deux cents" mais "deux cent cinquante").
String _threeDigitsToFrenchWords(int n) {
  final hundreds = n ~/ 100;
  final rem = n % 100;
  final buffer = StringBuffer();

  if (hundreds > 0) {
    if (hundreds > 1) buffer.write('${_kUnitsFr[hundreds]} ');
    buffer.write('cent');
    if (hundreds > 1 && rem == 0) buffer.write('s');
    if (rem > 0) buffer.write(' ');
  }
  if (rem > 0) buffer.write(_twoDigitsToFrenchWords(rem));

  return buffer.toString();
}

/// Convertit un entier en toutes lettres, pour que le TTS le prononce
/// correctement ("mille francs" plutôt que "1000 F").
String numberToFrenchWords(int n) {
  if (n == 0) return 'zéro';
  if (n < 0) return 'moins ${numberToFrenchWords(-n)}';

  if (n >= 1000000) {
    final millions = n ~/ 1000000;
    final rest = n % 1000000;
    final millionsWord = millions == 1 ? 'un million' : '${_threeDigitsToFrenchWords(millions)} millions';
    return rest > 0 ? '$millionsWord ${numberToFrenchWords(rest)}' : millionsWord;
  }

  final thousands = n ~/ 1000;
  final rem = n % 1000;
  final parts = <String>[];
  if (thousands > 0) {
    parts.add(thousands == 1 ? 'mille' : '${_threeDigitsToFrenchWords(thousands)} mille');
  }
  if (rem > 0) parts.add(_threeDigitsToFrenchWords(rem));

  return parts.join(' ');
}

/// Phrase lue par le TTS pour annoncer une course, ex : "Nouvelle course
/// colis. Départ Kalabancoro, près du terrain de foot. Arrivée
/// Badalabougou. Prix mille francs."
String _announcementFor(RideModel ride) {
  final typeLabel = ride.type == 'colis' ? 'colis' : 'passager';
  final priceWords = numberToFrenchWords(ride.offeredPrice);
  return 'Nouvelle course $typeLabel. '
      'Départ ${ride.departureNeighborhood}, ${ride.departureLandmark}. '
      'Arrivée ${ride.arrivalNeighborhood}. '
      'Prix $priceWords francs.';
}

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen>
    with WidgetsBindingObserver {
  final _authService = AuthService();
  final _rideService = RideService();

  late final Future<UserModel?> _profileFuture;

  /// Ids des courses en cours d'acceptation, pour désactiver leur bouton.
  final Set<String> _pendingActionRideIds = {};

  /// Courses retirées localement dès qu'un autre chauffeur les a prises,
  /// en attendant que le flux Firestore se resynchronise.
  final Set<String> _dismissedRideIds = {};

  /// Ids des courses déjà annoncées à la voix, pour ne jamais répéter.
  final Set<String> _announcedRideIds = {};

  StreamSubscription<List<RideModel>>? _newRideSub;
  bool _isFirstRideSnapshot = true;
  bool _voiceEnabled = true;
  UserModel? _profile;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _profileFuture = _loadProfile();
  }

  @override
  void dispose() {
    _newRideSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Une annonce en cours n'a pas de sens quand l'app n'est plus au
    // premier plan (et le moteur TTS peut de toute façon être suspendu par
    // l'OS à ce moment-là).
    if (state != AppLifecycleState.resumed) {
      TtsService().stop();
    }
  }

  Future<UserModel?> _loadProfile() async {
    final uid = _authService.currentUser?.uid;
    if (uid == null) return null;
    final profile = await _authService.getUserData(uid);
    if (mounted) setState(() => _profile = profile);
    // Un chauffeur non vérifié n'a pas le droit d'interroger les courses
    // disponibles (firestore.rules), donc pas de topic ni d'annonces
    // pertinents pour lui.
    if (profile != null && profile.verificationStatus == 'approved') {
      await NotificationService().syncTopicForDriver(profile);
      await _initVoiceAnnouncements(profile);
    }
    return profile;
  }

  Future<void> _initVoiceAnnouncements(UserModel profile) async {
    final warning = await TtsService().init();
    if (mounted) {
      setState(() => _voiceEnabled = TtsService().isPreferenceEnabled);
    }
    if (warning != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(warning), duration: const Duration(seconds: 8)),
        );
      });
    }
    _startRideAnnouncements(profile);
  }

  /// Écoute les courses nouvellement publiées pour les annoncer à la voix.
  /// Fait exprès de NE PAS passer par un StreamBuilder dans build() : une
  /// souscription posée une fois ici évite de relire la même course à
  /// chaque reconstruction du widget.
  void _startRideAnnouncements(UserModel profile) {
    _newRideSub?.cancel();
    _isFirstRideSnapshot = true;

    _newRideSub = _rideService
        .watchNewlyAddedRides(profile.country, profile.city, _vehicleTypeForRole(profile.role))
        .listen((newRides) {
      // Le premier snapshot d'un listener Firestore contient un "added"
      // pour chaque course déjà présente : on les mémorise comme connues
      // sans les annoncer, sinon toutes les courses en attente seraient
      // lues d'un coup au démarrage.
      if (_isFirstRideSnapshot) {
        _isFirstRideSnapshot = false;
        _announcedRideIds.addAll(newRides.map((ride) => ride.id));
        return;
      }

      for (final ride in newRides) {
        if (_announcedRideIds.add(ride.id)) {
          TtsService().speak(_announcementFor(ride));
        }
      }
    });
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
  }

  void _openHistory(UserModel profile) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RideHistoryScreen(userId: profile.uid, role: profile.role),
      ),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _voiceEnabled ? Icons.record_voice_over : Icons.voice_over_off,
                  size: 20,
                ),
                Switch(
                  value: _voiceEnabled,
                  onChanged: !TtsService().isAvailable
                      ? null
                      : (next) async {
                          await TtsService().setEnabled(next);
                          if (mounted) setState(() => _voiceEnabled = next);
                        },
                ),
              ],
            ),
          ),
          if (_profile != null)
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'Historique',
              onPressed: () => _openHistory(_profile!),
            ),
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

          // Un chauffeur non vérifié ne peut pas interroger les courses
          // disponibles : firestore.rules l'interdit (approvedDriver()).
          // On le sait avant même d'essayer, pour éviter un permission-denied.
          if (profile.verificationStatus != 'approved') {
            return _PendingVerificationView(verificationStatus: profile.verificationStatus);
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

class _PendingVerificationView extends StatelessWidget {
  final String verificationStatus;

  const _PendingVerificationView({required this.verificationStatus});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              verificationStatus == 'rejected' ? Icons.error_outline : Icons.hourglass_top,
              size: 48,
              color: verificationStatus == 'rejected' ? colorScheme.error : colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              verificationStatus == 'rejected'
                  ? 'Vérification refusée'
                  : 'En attente de vérification',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _kVerificationMessages[verificationStatus] ??
                  'Ton dossier est en cours de contrôle.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DriverDocumentsScreen()),
                );
              },
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Gérer mes pièces'),
            ),
          ],
        ),
      ),
    );
  }
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
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Réécouter',
                  icon: const Icon(Icons.volume_up_outlined),
                  onPressed: () => TtsService().speak(_announcementFor(ride)),
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

  Future<void> _call(BuildContext context, String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(' ', ''));
    final launched = await launchUrl(uri);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de lancer l\'appel.')),
      );
    }
  }

  Future<void> _openWhatsApp(BuildContext context, String phone) async {
    final digitsOnly = phone.replaceAll(RegExp(r'[^\d]'), '');
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
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Réécouter',
                  icon: const Icon(Icons.volume_up_outlined),
                  onPressed: () => TtsService().speak(_announcementFor(ride)),
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
            // Le numéro du client n'est jamais dénormalisé sur le document
            // rides/{id} (voir RideService.createRideRequest) : on le lit
            // depuis la sous-collection privée, accessible uniquement une
            // fois la course acceptée par ce chauffeur.
            StreamBuilder<String?>(
              stream: RideService().watchClientPhone(ride.id),
              builder: (context, snapshot) {
                final phone = snapshot.data;
                return Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: phone == null ? null : () => _call(context, phone),
                        icon: const Icon(Icons.call, size: 18),
                        label: const Text('Appeler'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: phone == null ? null : () => _openWhatsApp(context, phone),
                        icon: const Icon(Icons.chat, size: 18),
                        label: const Text('WhatsApp'),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            if (ride.driverId != null)
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RideChatScreen(
                      rideId: ride.id,
                      currentUserId: ride.driverId!,
                      otherPartyName: ride.clientName,
                    ),
                  ),
                ),
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: const Text('Discuter avec le client'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
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
