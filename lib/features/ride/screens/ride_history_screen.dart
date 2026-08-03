import 'package:flutter/material.dart';
import '../models/ride_model.dart';
import '../services/ride_service.dart';

const List<String> _kMonthsFr = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
];

String _formattedDate(DateTime? date) {
  if (date == null) return '';
  return '${date.day} ${_kMonthsFr[date.month - 1]} ${date.year}';
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

/// Historique des courses : passées côté client, effectuées + gains sur
/// 7/30 jours côté chauffeur (un indicateur qui compte beaucoup pour eux,
/// à ne pas négliger).
class RideHistoryScreen extends StatelessWidget {
  final String userId;
  final String role;

  const RideHistoryScreen({super.key, required this.userId, required this.role});

  bool get _isDriver => role == 'driver_moto' || role == 'driver_taxi';

  @override
  Widget build(BuildContext context) {
    final rideService = RideService();

    return Scaffold(
      appBar: AppBar(title: const Text('Historique')),
      body: StreamBuilder<List<RideModel>>(
        stream: rideService.myRidesStream(userId, _isDriver ? 'driver' : 'client'),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final rides = (snapshot.data ?? [])
              .where((r) => r.status == 'completed' || r.status == 'cancelled')
              .toList();

          if (rides.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Aucune course dans ton historique pour l\'instant.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_isDriver) ...[
                _EarningsSummary(rides: rides),
                const SizedBox(height: 20),
              ],
              ...rides.map((ride) => _RideHistoryTile(ride: ride, isDriver: _isDriver)),
            ],
          );
        },
      ),
    );
  }
}

class _EarningsSummary extends StatelessWidget {
  final List<RideModel> rides;

  const _EarningsSummary({required this.rides});

  int _totalSince(Duration window) {
    final cutoff = DateTime.now().subtract(window);
    return rides
        .where((r) =>
            r.status == 'completed' && r.completedAt != null && r.completedAt!.isAfter(cutoff))
        .fold<int>(0, (sum, r) => sum + r.offeredPrice);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: _EarningsCard(
            label: '7 derniers jours',
            amount: _totalSince(const Duration(days: 7)),
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _EarningsCard(
            label: '30 derniers jours',
            amount: _totalSince(const Duration(days: 30)),
            color: colorScheme.tertiary,
          ),
        ),
      ],
    );
  }
}

class _EarningsCard extends StatelessWidget {
  final String label;
  final int amount;
  final Color color;

  const _EarningsCard({required this.label, required this.amount, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              _formattedPrice(amount),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _RideHistoryTile extends StatelessWidget {
  final RideModel ride;
  final bool isDriver;

  const _RideHistoryTile({required this.ride, required this.isDriver});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isCompleted = ride.status == 'completed';
    final otherParty = isDriver ? ride.clientName : (ride.driverName ?? 'Chauffeur');
    final date = isCompleted ? ride.completedAt : (ride.cancelledAt ?? ride.createdAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  ride.type == 'colis' ? Icons.inventory_2_outlined : Icons.person_outline,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${ride.departureNeighborhood} → ${ride.arrivalNeighborhood}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Chip(
                  label: Text(isCompleted ? 'Terminée' : 'Annulée'),
                  labelStyle: const TextStyle(fontSize: 11),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: isCompleted
                      ? Colors.green.withValues(alpha: 0.15)
                      : colorScheme.errorContainer,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  otherParty.isEmpty ? '—' : otherParty,
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                ),
                Text(
                  _formattedDate(date),
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _formattedPrice(ride.offeredPrice),
              style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}
