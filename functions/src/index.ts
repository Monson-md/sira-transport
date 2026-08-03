import { initializeApp } from 'firebase-admin/app';
import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import * as logger from 'firebase-functions/logger';
import { CallableRequest, HttpsError, onCall } from 'firebase-functions/v2/https';
import { onDocumentCreated, onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';

initializeApp();
const db = getFirestore();
const messaging = getMessaging();

const RIDE_NOTIFICATION_CHANNEL_ID = 'rides_urgent';

function assertAdmin(request: CallableRequest): void {
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError('permission-denied', 'Réservé aux administrateurs.');
  }
}

function requireDriverId(data: unknown): string {
  const driverId = (data as { driverId?: unknown } | null)?.driverId;
  if (typeof driverId !== 'string' || driverId.length === 0) {
    throw new HttpsError('invalid-argument', 'driverId manquant.');
  }
  return driverId;
}

/**
 * Seule fonction autorisée à faire passer un chauffeur à 'approved'.
 * firestore.rules verrouille users/{uid}.verificationStatus contre toute
 * écriture depuis l'app — ce callable, exécuté avec l'Admin SDK, est le
 * seul chemin qui puisse le changer.
 */
export const approveDriver = onCall(async (request) => {
  assertAdmin(request);
  const driverId = requireDriverId(request.data);

  const userRef = db.collection('users').doc(driverId);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new HttpsError('not-found', "Ce chauffeur n'existe pas.");
  }

  await userRef.update({ verificationStatus: 'approved' });

  const pendingDocs = await db
    .collection('driver_documents')
    .where('driverId', '==', driverId)
    .where('status', '==', 'pending_review')
    .get();

  const batch = db.batch();
  pendingDocs.forEach((doc) => batch.update(doc.ref, { status: 'approved' }));
  await batch.commit();

  return { driverId, verificationStatus: 'approved' };
});

/** Refuse un chauffeur ; il pourra renvoyer ses pièces depuis l'app. */
export const rejectDriver = onCall(async (request) => {
  assertAdmin(request);
  const driverId = requireDriverId(request.data);

  const userRef = db.collection('users').doc(driverId);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new HttpsError('not-found', "Ce chauffeur n'existe pas.");
  }

  await userRef.update({ verificationStatus: 'rejected' });

  const pendingDocs = await db
    .collection('driver_documents')
    .where('driverId', '==', driverId)
    .where('status', '==', 'pending_review')
    .get();

  const batch = db.batch();
  pendingDocs.forEach((doc) => batch.update(doc.ref, { status: 'rejected' }));
  await batch.commit();

  return { driverId, verificationStatus: 'rejected' };
});

// ===============================================================
// Notifications temps réel
// ===============================================================

/**
 * Replie les accents français courants puis remplace tout caractère hors
 * [A-Za-z0-9_] par '_' (les topics FCM n'acceptent que
 * [a-zA-Z0-9-_.~%]). Doit rester strictement identique à la fonction
 * sanitizeTopicPart de
 * lib/features/notifications/services/notification_service.dart : le
 * topic publié ici et celui auquel le chauffeur s'abonne doivent matcher
 * caractère pour caractère.
 */
const ACCENT_FOLD: Record<string, string> = {
  é: 'e',
  è: 'e',
  ê: 'e',
  ë: 'e',
  à: 'a',
  â: 'a',
  ä: 'a',
  ô: 'o',
  ö: 'o',
  ù: 'u',
  û: 'u',
  ü: 'u',
  ç: 'c',
  î: 'i',
  ï: 'i',
};

function sanitizeTopicPart(value: string): string {
  const folded = value
    .split('')
    .map((char) => ACCENT_FOLD[char.toLowerCase()] ?? char)
    .join('');

  return folded
    .replace(/[^A-Za-z0-9_]/g, '_')
    .replace(/_+/g, '_')
    .replace(/^_+|_+$/g, '');
}

function rideTopicFor(country: string, city: string, vehicleType: string): string {
  return `rides_${sanitizeTopicPart(country)}_${sanitizeTopicPart(city)}_${sanitizeTopicPart(vehicleType)}`;
}

