import 'dart:async';

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'auth_gate.dart';

/// Bloque l'accès au tableau de bord tant que l'email n'est pas vérifié.
/// Une fois le lien cliqué dans la boîte mail, l'utilisateur revient ici et
/// appuie sur "J'ai vérifié mon email" pour recharger son statut.
class EmailVerificationScreen extends StatefulWidget {
  final String email;

  const EmailVerificationScreen({super.key, required this.email});

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  static const _resendCooldown = Duration(seconds: 60);

  final _authService = AuthService();
  bool _isSending = false;
  bool _isChecking = false;
  Timer? _cooldownTimer;
  int _cooldownSeconds = 0;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldownSeconds = _resendCooldown.inSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _cooldownSeconds = 0);
      } else {
        setState(() => _cooldownSeconds--);
      }
    });
  }

  // Renvoyer l'email en boucle rapprochée fait taire Firebase sans erreur
  // (throttling silencieux) : le cooldown ci-dessus évite ce piège, la
  // cause la plus fréquente d'un email "qui n'arrive jamais" alors que
  // l'appel a bien réussi.
  Future<void> _resend() async {
    setState(() => _isSending = true);
    try {
      await _authService.sendEmailVerification();
      if (!mounted) return;
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Email de vérification renvoyé. Pensez à vérifier vos spams/indésirables.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _checkVerified() async {
    setState(() => _isChecking = true);
    try {
      final verified = await _authService.reloadAndCheckEmailVerified();
      if (!mounted) return;
      if (verified) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AuthGate()),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email pas encore vérifié. Vérifiez votre boîte mail.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
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
              Icon(Icons.mark_email_unread_outlined, size: 56, color: colorScheme.primary),
              const SizedBox(height: 20),
              Text(
                'Vérifiez votre adresse email',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                'Un lien de confirmation a été envoyé à ${widget.email}. '
                'Ouvrez-le, puis revenez ici.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Text(
                'Rien reçu après quelques minutes ? Vérifiez le dossier '
                'spam/indésirables de votre messagerie.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12.5),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _isChecking ? null : _checkVerified,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isChecking
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text("J'ai vérifié mon email"),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: (_isSending || _cooldownSeconds > 0) ? null : _resend,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSending
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _cooldownSeconds > 0
                            ? 'Renvoyer l\'email (${_cooldownSeconds}s)'
                            : "Renvoyer l'email de vérification",
                      ),
              ),
              const SizedBox(height: 16),
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
