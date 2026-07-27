import 'package:flutter/material.dart';
import '../../auth/models/user_model.dart';
import '../../auth/services/auth_service.dart';
import '../models/ride_model.dart';
import '../services/ride_service.dart';

class CreateRideScreen extends StatefulWidget {
  const CreateRideScreen({super.key});

  @override
  State<CreateRideScreen> createState() => _CreateRideScreenState();
}

class _CreateRideScreenState extends State<CreateRideScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _rideService = RideService();

  final _departureNeighborhoodController = TextEditingController();
  final _departureLandmarkController = TextEditingController();
  final _arrivalNeighborhoodController = TextEditingController();
  final _arrivalLandmarkController = TextEditingController();
  final _priceController = TextEditingController();

  late final Future<UserModel?> _profileFuture;

  String _selectedType = 'colis';
  bool _isPublishing = false;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
  }

  Future<UserModel?> _loadProfile() async {
    final uid = _authService.currentUser?.uid;
    if (uid == null) return null;
    final profile = await _authService.getUserData(uid);
    if (profile != null) {
      _departureNeighborhoodController.text = profile.neighborhood;
    }
    return profile;
  }

  @override
  void dispose() {
    _departureNeighborhoodController.dispose();
    _departureLandmarkController.dispose();
    _arrivalNeighborhoodController.dispose();
    _arrivalLandmarkController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _submit(UserModel profile) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isPublishing = true);
    try {
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
        offeredPrice: double.parse(_priceController.text.trim()),
        country: profile.country,
        city: profile.city,
        createdAt: DateTime.now(),
      );

      await _rideService.createRideRequest(ride);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Votre course a été publiée !')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
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
                              child: _RideTypeOption(
                                emoji: '📦',
                                label: 'Colis',
                                selected: _selectedType == 'colis',
                                onTap: () => setState(() => _selectedType = 'colis'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _RideTypeOption(
                                emoji: '👥',
                                label: 'Passager',
                                selected: _selectedType == 'passager',
                                onTap: () => setState(() => _selectedType = 'passager'),
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
                            hint: 'Ex : devant la pharmacie',
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
                            hint: 'Ex : près du terrain de foot',
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
                            hint: 'Ex : 1500',
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Entrez un prix';
                            }
                            final parsed = double.tryParse(v.trim());
                            if (parsed == null || parsed <= 0) {
                              return 'Entrez un prix valide';
                            }
                            return null;
                          },
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

/// Bouton visuel de sélection du type de course (Colis / Passager).
class _RideTypeOption extends StatelessWidget {
  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RideTypeOption({
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
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: selected ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