interface RideData {
  clientId: string;
  driverName?: string;
  status: string;
  type: string;
  offeredPrice: number;
  departureNeighborhood: string;
  arrivalNeighborhood: string;
  vehicleType: string;
  country: string;
  city: string;
}

/** Notifie les chauffeurs du topic concerné qu'une nouvelle course est disponible. */
export const onRideCreated = onDocumentCreated('rides/{rideId}', async (event) => {
  const snap = event.data;
  if (!snap) return;

  const ride = snap.data() as RideData;
  if (ride.status !== 'pending') return;

  const rideId = event.params.rideId;
  const topics =
    ride.vehicleType === 'any'
      ? [rideTopicFor(ride.country, ride.city, 'moto'), rideTopicFor(ride.country, ride.city, 'taxi')]
      : [rideTopicFor(ride.country, ride.city, ride.vehicleType)];

  const typeLabel = ride.type === 'colis' ? 'colis' : 'passager';
  const title = `Nouvelle course ${typeLabel} — ${ride.offeredPrice} F`;
  const body = `${ride.departureNeighborhood} -> ${ride.arrivalNeighborhood}`;

  await Promise.all(
    topics.map((topic) =>
      messaging
        .send({
          topic,
          notification: { title, body },
          data: { rideId, type: ride.type, price: String(ride.offeredPrice) },
          android: {
            priority: 'high',
            notification: { channelId: RIDE_NOTIFICATION_CHANNEL_ID, priority: 'max' },
          },
        })
        .catch((error) => {
          logger.error(`Échec envoi notification sur le topic ${topic}`, error);
        })
    )
  );
});

async function notifyClient(
  clientId: string,
  title: string,
  body: string,
  rideId: string,
  eventName: string
): Promise<void> {
  const clientSnap = await db.collection('users').doc(clientId).get();
  const fcmToken = clientSnap.data()?.fcmToken as string | undefined;
  if (!fcmToken) return;

  try {
    await messaging.send({
      token: fcmToken,
      notification: { title, body },
      data: { rideId, event: eventName },
      android: {
        priority: 'high',
        notification: { channelId: RIDE_NOTIFICATION_CHANNEL_ID, priority: 'max' },
      },
    });
  } catch (error) {
    logger.error(`Échec envoi notification au client ${clientId}`, error);
  }
}

/** Notifie le client que son chauffeur arrive. */
export const onRideAccepted = onDocumentUpdated('rides/{rideId}', async (event) => {
  const change = event.data;
  if (!change) return;

  const before = change.before.data() as RideData;
  const after = change.after.data() as RideData;
  if (before.status === 'accepted' || after.status !== 'accepted') return;

  await notifyClient(
    after.clientId,
    'Chauffeur trouvé',
    `${after.driverName ?? 'Ton chauffeur'} arrive vers toi`,
    event.params.rideId,
    'ride_accepted'
  );
});

/** Notifie le client que sa course est terminée et lui demande de noter. */
export const onRideCompleted = onDocumentUpdated('rides/{rideId}', async (event) => {
  const change = event.data;
  if (!change) return;

  const before = change.before.data() as RideData;
  const after = change.after.data() as RideData;
  if (before.status === 'completed' || after.status !== 'completed') return;

  await notifyClient(after.clientId, 'Course terminée', 'Notez votre chauffeur', event.params.rideId, 'ride_completed');
});

/**
 * Passe en 'cancelled' les courses 'pending' de plus de 30 minutes, sinon
 * la liste chauffeur se remplit de courses mortes.
 */
export const expireOldRides = onSchedule('every 15 minutes', async () => {
  const cutoff = Timestamp.fromMillis(Date.now() - 30 * 60 * 1000);

  const staleRides = await db
    .collection('rides')
    .where('status', '==', 'pending')
    .where('createdAt', '<', cutoff)
    .get();

  if (staleRides.empty) return;

  const batch = db.batch();
  staleRides.forEach((doc) => {
    batch.update(doc.ref, { status: 'cancelled', cancelledAt: FieldValue.serverTimestamp() });
  });
  await batch.commit();
});
