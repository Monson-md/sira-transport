import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/models/user_model.dart';
import '../../auth/services/auth_service.dart';
import '../../ride/screens/ride_tracking_screen.dart';

/// Id du canal Android utilisé pour toutes les notifications de course
/// (priorité HIGH : une course, c'est urgent). Le son est celui du système
/// pour l'instant — pour un son personnalisé, déposer un fichier audio
/// dans android/app/src/main/res/raw/ (ex: ride_alert.mp3) et remplacer
/// `sound: null` ci-dessous par `RawResourceAndroidNotificationSound('ride_alert')`.
const String rideNotificationChannelId = 'rides_urgent';

const String _topicPrefKey = 'fcm_topic';

/// Point d'entrée unique de navigation, utilisé par MaterialApp et par ce
/// service pour ouvrir un écran depuis un tap sur notification, en dehors
/// de tout contexte de widget.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Replie les accents français courants puis remplace tout caractère hors
/// [A-Za-z0-9_] par '_' (les topics FCM n'acceptent que
/// [a-zA-Z0-9-_.~%]). Doit rester strictement identique à la fonction
/// `sanitizeTopicPart` de functions/src/index.ts : le topic publié par la
/// Cloud Function et celui auquel le chauffeur s'abonne doivent matcher
/// caractère pour caractère.
String sanitizeTopicPart(String value) {
  const accents = {
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'à': 'a', 'â': 'a', 'ä': 'a',
    'ô': 'o', 'ö': 'o',
    'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c',
    'î': 'i', 'ï': 'i',
  };
  final folded = value.split('').map((char) {
    final lower = char.toLowerCase();
    return accents[lower] ?? char;
  }).join();

  return folded
      .replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}

/// Topic FCM d'une combinaison pays/ville/type de véhicule, ex:
/// "rides_Mali_Bamako_moto".
String rideTopicFor(String country, String city, String vehicleType) {
  return 'rides_${sanitizeTopicPart(country)}_${sanitizeTopicPart(city)}_${sanitizeTopicPart(vehicleType)}';
}

String _vehicleTypeForRole(String role) {
  switch (role) {
    case 'driver_moto':
      return 'moto';
    case 'driver_taxi':
      return 'taxi';
    default:
      return 'any';
  }
}

/// Doit être une fonction top-level (contrainte de firebase_messaging,
/// exécutée dans un isolate séparé quand l'app est fermée). FCM affiche
/// déjà tout seul la notification système à partir du payload
/// "notification" dans ce cas : ce handler n'a rien à faire de plus.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final AuthService _authService = AuthService();

  bool _handlersBound = false;

  /// Crée le canal Android et initialise le plugin d'affichage local.
  /// À appeler une fois, avant runApp() : ne dépend d'aucun utilisateur
  /// connecté.
  Future<void> initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _localNotifications.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        _handleTapData(jsonDecode(payload) as Map<String, dynamic>);
      },
    );

    const channel = AndroidNotificationChannel(
      rideNotificationChannelId,
      'Courses',
      description:
          'Nouvelles courses disponibles et mises à jour de vos courses en cours.',
      importance: Importance.max,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// À appeler une fois le profil de l'utilisateur connecté chargé :
  /// demande la permission, enregistre le token FCM sur son profil, et
  /// branche les écouteurs de messages (premier plan / tap sur notif).
  Future<void> registerForCurrentUser(UserModel profile) async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    final token = await _messaging.getToken();
    if (token != null) {
      await _authService.updateFcmToken(token);
    }
    _messaging.onTokenRefresh.listen(_authService.updateFcmToken);

    if (_handlersBound) return;
    _handlersBound = true;

    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
    FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _handleTapData(message.data),
    );

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleTapData(initialMessage.data);
    }
  }

  /// Abonne le chauffeur au topic de sa ville/véhicule, en se désabonnant
  /// d'abord de l'ancien topic si sa ville ou son rôle a changé depuis la
  /// dernière fois (topic mémorisé pour survivre à un redémarrage de
  /// l'app).
  Future<void> syncTopicForDriver(UserModel profile) async {
    final desiredTopic = rideTopicFor(
      profile.country,
      profile.city,
      _vehicleTypeForRole(profile.role),
    );

    final prefs = await SharedPreferences.getInstance();
    final currentTopic = prefs.getString(_topicPrefKey);
    if (currentTopic == desiredTopic) return;

    if (currentTopic != null) {
      await _messaging.unsubscribeFromTopic(currentTopic);
    }
    await _messaging.subscribeToTopic(desiredTopic);
    await prefs.setString(_topicPrefKey, desiredTopic);
  }

  /// Désabonne le topic courant. À appeler avant la déconnexion.
  Future<void> unsubscribeCurrentTopic() async {
    final prefs = await SharedPreferences.getInstance();
    final currentTopic = prefs.getString(_topicPrefKey);
    if (currentTopic == null) return;

    await _messaging.unsubscribeFromTopic(currentTopic);
    await prefs.remove(_topicPrefKey);
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    await _localNotifications.show(
      message.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          rideNotificationChannelId,
          'Courses',
          channelDescription:
              'Nouvelles courses disponibles et mises à jour de vos courses en cours.',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _handleTapData(Map<String, dynamic> data) {
    final event = data['event'];
    final rideId = data['rideId'];
    if (rideId == null || (rideId as String).isEmpty) return;
    if (event != 'ride_accepted' && event != 'ride_completed') return;

    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => RideTrackingScreen(rideId: rideId)),
    );
  }
}
