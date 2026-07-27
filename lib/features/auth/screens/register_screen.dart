import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';

/// Rôles disponibles sur la plateforme.
const Map<String, String> _kRoleLabels = {
  'client': 'Client (Vendeur / Passager)',
  'driver_moto': 'Conducteur Moto-Taxi',
  'driver_taxi': 'Conducteur Taxi Voiture',
};

/// Villes proposées par défaut pour chaque pays supporté.
/// 'Autre' n'a pas de liste : la ville est saisie librement.
const Map<String, List<String>> _kCitiesByCountry = {
  'Mali': ['Bamako', 'Kayes', 'Sikasso', 'Ségou', 'Mopti', 'Koutiala'],
  'Côte d\'Ivoire': ['Abidjan', 'Yamoussoukro', 'Bouaké', 'San-Pédro', 'Daloa'],
  'Sénégal': ['Dakar', 'Thiès', 'Touba', 'Saint-Louis', 'Ziguinchor'],
};

const List<String> _kCountries = ['Mali', 'Côte d\'Ivoire', 'Sénégal', 'Autre'];

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  // Contrôleurs de texte
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _neighborhoodController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _vehicleModelController = TextEditingController();
  final _customCountryController = TextEditingController();
  final _customCityController = TextEditingController();

  String _selectedRole = 'client';
  String _selectedCountry = 'Mali';
  String? _selectedCity = 'Bamako';

  bool _isLoading = false;
  bool _obscurePassword = true;

  bool get _isDriver =>
      _selectedRole == 'driver_moto' || _selectedRole == 'driver_taxi';

  bool get _isCustomCountry => _selectedCountry == 'Autre';

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _neighborhoodController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _vehicleModelController.dispose();
    _customCountryController.dispose();
    _customCityController.dispose();
    super.dispose();
  }

  void _onCountryChanged(String? value) {
    if (value == null) return;
    setState(() {
      _selectedCountry = value;
      final cities = _kCitiesByCountry[value];
      _selectedCity = (cities != null && cities.isNotEmpty) ? cities.first : null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final String country =
        _isCustomCountry ? _customCountryController.text.trim() : _selectedCountry;
    final String city =
        _isCustomCountry ? _customCityController.text.trim() : (_selectedCity ?? '');

    try {
      await _authService.signUpWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        name: _nameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        role: _selectedRole,
        country: country,
        city: city,
        neighborhood: _neighborhoodController.text.trim(),
        vehicleModel: _isDriver ? _vehicleModelController.text.trim() : null,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inscription réussie ! Bienvenue sur Sira-Transport.')),
      );

      // La redirection vers le bon Dashboard selon le rôle se fera à l'étape suivante.
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mapAuthError(e))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'Cet email est déjà utilisé par un autre compte.';
      case 'invalid-email':
        return 'Adresse email invalide.';
      case 'weak-password':
        return 'Mot de passe trop faible (min. 6 caractères).';
      default:
        return 'Erreur d\'inscription : ${e.message ?? e.code}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Créer un compte')),
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _isLoading,
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
                        'Rejoignez Sira-Transport',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Renseignez vos informations pour créer votre compte.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 24),

                      _sectionTitle('Vous êtes'),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedRole,
                        decoration: _inputDecoration(
                          label: 'Rôle',
                          icon: Icons.badge_outlined,
                        ),
                        items: _kRoleLabels.entries
                            .map((e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(e.value),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedRole = v!),
                      ),
                      const SizedBox(height: 24),

                      _sectionTitle('Informations personnelles'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: _inputDecoration(
                          label: 'Nom complet',
                          icon: Icons.person_outline,
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Entrez votre nom' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: _inputDecoration(
                          label: 'Numéro WhatsApp',
                          icon: Icons.phone_outlined,
                          hint: 'Ex : +223 70 00 00 00',
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Entrez votre numéro' : null,
                      ),
                      const SizedBox(height: 24),

                      _sectionTitle('Localisation'),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedCountry,
                        decoration: _inputDecoration(
                          label: 'Pays',
                          icon: Icons.public_outlined,
                        ),
                        items: _kCountries
                            .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: _onCountryChanged,
                      ),
                      const SizedBox(height: 16),
                      if (_isCustomCountry) ...[
                        TextFormField(
                          controller: _customCountryController,
                          textCapitalization: TextCapitalization.words,
                          decoration: _inputDecoration(
                            label: 'Précisez votre pays',
                            icon: Icons.flag_outlined,
                          ),
                          validator: (v) => (_isCustomCountry && (v == null || v.trim().isEmpty))
                              ? 'Entrez le nom du pays'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _customCityController,
                          textCapitalization: TextCapitalization.words,
                          decoration: _inputDecoration(
                            label: 'Ville',
                            icon: Icons.location_city_outlined,
                          ),
                          validator: (v) => (_isCustomCountry && (v == null || v.trim().isEmpty))
                              ? 'Entrez votre ville'
                              : null,
                        ),
                      ] else
                        DropdownButtonFormField<String>(
                          initialValue: _selectedCity,
                          decoration: _inputDecoration(
                            label: 'Ville',
                            icon: Icons.location_city_outlined,
                          ),
                          items: (_kCitiesByCountry[_selectedCountry] ?? [])
                              .map((city) => DropdownMenuItem(value: city, child: Text(city)))
                              .toList(),
                          onChanged: (v) => setState(() => _selectedCity = v),
                          validator: (v) => (v == null || v.isEmpty) ? 'Choisissez une ville' : null,
                        ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _neighborhoodController,
                        textCapitalization: TextCapitalization.words,
                        decoration: _inputDecoration(
                          label: 'Quartier',
                          icon: Icons.map_outlined,
                          hint: 'Ex : Kalabancoro, ACI 2000, Cocody',
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Entrez votre quartier' : null,
                      ),

                      if (_isDriver) ...[
                        const SizedBox(height: 24),
                        _sectionTitle('Véhicule'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _vehicleModelController,
                          decoration: _inputDecoration(
                            label: _selectedRole == 'driver_moto'
                                ? 'Modèle de moto'
                                : 'Modèle du véhicule',
                            icon: Icons.two_wheeler_outlined,
                            hint: _selectedRole == 'driver_moto'
                                ? 'Ex : Sanili, Haojue'
                                : 'Ex : Toyota Corolla, Picanto',
                          ),
                          validator: (v) => (_isDriver && (v == null || v.trim().isEmpty))
                              ? 'Entrez le modèle de votre véhicule'
                              : null,
                        ),
                      ],

                      const SizedBox(height: 24),
                      _sectionTitle('Connexion'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _inputDecoration(
                          label: 'Email',
                          icon: Icons.email_outlined,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Entrez un email';
                          if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) {
                            return 'Email invalide';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: _inputDecoration(
                          label: 'Mot de passe',
                          icon: Icons.lock_outline,
                          hint: 'Minimum 6 caractères',
                        ).copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                            onPressed: () =>
                                setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (v) => (v == null || v.length < 6)
                            ? 'Mot de passe trop court (min. 6 caractères)'
                            : null,
                      ),

                      const SizedBox(height: 32),
                      FilledButton(
                        onPressed: _isLoading ? null : _submit,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'S\'inscrire',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              if (_isLoading)
                Container(
                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
                  child: const Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
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
