import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../auth/models/user_model.dart';
import '../../auth/services/auth_service.dart';
import '../models/ride_model.dart';
import '../services/ride_service.dart';
import 'ride_chat_screen.dart';

/// Écran de suivi d'une course côté client, branché en temps réel sur
/// [RideService.watchRide]. Le numéro du chauffeur n'apparaît que lorsque
/// ride.status == 'accepted' : avant, on ne sait même pas qui il est.
class RideTrackingScreen extends StatefulWidget {
  final String rideId;

  const RideTrackingScreen({super.key, required this.rideId});

  @override
  State<RideTrackingScreen> createState() => _RideTrackingScreenState();
}

class _RideTrackingScreenState extends State<RideTrackingScreen> {
  final _rideService = RideService();
  bool _isCancelling = false;
  bool _isIncreasingPrice = false;

  Future<void> _cancel(String rideId) async {
    setState(() => _isCancelling = true);
    try {
      await _rideService.cancelRide(rideId);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : ${e.toString()}')),
      );
      setState(() => _isCancelling = false);
    }
  }

  Future<void> _increasePrice(RideModel ride) async {
    setState(() => _isIncreasingPrice = true);
    try {
      await _rideService.increaseOfferedPrice(ride.id, ride.offeredPrice + 500);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isIncreasingPrice = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Votre course')),
      body: StreamBuilder<RideModel>(
        stream: _rideService.watchRide(widget.rideId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || !snapshot.hasData || snapshot.data!.id.isEmpty) {
            return const Center(child: Text('Impossible de charger cette course.'));
          }

          final ride = snapshot.data!;

          switch (ride.status) {
            case 'accepted':
              return _AcceptedView(ride: ride);
            case 'completed':
              return _CompletedView(ride: ride);
            case 'cancelled':
              return const _CancelledView();
            case 'pending':
            default:
              return _PendingView(
                ride: ride,
                isCancelling: _isCancelling,
                onCancel: () => _cancel(ride.id),
                isIncreasingPrice: _isIncreasingPrice,
                onIncreasePrice: () => _increasePrice(ride),
              );
          }
        },
      ),
    );
  }
}

/// Écran d'attente qui reste vivant : chrono d'attente, message qui évolue,
/// et bouton pour augmenter l'offre après 3 minutes sans réponse — pour
/// que le client ne se demande jamais si l'app est plantée.
class _PendingView extends StatefulWidget {
  final RideModel ride;
  final bool isCancelling;
  final VoidCallback onCancel;
  final bool isIncreasingPrice;
  final VoidCallback onIncreasePrice;

  const _PendingView({
    required this.ride,
    required this.isCancelling,
    required this.onCancel,
    required this.isIncreasingPrice,
    required this.onIncreasePrice,
  });

  @override
  State<_PendingView> createState() => _PendingViewState();
}

class _PendingViewState extends State<_PendingView> {
  static const _messageThreshold = Duration(minutes: 2);
  static const _increaseOfferThreshold = Duration(minutes: 3);

  Timer? _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateElapsed();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateElapsed());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateElapsed() {
    final createdAt = widget.ride.createdAt;
    if (createdAt == null) return;
    setState(() => _elapsed = DateTime.now().difference(createdAt));
  }

  String _formattedElapsed() {
    final minutes = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ride = widget.ride;
    final searchMessage = _elapsed >= _messageThreshold
        ? 'Toujours en recherche, essaie d\'augmenter ton prix ?'
        : 'Recherche d\'un chauffeur…';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(color: colorScheme.primary),
            ),
            const SizedBox(height: 24),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Text(
                searchMessage,
                key: ValueKey(searchMessage),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Depuis ${_formattedElapsed()}',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${ride.departureNeighborhood} → ${ride.arrivalNeighborhood}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${ride.offeredPrice} FCFA',
                      style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (_elapsed >= _increaseOfferThreshold) ...[
              FilledButton.icon(
                onPressed: widget.isIncreasingPrice ? null : widget.onIncreasePrice,
                icon: widget.isIncreasingPrice
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.trending_up),
                label: const Text('Augmenter mon offre de 500 F'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
            ],
            OutlinedButton(
              onPressed: widget.isCancelling ? null : widget.onCancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.error,
                side: BorderSide(color: colorScheme.error),
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: widget.isCancelling
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Annuler la course'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AcceptedView extends StatelessWidget {
  final RideModel ride;

  const _AcceptedView({required this.ride});

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
    final driverId = ride.driverId;
    final driverName = ride.driverName ?? 'Chauffeur';
    final driverPhone = ride.driverPhone;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$driverName arrive vers vous',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (driverId != null)
            FutureBuilder<UserModel?>(
              future: AuthService().getUserData(driverId),
              builder: (context, snapshot) {
                final driver = snapshot.data;
                return Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: colorScheme.primaryContainer,
                          child: Text(
                            driverName.isNotEmpty ? driverName[0].toUpperCase() : '?',
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(driverName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        if (driver?.vehicleModel != null && driver!.vehicleModel!.isNotEmpty)
                          Text(
                            driver.vehicleModel!,
                            style: TextStyle(color: colorScheme.onSurfaceVariant),
                          ),
                        if (driver != null) ...[
                          const SizedBox(height: 4),
                          Text('⭐ ${driver.rating.toStringAsFixed(1)}'),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 16),
          if (driverPhone != null)
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _call(context, driverPhone),
                    icon: const Icon(Icons.call),
                    label: const Text('Appeler'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _openWhatsApp(context, driverPhone),
                    icon: const Icon(Icons.chat),
                    label: const Text('WhatsApp'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          if (driverId != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RideChatScreen(
                    rideId: ride.id,
                    currentUserId: ride.clientId,
                    otherPartyName: driverName,
                  ),
                ),
              ),
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Chat'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${ride.departureNeighborhood} → ${ride.arrivalNeighborhood}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    '${ride.departureLandmark} → ${ride.arrivalLandmark}',
                    style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${ride.offeredPrice} FCFA',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: colorScheme.primary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Le paiement se fait de la main à la main, comme d\'habitude.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _CompletedView extends StatefulWidget {
  final RideModel ride;

  const _CompletedView({required this.ride});

  @override
  State<_CompletedView> createState() => _CompletedViewState();
}

class _CompletedViewState extends State<_CompletedView> {
  int _selectedStars = 5;

  void _finish() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 56, color: colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              widget.ride.type == 'colis' ? 'Colis livré' : 'Course terminée',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.ride.offeredPrice} FCFA',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 28),
            Text(
              'Comment était ${widget.ride.driverName ?? 'votre chauffeur'} ?',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final starIndex = index + 1;
                return IconButton(
                  iconSize: 34,
                  onPressed: () => setState(() => _selectedStars = starIndex),
                  icon: Icon(
                    starIndex <= _selectedStars ? Icons.star : Icons.star_border,
                    color: colorScheme.primary,
                  ),
                );
              }),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _finish,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Envoyer'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _finish,
              child: const Text('Passer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CancelledView extends StatelessWidget {
  const _CancelledView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cancel_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('Cette course a été annulée.', textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Retour'),
            ),
          ],
        ),
      ),
    );
  }
}
