import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _prefsEnabledKey = 'tts_enabled';

/// Lecture vocale des annonces de course, pour les chauffeurs.
///
/// Volontairement un service simple à état interne (pas un Stream/
/// ChangeNotifier) : les écrans appellent [speak] quand un événement se
/// produit, jamais depuis un `build()`. C'est le seul moyen d'éviter la
/// boucle classique où un StreamBuilder relit la même course à chaque
/// rebuild.
class TtsService {
  static final TtsService _instance = TtsService._internal();

  factory TtsService() => _instance;

  TtsService._internal();

  final FlutterTts _tts = FlutterTts();

  bool _initialized = false;
  bool _available = false;
  bool _enabled = true;

  final List<String> _pending = [];
  bool _isSpeaking = false;

  /// True si le français est disponible sur cet appareil pour la synthèse
  /// vocale (indépendant de la préférence utilisateur).
  bool get isAvailable => _available;

  /// Préférence "Lecture vocale" telle que choisie par le chauffeur
  /// (indépendante de la disponibilité réelle du français).
  bool get isPreferenceEnabled => _enabled;

  /// Initialise le moteur TTS (langue, débit, vérification de la
  /// disponibilité du français) et charge la préférence sauvegardée.
  /// Idempotent : les appels suivants ne font rien et renvoient null.
  ///
  /// Renvoie un message à afficher une seule fois si le français n'est
  /// pas installé sur l'appareil (fréquent sur les Android d'entrée de
  /// gamme), sinon null.
  Future<String?> init() async {
    if (_initialized) return null;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_prefsEnabledKey) ?? true;

    try {
      await _tts.setLanguage('fr-FR');
      await _tts.setSpeechRate(0.45);
      await _tts.awaitSpeakCompletion(true);

      final result = await _tts.isLanguageAvailable('fr-FR');
      _available = result == true || result == 1;
    } catch (_) {
      _available = false;
    }

    if (!_available) {
      return 'La voix française n\'est pas installée sur cet appareil, la '
          'lecture des courses est désactivée. Pour l\'activer : '
          'Paramètres du téléphone → Langues et saisie → Synthèse vocale '
          '(Text-to-speech) → données vocales → installe le français.';
    }
    return null;
  }

  /// Active ou désactive la lecture vocale (préférence persistée). La
  /// désactiver coupe immédiatement toute annonce en cours ou en attente.
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEnabledKey, value);
    if (!value) {
      await stop();
    }
  }

  /// Met [text] en file d'attente. Si une annonce est déjà en cours, celle-ci
  /// se termine avant que la suivante ne démarre — jamais de superposition.
  /// Ne fait rien si le TTS est désactivé ou le français indisponible.
  void speak(String text) {
    if (!_available || !_enabled) return;
    _pending.add(text);
    _drain();
  }

  Future<void> _drain() async {
    if (_isSpeaking) return;
    _isSpeaking = true;
    try {
      while (_pending.isNotEmpty) {
        if (!_available || !_enabled) {
          _pending.clear();
          break;
        }
        final text = _pending.removeAt(0);
        try {
          await _tts.speak(text);
        } catch (_) {
          // Une erreur du moteur TTS ne doit pas bloquer les annonces
          // suivantes de la file.
        }
      }
    } finally {
      _isSpeaking = false;
    }
  }

  /// Arrête l'annonce en cours et vide la file d'attente.
  Future<void> stop() async {
    _pending.clear();
    await _tts.stop();
  }
}
