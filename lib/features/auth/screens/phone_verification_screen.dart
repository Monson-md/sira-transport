import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';

/// Vérifie le numéro WhatsApp du profil par SMS (Firebase Phone Auth) et le
/// rattache au compte existant. N'est pas un blocage d'accès : accessible
/// depuis le profil, à la différence de la vérification email.
class PhoneVerificationScreen extends StatefulWidget {
  final String initialPhoneNumber;

  const PhoneVerificationScreen({super.key, required this.initialPhoneNumber});

  @override
  State<PhoneVerificationScreen> createState() => _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState extends State<PhoneVerificationScreen> {
  final _authService = AuthService();
  late final TextEditingController _phoneController;
  final _codeController = TextEditingController();

  String? _verificationId;
  bool _isSendingCode = false;
  bool _isConfirming = false;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(text: widget.initialPhoneNumber);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (!phone.startsWith('+') || phone.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entrez un numéro au format international, ex : +223 70 00 00 00')),
      );
      return;
    }

    setState(() => _isSendingCode = true);
    try {
      await _authService.startPhoneVerification(
        phoneNumber: phone.replaceAll(' ', ''),
        onCodeSent: (verificationId) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _isSendingCode = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Code envoyé par SMS.')),
          );
        },
        onAutoVerified: () {
          if (!mounted) return;
          setState(() => _isSendingCode = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Numéro vérifié automatiquement !')),
          );
          Navigator.of(context).pop();
        },
        onFailed: (e) {
          if (!mounted) return;
          setState(() => _isSendingCode = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : ${e.message ?? e.code}')),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSendingCode = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : ${e.toString()}')),
      );
    }
  }

  Future<void> _confirmCode() async {
    final verificationId = _verificationId;
    if (verificationId == null) return;

    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    setState(() => _isConfirming = true);
    try {
      await _authService.confirmPhoneVerification(
        verificationId: verificationId,
        smsCode: code,
        phoneNumber: _phoneController.text.trim().replaceAll(' ', ''),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Numéro vérifié !')),
      );
      Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Code invalide : ${e.message ?? e.code}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSentCode = _verificationId != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Vérifier mon numéro')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Un code vous sera envoyé par SMS pour confirmer ce numéro.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _phoneController,
                enabled: !hasSentCode,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Numéro WhatsApp',
                  hintText: 'Ex : +223 70 00 00 00',
                  filled: true,
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 16),
              if (!hasSentCode)
                FilledButton(
                  onPressed: _isSendingCode ? null : _sendCode,
                  style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                  child: _isSendingCode
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Envoyer le code'),
                ),
              if (hasSentCode) ...[
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Code reçu par SMS',
                    filled: true,
                    prefixIcon: Icon(Icons.sms_outlined),
                  ),
                ),
                const SizedBox(height: 16),
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
                TextButton(
                  onPressed: _isSendingCode ? null : _sendCode,
                  child: const Text('Renvoyer le code'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
