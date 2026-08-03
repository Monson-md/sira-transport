import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'package:sira_transport/features/auth/screens/auth_gate.dart';
import 'package:sira_transport/features/notifications/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await NotificationService().initLocalNotifications();
  runApp(const SiraTransportApp());
}

class SiraTransportApp extends StatelessWidget {
  const SiraTransportApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sira-Transport',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green), // Style moderne Material 3
        useMaterial3: true,
      ),
      home: const AuthGate(), // Redirige vers la connexion ou le tableau de bord
    );
  }
}