const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');

initializeApp();
const db = getFirestore();

function assertAdmin(request) {
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError('permission-denied', 'Réservé aux administrateurs.');
  }
}

function requireDriverId(data) {
  if (!data || typeof data.driverId !== 'string' || data.driverId.length === 0) {
    throw new HttpsError('invalid-argument', 'driverId manquant.');
  }
  return data.driverId;
}

/**
 * Seule fonction autorisée à faire passer un chauffeur à 'approved'.
 * firestore.rules verrouille users/{uid}.verificationStatus contre toute
 * écriture depuis l'app — ce callable, exécuté avec l'Admin SDK, est le
 * seul chemin qui puisse le changer.
 */
exports.approveDriver = onCall(async (request) => {
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
exports.rejectDriver = onCall(async (request) => {
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
