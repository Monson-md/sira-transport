import 'package:flutter/material.dart';
import '../../auth/models/user_model.dart';
import '../../auth/services/auth_service.dart';
import '../models/place.dart';
import '../services/place_service.dart';

/// Écran "Mes lieux", accessible depuis le profil : liste, modification et
/// suppression des lieux favoris du client, plus le formulaire d'ajout.
class PlacesScreen extends StatefulWidget {
  const PlacesScreen({super.key});

  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
  final _authService = AuthService();
  final _placeService = PlaceService();

  UserModel? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = _authService.currentUser?.uid;
    if (uid == null) return;
    final profile = await _authService.getUserData(uid);
    if (mounted) setState(() => _profile = profile);
  }

  Future<void> _openForm({Place? existing}) async {
    final profile = _profile;
    if (profile == null) return;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PlaceFormSheet(existing: existing),
    );
    if (result != true) return;
    // Le sheet a déjà écrit dans Firestore (voir _PlaceFormSheet._submit) ;
    // rien à faire ici, myPlaces() est un flux temps réel.
  }

  Future<void> _confirmDelete(Place place) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce lieu ?'),
        content: Text('« ${place.label} » sera retiré de tes lieux favoris.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await _placeService.deletePlace(place.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes lieux')),
      floatingActionButton: _profile == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter'),
            ),
      body: StreamBuilder<List<Place>>(
        stream: _placeService.myPlaces(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final places = snapshot.data ?? [];
          if (places.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.place_outlined,
                      size: 48,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Aucun lieu enregistré. Ajoute ta maison pour publier '
                      'une course en deux gestes.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: places.length,
            itemBuilder: (context, index) {
              final place = places[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(placeIconData(place.icon)),
                  ),
                  title: Text(place.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${place.neighborhood}, ${place.landmark}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _openForm(existing: place),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _confirmDelete(place),
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

/// Formulaire d'ajout/modification d'un lieu, en feuille modale : label,
/// icône (5 choix), quartier, repère. Ville/pays viennent du profil du
/// client, jamais retapés.
class _PlaceFormSheet extends StatefulWidget {
  final Place? existing;

  const _PlaceFormSheet({this.existing});

  @override
  State<_PlaceFormSheet> createState() => _PlaceFormSheetState();
}

class _PlaceFormSheetState extends State<_PlaceFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _placeService = PlaceService();
  final _authService = AuthService();

  late final TextEditingController _labelController;
  late final TextEditingController _neighborhoodController;
  late final TextEditingController _landmarkController;
  late String _selectedIcon;

  bool _isSaving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _labelController = TextEditingController(text: existing?.label ?? '');
    _neighborhoodController = TextEditingController(text: existing?.neighborhood ?? '');
    _landmarkController = TextEditingController(text: existing?.landmark ?? '');
    _selectedIcon = existing?.icon ?? 'home';
  }

  @override
  void dispose() {
    _labelController.dispose();
    _neighborhoodController.dispose();
    _landmarkController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      if (_isEditing) {
        await _placeService.updatePlace(
          placeId: widget.existing!.id,
          label: _labelController.text.trim(),
          icon: _selectedIcon,
          neighborhood: _neighborhoodController.text.trim(),
          landmark: _landmarkController.text.trim(),
        );
      } else {
        final uid = _authService.currentUser?.uid;
        final profile = uid == null ? null : await _authService.getUserData(uid);
        if (profile == null) return;
        await _placeService.addPlace(
          label: _labelController.text.trim(),
          icon: _selectedIcon,
          neighborhood: _neighborhoodController.text.trim(),
          landmark: _landmarkController.text.trim(),
          city: profile.city,
          country: profile.country,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEditing ? 'Modifier ce lieu' : 'Ajouter un lieu',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _labelController,
              decoration: const InputDecoration(
                labelText: 'Nom du lieu',
                hintText: 'Ex : Chez moi, Mon boulot, Le marché',
              ),
              maxLength: 30,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Entrez un nom' : null,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              children: kPlaceIcons.map((icon) {
                final selected = icon == _selectedIcon;
                return ChoiceChip(
                  avatar: Icon(placeIconData(icon), size: 18),
                  label: Text(kPlaceIconLabels[icon] ?? icon),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedIcon = icon),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _neighborhoodController,
              decoration: const InputDecoration(labelText: 'Quartier'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Entrez le quartier' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _landmarkController,
              decoration: const InputDecoration(
                labelText: 'Repère précis',
                hintText: 'Ex : devant la pharmacie, près du terrain de foot',
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Entrez un repère' : null,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isSaving ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSaving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}
