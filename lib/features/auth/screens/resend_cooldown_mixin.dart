import 'dart:async';

import 'package:flutter/widgets.dart';

/// Délai minimum entre deux renvois (email ou SMS) : en dessous, Firebase
/// finit par répondre 'too-many-requests' sans prévenir, ce qui ressemble
/// à un message qui "n'arrive jamais" alors qu'il a juste été throttlé.
const resendCooldownDuration = Duration(seconds: 60);

/// Compte à rebours partagé par les écrans de renvoi de code (email,
/// vérification SMS obligatoire, vérification SMS facultative depuis le
/// profil) : évite de dupliquer le Timer et son nettoyage dans chacun.
mixin ResendCooldownMixin<T extends StatefulWidget> on State<T> {
  Timer? _cooldownTimer;
  int cooldownSeconds = 0;

  void startResendCooldown() {
    _cooldownTimer?.cancel();
    setState(() => cooldownSeconds = resendCooldownDuration.inSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (cooldownSeconds <= 1) {
        timer.cancel();
        setState(() => cooldownSeconds = 0);
      } else {
        setState(() => cooldownSeconds--);
      }
    });
  }

  void disposeResendCooldown() => _cooldownTimer?.cancel();
}
