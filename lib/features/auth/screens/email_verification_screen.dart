import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'resend_cooldown_mixin.dart';

/// Vérification de l'email, facultative : accessible depuis le profil
/// ("Ajouter un email de secours"), plus jamais un blocage d'accès à
/// l'app — c'est le numéro WhatsApp vérifié par SMS qui joue ce rôle
/// (voir AuthGate / PhoneVerificationGateScreen).
class EmailVerificationScreen extends StatefulWidget {
  final String email;

  const EmailVerificationScreen({super.key, required this.email});

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen>
    with ResendCooldownMixin {
  final _authService = AuthService();
  bool _isSending = false;
  bool _isChecking = false;

  @override
  void dispose() {
    disposeResendCooldown();
    super.dispose();
  }

  // Renvoyer l'email en boucle rapprochée fait taire Firebase sans erreur
  // (throttling silencieux) : le cooldown évite ce piège, la cause la plus
  // fréquente d'un email "qui n'arrive jamais" alors que l'appel a bien
  // réussi.
  Future<void> _resend() async {
    setState(() => _isSending = true);
    try {
      await _authService.sendEmailVerification();
      if (!mounted) return;
      startResendCooldown();
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email vérifié, merci !')),
        );
        Navigator.of(context).pop();
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Email de secours (facultatif)')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.mark_email_unread_outlined, size: 56, color: colorScheme.primary),
              const SizedBox(height: 20),
              Text(
                'Confirme ton adresse email',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                'Un lien de confirmation a été envoyé à ${widget.email}. '
                'Ce n\'est pas obligatoire pour utiliser l\'app : ça sert juste de '
                'moyen de contact de secours.',
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
                onPressed: (_isSending || cooldownSeconds > 0) ? null : _resend,
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
                        cooldownSeconds > 0
                            ? 'Renvoyer l\'email (${cooldownSeconds}s)'
                            : "Renvoyer l'email de vérification",
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
