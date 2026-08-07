import 'package:flutter/material.dart';
import '../../auth/models/user_model.dart';
import '../../auth/services/auth_service.dart';
import '../../places/models/place.dart';
import '../../places/screens/places_screen.dart';
import '../../places/services/place_service.dart';
import '../models/ride_model.dart';
import '../services/ride_service.dart';
import 'ride_tracking_screen.dart';

const int _kMinPrice = 100;
const List<int> _kQuickPriceSteps = [100, 500, 1000];

class CreateRideScreen extends StatefulWidget {
  const CreateRideScreen({super.key});

  @override
  State<CreateRideScreen> createState() => _CreateRideScreenState();
}

class _CreateRideScreenState extends State<CreateRideScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _rideService = RideService();
  final _placeService = PlaceService();

  final _departureNeighborhoodController = TextEditingController();
  final _departureLandmarkController = TextEditingController();
  final _arrivalNeighborhoodController = TextEditingController();
  final _arrivalLandmarkController = TextEditingController();
  final _priceController = TextEditingController();

  late final Future<UserModel?> _profileFuture;

  String _selectedType = 'colis';
  String _selectedVehicleType = 'moto';
  bool _isPublishing = false;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
    // Le petit indicateur "Remplir le départ / l'arrivée" dépend du
    // contenu des champs de départ : il doit se mettre à jour aussi bien
    // quand une puce de lieu les remplit que quand le client tape lui-même.
    _departureNeighborhoodController.addListener(_onDepartureChanged);
    _departureLandmarkController.addListener(_onDepartureChanged);
  }

  void _onDepartureChanged() => setState(() {});

  Future<UserModel?> _loadProfile() async {
    final uid = _authService.currentUser?.uid;
    if (uid == null) return null;
    final profile = await _authService.getUserData(uid);
    if (profile != null) {
      _departureNeighborhoodController.text = profile.neighborhood;
    }
    return profile;
  }

  bool get _departureComplete =>
      _departureNeighborhoodController.text.trim().isNotEmpty &&
      _departureLandmarkController.text.trim().isNotEmpty;

  /// Un appui simple remplit le départ ; une fois le départ complet
  /// (quartier + repère), l'appui suivant remplit l'arrivée. Les champs
  /// restent modifiables ensuite : c'est une suggestion, pas un verrou.
  void _applyPlace(Place place) {
    if (!_departureComplete) {
      _departureNeighborhoodController.text = place.neighborhood;
      _departureLandmarkController.text = place.landmark;
    } else {
      _arrivalNeighborhoodController.text = place.neighborhood;
      _arrivalLandmarkController.text = place.landmark;
      setState(() {});
    }
    _placeService.markUsed(place.id);
  }

  void _openPlaces() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlacesScreen()),
    );
  }

  @override
  void dispose() {
    _departureNeighborhoodController.removeListener(_onDepartureChanged);
    _departureLandmarkController.removeListener(_onDepartureChanged);
    _departureNeighborhoodController.dispose();
    _departureLandmarkController.dispose();
    _arrivalNeighborhoodController.dispose();
    _arrivalLandmarkController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _bumpPrice(int amount) {
    final current = int.tryParse(_priceController.text.trim()) ?? 0;
    setState(() {
      _priceController.text = (current + amount).toString();
    });
  }

  Future<void> _submit(UserModel profile) async {
    if (!_formKey.currentState!.validate()) return;

    final price = int.parse(_priceController.text.trim());
    final ride = RideModel(
      id: '',
      clientId: profile.uid,
      clientName: profile.name,
      clientPhone: profile.phoneNumber,
      type: _selectedType,
      departureNeighborhood: _departureNeighborhoodController.text.trim(),
      departureLandmark: _departureLandmarkController.text.trim(),
      arrivalNeighborhood: _arrivalNeighborhoodController.text.trim(),
      arrivalLandmark: _arrivalLandmarkController.text.trim(),
      offeredPrice: price,
      vehicleType: _selectedVehicleType,
      country: profile.country,
      city: profile.city,
    );

    final confirmed = await _showRecapDialog(ride);
    if (confirmed != true || !mounted) return;

    setState(() => _isPublishing = true);
    try {
      final rideId = await _rideService.createRideRequest(ride);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => RideTrackingScreen(rideId: rideId)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  Future<bool?> _showRecapDialog(RideModel ride) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmer la course'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ride.type == 'colis' ? '📦 Colis' : '👥 Passager'),
            Text(ride.vehicleType == 'moto' ? '🏍️ Moto' : '🚕 Taxi'),
            const SizedBox(height: 12),
            Text('${ride.departureNeighborhood} (${ride.departureLandmark})'),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Icon(Icons.arrow_downward, size: 16),
            ),
            Text('${ride.arrivalNeighborhood} (${ride.arrivalLandmark})'),
            const SizedBox(height: 12),
            Text(
              '${ride.offeredPrice} FCFA',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Modifier'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Publier une course')),
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

          return SafeArea(
            child: Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _PlacesRow(
                          placesStream: _placeService.myPlaces(),
                          indicatorText:
                              _departureComplete ? 'Remplir l\'arrivée' : 'Remplir le départ',
                          onPlaceTap: _applyPlace,
                          onAddTap: _openPlaces,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Que souhaitez-vous envoyer ?',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _RideTypeCard(
                                emoji: '📦',
                                label: 'Colis',
                                selected: _selectedType == 'colis',
                                onTap: () => setState(() => _selectedType = 'colis'),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _RideTypeCard(
                                emoji: '👥',
                                label: 'Passager',
                                selected: _selectedType == 'passager',
                                onTap: () => setState(() => _selectedType = 'passager'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        _sectionTitle('Véhicule souhaité'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _RideTypeCard(
                                emoji: '🏍️',
                                label: 'Moto',
                                selected: _selectedVehicleType == 'moto',
                                onTap: () => setState(() => _selectedVehicleType = 'moto'),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _RideTypeCard(
                                emoji: '🚕',
                                label: 'Taxi',
                                selected: _selectedVehicleType == 'taxi',
                                onTap: () => setState(() => _selectedVehicleType = 'taxi'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        _sectionTitle('Départ'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _departureNeighborhoodController,
                          decoration: _inputDecoration(
                            label: 'Quartier de départ',
                            icon: Icons.my_location_outlined,
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Entrez le quartier de départ'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _departureLandmarkController,
                          decoration: _inputDecoration(
                            label: 'Repère précis',
                            icon: Icons.place_outlined,
                            hint: 'Ex : devant la pharmacie, près du terrain de foot',
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Entrez un repère de départ'
                              : null,
                        ),
                        const SizedBox(height: 24),

                        _sectionTitle('Arrivée'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _arrivalNeighborhoodController,
                          decoration: _inputDecoration(
                            label: 'Quartier d\'arrivée',
                            icon: Icons.location_on_outlined,
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Entrez le quartier d\'arrivée'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _arrivalLandmarkController,
                          decoration: _inputDecoration(
                            label: 'Repère précis',
                            icon: Icons.flag_outlined,
                            hint: 'Ex : devant la pharmacie, près du terrain de foot',
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Entrez un repère d\'arrivée'
                              : null,
                        ),
                        const SizedBox(height: 24),

                        _sectionTitle('Prix'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _priceController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: false),
                          decoration: _inputDecoration(
                            label: 'Prix proposé (FCFA)',
                            icon: Icons.payments_outlined,
                            hint: 'Ex : 1000',
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Entrez un prix';
                            }
                            final parsed = int.tryParse(v.trim());
                            if (parsed == null || parsed < _kMinPrice) {
                              return 'Le prix minimum est de $_kMinPrice FCFA';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          children: _kQuickPriceSteps
                              .map(
                                (step) => OutlinedButton(
                                  onPressed: () => _bumpPrice(step),
                                  child: Text('+$step'),
                                ),
                              )
                              .toList(),
                        ),

                        const SizedBox(height: 32),
                        FilledButton(
                          onPressed: _isPublishing ? null : () => _submit(profile),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(double.infinity, 52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Publier la course',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                if (_isPublishing)
                  Container(
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}

/// Rangée de puces "lieux favoris" en haut du formulaire : un appui remplit
/// le départ, puis l'arrivée une fois le départ complet. Toujours une puce
/// "+ Ajouter" ; si le client n'a encore aucun lieu, c'est la seule.
class _PlacesRow extends StatelessWidget {
  final Stream<List<Place>> placesStream;
  final String indicatorText;
  final ValueChanged<Place> onPlaceTap;
  final VoidCallback onAddTap;

  const _PlacesRow({
    required this.placesStream,
    required this.indicatorText,
    required this.onPlaceTap,
    required this.onAddTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return StreamBuilder<List<Place>>(
      stream: placesStream,
      builder: (context, snapshot) {
        final places = snapshot.data ?? [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              places.isEmpty ? 'Enregistre les endroits où tu vas souvent.' : indicatorText,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: places.isEmpty ? FontWeight.normal : FontWeight.w600,
                color: places.isEmpty ? colorScheme.onSurfaceVariant : colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final place in places) ...[
                    _PlaceChip(place: place, onTap: () => onPlaceTap(place)),
                    const SizedBox(width: 8),
                  ],
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('Ajouter'),
                    onPressed: onAddTap,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PlaceChip extends StatelessWidget {
  final Place place;
  final VoidCallback onTap;

  const _PlaceChip({required this.place, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(placeIconData(place.icon), size: 18),
      label: Text(place.label),
      onPressed: onTap,
    );
  }
}

/// Grande carte cliquable de sélection du type de course (Colis / Passager).
class _RideTypeCard extends StatelessWidget {
  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RideTypeCard({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: selected ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 36)),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: selected ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
