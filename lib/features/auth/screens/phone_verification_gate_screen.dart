import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import 'resend_cooldown_mixin.dart';

/// Bloque l'accès au tableau de bord tant que le numéro WhatsApp n'est pas
/// vérifié par SMS — le passage obligatoire, à la place de l'email (voir
/// AuthGate). Envoie le code automatiquement à l'ouverture : le numéro est
/// déjà connu depuis l'inscription, pas besoin de le faire retaper.
class PhoneVerificationGateScreen extends StatefulWidget {
  final String phoneNumber;

  const PhoneVerificationGateScreen({super.key, required this.phoneNumber});

  @override
  State<PhoneVerificationGateScreen> createState() => _PhoneVerificationGateScreenState();
}

class _PhoneVerificationGateScreenState extends State<PhoneVerificationGateScreen>
    with ResendCooldownMixin {
  final _authService = AuthService();
  final _codeController = TextEditingController();

  late String _phoneNumber;
  String? _verificationId;
  bool _isSending = true;
  bool _isConfirming = false;
  bool _isAutoCompleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _phoneNumber = widget.phoneNumber;
    _sendCode();
  }

  @override
  void dispose() {
    disposeResendCooldown();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    setState(() {
      _isSending = true;
      _error = null;
    });
    try {
      await _authService.startPhoneVerification(
        phoneNumber: _phoneNumber,
        onCodeSent: (verificationId) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _isSending = false;
          });
          startResendCooldown();
        },
        onAutoVerified: () {
          if (!mounted) return;
          // Firestore est déjà à jour à ce stade (AuthService écrit avant
          // d'appeler ce callback) : AuthGate va basculer tout seul sur le
          // tableau de bord dès que son flux Firestore reçoit la mise à
          // jour. On affiche juste un état "presque fini" en attendant.
          setState(() {
            _isAutoCompleting = true;
            _isSending = false;
          });
        },
        onFailed: (e) {
          if (!mounted) return;
          setState(() {
            _isSending = false;
            _error = _mapPhoneError(e);
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _confirmCode() async {
    final verificationId = _verificationId;
    final code = _codeController.text.trim();
    if (verificationId == null || code.length != 6) return;

    setState(() {
      _isConfirming = true;
      _error = null;
    });
    try {
      await _authService.confirmPhoneVerification(
        verificationId: verificationId,
        smsCode: code,
        phoneNumber: _phoneNumber,
      );
      // Rien d'autre à faire : AuthGate écoute déjà le profil Firestore et
      // basculera sur le tableau de bord dès que phoneVerified passe à true.
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = _mapPhoneError(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  String _mapPhoneError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-verification-code':
        return 'Code invalide. Vérifie les 6 chiffres reçus par SMS.';
      case 'session-expired':
        return 'Ce code a expiré, demande-en un nouveau.';
      case 'too-many-requests':
        return 'Trop de tentatives. Réessaie dans quelques minutes.';
      case 'invalid-phone-number':
        return 'Numéro invalide. Vérifie le format (ex : +223 70 00 00 00).';
      default:
        return e.message ?? 'Erreur : ${e.code}';
    }
  }

  Future<void> _editPhoneNumber() async {
    final controller = TextEditingController(text: _phoneNumber);
    final newNumber = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Corriger le numéro'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Numéro WhatsApp',
            hintText: 'Ex : +223 70 00 00 00',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Valider'),
          ),
        ],
      ),
    );

    if (newNumber == null || newNumber.isEmpty || newNumber == _phoneNumber) return;
    setState(() {
      _phoneNumber = newNumber;
      _verificationId = null;
      _codeController.clear();
    });
    _sendCode();
  }

  Future<void> _signOut() async {
    await _authService.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.sms_outlined, size: 56, color: colorScheme.primary),
              const SizedBox(height: 20),
              Text(
                'Vérifie ton numéro WhatsApp',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                _phoneNumber,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: (_isSending || _isAutoCompleting) ? null : _editPhoneNumber,
                child: const Text('Ce numéro est incorrect ? Le modifier'),
              ),
              const SizedBox(height: 16),

              if (_isAutoCompleting) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text('Numéro vérifié, un instant…', textAlign: TextAlign.center),
              ] else if (_isSending) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text(
                  'Le code arrive par SMS dans quelques secondes…',
                  textAlign: TextAlign.center,
                ),
              ] else ...[
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  autofocus: true,
                  maxLength: 6,
                  style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.bold),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: const InputDecoration(
                    counterText: '',
                    labelText: 'Code à 6 chiffres',
                    filled: true,
                  ),
                  onChanged: (v) {
                    if (v.length == 6) _confirmCode();
                  },
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _isConfirming ? null : _confirmCode,
                  style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                  child: _isConfirming
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Vérifier'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: cooldownSeconds > 0 ? null : _sendCode,
                  child: Text(
                    cooldownSeconds > 0
                        ? 'Renvoyer le code (${cooldownSeconds}s)'
                        : 'Renvoyer le code',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tu n\'as rien reçu ? Vérifie que ton numéro est correct, '
                  'ou réessaie dans une minute.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colorScheme.error),
                ),
              ],

              const SizedBox(height: 24),
              TextButton(
                onPressed: _signOut,
                child: const Text('Se déconnecter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
