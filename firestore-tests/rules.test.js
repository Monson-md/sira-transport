/**
 * Tests des règles firestore.rules, via @firebase/rules-unit-testing.
 *
 * À exécuter avec l'émulateur Firestore démarré (depuis la racine du repo,
 * pas depuis firestore-tests/) :
 *
 *   firebase emulators:exec --only firestore "npm --prefix firestore-tests test"
 *
 * (firebase emulators:exec démarre l'émulateur sur le port défini dans
 * firebase.json — 8080 — exécute la commande, puis l'arrête.)
 */
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const firebase = require('firebase/compat/app');
require('firebase/compat/firestore');

const serverTimestamp = () => firebase.firestore.FieldValue.serverTimestamp();

const CLIENT_A = 'client-a';
const CLIENT_B = 'client-b';
const DRIVER_PENDING = 'driver-pending';
const DRIVER_APPROVED_BAMAKO = 'driver-approved-bamako';
const DRIVER_APPROVED_ABIDJAN = 'driver-approved-abidjan';

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'sira-transport-test',
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, '../firestore.rules'), 'utf8'),
      host: 'localhost',
      port: 8080,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

async function seed(setupFn) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setupFn(context.firestore());
  });
}

function userDoc(overrides = {}) {
  return {
    uid: overrides.uid,
    name: 'Test User',
    phoneNumber: '+22370000000',
    role: 'client',
    country: 'Mali',
    city: 'Bamako',
    neighborhood: 'Kalabancoro',
    vehicleModel: null,
    rating: 5.0,
    ratingCount: 0,
    verificationStatus: 'approved',
    phoneVerified: false,
    ...overrides,
  };
}

function rideDoc(overrides = {}) {
  return {
    id: overrides.id || 'ride-1',
    clientId: CLIENT_A,
    clientName: 'Test User',
    clientPhone: '+22370000000',
    type: 'colis',
    departureNeighborhood: 'Kalabancoro',
    departureLandmark: 'près du terrain',
    arrivalNeighborhood: 'Badalabougou',
    arrivalLandmark: 'devant la pharmacie',
    offeredPrice: 1000,
    status: 'pending',
    driverId: null,
    driverName: null,
    driverPhone: null,
    vehicleType: 'moto',
    country: 'Mali',
    city: 'Bamako',
    platformFee: 0,
    createdAt: new Date(),
    acceptedAt: null,
    completedAt: null,
    cancelledAt: null,
    ...overrides,
  };
}

describe('users', () => {
  test("un client ne peut pas lire le profil d'un autre utilisateur", async () => {
    await seed(async (db) => {
      await db.collection('users').doc(CLIENT_B).set(userDoc({ uid: CLIENT_B }));
    });

    const clientA = testEnv.authenticatedContext(CLIENT_A).firestore();
    await assertFails(clientA.collection('users').doc(CLIENT_B).get());
  });

  test('un utilisateur ne peut pas modifier son propre role ni son rating', async () => {
    await seed(async (db) => {
      await db.collection('users').doc(CLIENT_A).set(userDoc({ uid: CLIENT_A }));
    });

    const clientA = testEnv.authenticatedContext(CLIENT_A).firestore();

    await assertFails(clientA.collection('users').doc(CLIENT_A).update({ role: 'driver_moto' }));
    await assertFails(clientA.collection('users').doc(CLIENT_A).update({ rating: 1.0 }));

    // Un champ ordinaire doit rester modifiable : la règle ne doit pas tout bloquer.
    await assertSucceeds(
      clientA.collection('users').doc(CLIENT_A).update({ neighborhood: 'ACI 2000' })
    );
  });
});

describe('rides — visibilité chauffeur', () => {
  test('un chauffeur non vérifié ne voit aucune course', async () => {
    await seed(async (db) => {
      await db.collection('users').doc(DRIVER_PENDING).set(
        userDoc({
          uid: DRIVER_PENDING,
          role: 'driver_moto',
          verificationStatus: 'pending',
          country: 'Mali',
          city: 'Bamako',
        })
      );
      await db.collection('rides').doc('ride-1').set(rideDoc());
    });

    const driver = testEnv.authenticatedContext(DRIVER_PENDING).firestore();
    await assertFails(
      driver
        .collection('rides')
        .where('status', '==', 'pending')
        .where('country', '==', 'Mali')
        .where('city', '==', 'Bamako')
        .get()
    );
  });

  test("un chauffeur d'une autre ville ne voit pas les courses", async () => {
    await seed(async (db) => {
      await db.collection('users').doc(DRIVER_APPROVED_ABIDJAN).set(
        userDoc({
          uid: DRIVER_APPROVED_ABIDJAN,
          role: 'driver_moto',
          verificationStatus: 'approved',
          country: "Côte d'Ivoire",
          city: 'Abidjan',
        })
      );
      await db.collection('rides').doc('ride-1').set(rideDoc());
    });

    const driver = testEnv.authenticatedContext(DRIVER_APPROVED_ABIDJAN).firestore();
    await assertFails(
      driver
        .collection('rides')
        .where('status', '==', 'pending')
        .where('country', '==', 'Mali')
        .where('city', '==', 'Bamako')
        .get()
    );
  });

  test('un chauffeur vérifié de la bonne ville voit les courses en attente', async () => {
    await seed(async (db) => {
      await db.collection('users').doc(DRIVER_APPROVED_BAMAKO).set(
        userDoc({
          uid: DRIVER_APPROVED_BAMAKO,
          role: 'driver_moto',
          verificationStatus: 'approved',
          country: 'Mali',
          city: 'Bamako',
        })
      );
      await db.collection('rides').doc('ride-1').set(rideDoc());
    });

    const driver = testEnv.authenticatedContext(DRIVER_APPROVED_BAMAKO).firestore();
    await assertSucceeds(
      driver
        .collection('rides')
        .where('status', '==', 'pending')
        .where('country', '==', 'Mali')
        .where('city', '==', 'Bamako')
        .get()
    );
  });
});

describe('rides — transitions de statut', () => {
  test('un client ne peut pas passer une course en completed', async () => {
    await seed(async (db) => {
      await db.collection('users').doc(CLIENT_A).set(userDoc({ uid: CLIENT_A }));
      await db.collection('rides').doc('ride-1').set(rideDoc({ clientId: CLIENT_A }));
    });

    const clientA = testEnv.authenticatedContext(CLIENT_A).firestore();
    await assertFails(clientA.collection('rides').doc('ride-1').update({ status: 'completed' }));
  });

  test('le chauffeur assigné peut terminer sa course acceptée', async () => {
    await seed(async (db) => {
      await db.collection('users').doc(DRIVER_APPROVED_BAMAKO).set(
        userDoc({
          uid: DRIVER_APPROVED_BAMAKO,
          role: 'driver_moto',
          verificationStatus: 'approved',
        })
      );
      await db.collection('rides').doc('ride-1').set(
        rideDoc({
          status: 'accepted',
          driverId: DRIVER_APPROVED_BAMAKO,
          driverName: 'Test User',
          driverPhone: '+22370000000',
        })
      );
    });

    const driver = testEnv.authenticatedContext(DRIVER_APPROVED_BAMAKO).firestore();
    await assertSucceeds(
      driver
        .collection('rides')
        .doc('ride-1')
        .update({ status: 'completed', completedAt: serverTimestamp() })
    );
  });
});
