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

// Le hook par défaut de Jest (5000 ms) est bien trop court pour
// initializeTestEnvironment() sur une machine chargée : la connexion à
// l'émulateur peut prendre plus de temps que ça sans que ce soit un
// problème réel (observé jusqu'à plus de 60s certaines fois).
jest.setTimeout(180000);

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

describe('rides — augmentation de l\'offre', () => {
  test('le client peut augmenter son offre tant que la course est pending', async () => {
    await seed(async (db) => {
      await db.collection('users').doc(CLIENT_A).set(userDoc({ uid: CLIENT_A }));
      await db.collection('rides').doc('ride-1').set(rideDoc({ clientId: CLIENT_A, offeredPrice: 1000 }));
    });

    const clientA = testEnv.authenticatedContext(CLIENT_A).firestore();
    await assertSucceeds(
      clientA.collection('rides').doc('ride-1').update({ offeredPrice: 1500 })
    );
  });

  test("le client ne peut pas baisser son offre", async () => {
    await seed(async (db) => {
      await db.collection('users').doc(CLIENT_A).set(userDoc({ uid: CLIENT_A }));
      await db.collection('rides').doc('ride-1').set(rideDoc({ clientId: CLIENT_A, offeredPrice: 1000 }));
    });

    const clientA = testEnv.authenticatedContext(CLIENT_A).firestore();
    await assertFails(
      clientA.collection('rides').doc('ride-1').update({ offeredPrice: 500 })
    );
  });

  test("le client ne peut pas augmenter l'offre d'une course déjà acceptée", async () => {
    await seed(async (db) => {
      await db.collection('users').doc(CLIENT_A).set(userDoc({ uid: CLIENT_A }));
      await db.collection('rides').doc('ride-1').set(
        rideDoc({
          clientId: CLIENT_A,
          offeredPrice: 1000,
          status: 'accepted',
          driverId: DRIVER_APPROVED_BAMAKO,
        })
      );
    });

    const clientA = testEnv.authenticatedContext(CLIENT_A).firestore();
    await assertFails(
      clientA.collection('rides').doc('ride-1').update({ offeredPrice: 1500 })
    );
  });

  test("le client ne peut pas modifier un autre champ en même temps que le prix", async () => {
    await seed(async (db) => {
      await db.collection('users').doc(CLIENT_A).set(userDoc({ uid: CLIENT_A }));
      await db.collection('rides').doc('ride-1').set(rideDoc({ clientId: CLIENT_A, offeredPrice: 1000 }));
    });

    const clientA = testEnv.authenticatedContext(CLIENT_A).firestore();
    await assertFails(
      clientA
        .collection('rides')
        .doc('ride-1')
        .update({ offeredPrice: 1500, arrivalNeighborhood: 'Ailleurs' })
    );
  });
});

describe('rides/{rideId}/messages', () => {
  async function seedAcceptedRide() {
    await seed(async (db) => {
      await db.collection('users').doc(CLIENT_A).set(userDoc({ uid: CLIENT_A }));
      await db.collection('users').doc(DRIVER_APPROVED_BAMAKO).set(
        userDoc({ uid: DRIVER_APPROVED_BAMAKO, role: 'driver_moto', verificationStatus: 'approved' })
      );
      await db.collection('rides').doc('ride-1').set(
        rideDoc({
          clientId: CLIENT_A,
          status: 'accepted',
          driverId: DRIVER_APPROVED_BAMAKO,
          driverName: 'Test User',
          driverPhone: '+22370000000',
        })
      );
    });
  }

  test('le client et le chauffeur de la course peuvent écrire un message une fois acceptée', async () => {
    await seedAcceptedRide();

    const clientA = testEnv.authenticatedContext(CLIENT_A).firestore();
    await assertSucceeds(
      clientA
        .collection('rides')
        .doc('ride-1')
        .collection('messages')
        .add({ senderId: CLIENT_A, text: 'Bonjour', createdAt: serverTimestamp() })
    );

    const driver = testEnv.authenticatedContext(DRIVER_APPROVED_BAMAKO).firestore();
    await assertSucceeds(
      driver
        .collection('rides')
        .doc('ride-1')
        .collection('messages')
        .add({ senderId: DRIVER_APPROVED_BAMAKO, text: "J'arrive", createdAt: serverTimestamp() })
    );
  });

  test("un tiers ne peut pas lire ni écrire dans le chat d'une course", async () => {
    await seedAcceptedRide();
    await seed(async (db) => {
      await db.collection('users').doc(CLIENT_B).set(userDoc({ uid: CLIENT_B }));
    });

    const clientB = testEnv.authenticatedContext(CLIENT_B).firestore();
    await assertFails(
      clientB
        .collection('rides')
        .doc('ride-1')
        .collection('messages')
        .add({ senderId: CLIENT_B, text: 'Intrus', createdAt: serverTimestamp() })
    );
    await assertFails(clientB.collection('rides').doc('ride-1').collection('messages').get());
  });

  test("le chat reste fermé tant que la course n'est pas acceptée", async () => {
    await seed(async (db) => {
      await db.collection('users').doc(CLIENT_A).set(userDoc({ uid: CLIENT_A }));
      await db.collection('rides').doc('ride-1').set(rideDoc({ clientId: CLIENT_A, status: 'pending' }));
    });

    const clientA = testEnv.authenticatedContext(CLIENT_A).firestore();
    await assertFails(
      clientA
        .collection('rides')
        .doc('ride-1')
        .collection('messages')
        .add({ senderId: CLIENT_A, text: 'Bonjour', createdAt: serverTimestamp() })
    );
  });
});

describe('ratings', () => {
  async function seedCompletedRide() {
    await seed(async (db) => {
      await db.collection('users').doc(CLIENT_A).set(userDoc({ uid: CLIENT_A }));
      await db.collection('users').doc(DRIVER_APPROVED_BAMAKO).set(
        userDoc({ uid: DRIVER_APPROVED_BAMAKO, role: 'driver_moto', verificationStatus: 'approved' })
      );
      await db.collection('rides').doc('ride-1').set(
        rideDoc({
          clientId: CLIENT_A,
          status: 'completed',
          driverId: DRIVER_APPROVED_BAMAKO,
          driverName: 'Test User',
          driverPhone: '+22370000000',
        })
      );
    });
  }

  test('le client de la course peut la noter une fois terminée', async () => {
    await seedCompletedRide();

    const clientA = testEnv.authenticatedContext(CLIENT_A).firestore();
    await assertSucceeds(
      clientA
        .collection('ratings')
        .doc('ride-1')
        .set({
          rideId: 'ride-1',
          clientId: CLIENT_A,
          driverId: DRIVER_APPROVED_BAMAKO,
          stars: 5,
          createdAt: serverTimestamp(),
        })
    );
  });

  test('le chauffeur ne peut pas noter sa propre course', async () => {
    await seedCompletedRide();

    const driver = testEnv.authenticatedContext(DRIVER_APPROVED_BAMAKO).firestore();
    await assertFails(
      driver
        .collection('ratings')
        .doc('ride-1')
        .set({
          rideId: 'ride-1',
          clientId: CLIENT_A,
          driverId: DRIVER_APPROVED_BAMAKO,
          stars: 5,
          createdAt: serverTimestamp(),
        })
    );
  });

  test('impossible de noter une course pas encore terminée', async () => {
    await seed(async (db) => {
      await db.collection('users').doc(CLIENT_A).set(userDoc({ uid: CLIENT_A }));
      await db.collection('rides').doc('ride-1').set(
        rideDoc({ clientId: CLIENT_A, status: 'accepted', driverId: DRIVER_APPROVED_BAMAKO })
      );
    });

    const clientA = testEnv.authenticatedContext(CLIENT_A).firestore();
    await assertFails(
      clientA
        .collection('ratings')
        .doc('ride-1')
        .set({
          rideId: 'ride-1',
          clientId: CLIENT_A,
          driverId: DRIVER_APPROVED_BAMAKO,
          stars: 5,
          createdAt: serverTimestamp(),
        })
    );
  });

  test('un avis ne peut pas être modifié une fois créé', async () => {
    await seedCompletedRide();
    await seed(async (db) => {
      await db.collection('ratings').doc('ride-1').set({
        rideId: 'ride-1',
        clientId: CLIENT_A,
        driverId: DRIVER_APPROVED_BAMAKO,
        stars: 5,
        createdAt: new Date(),
      });
    });

    const clientA = testEnv.authenticatedContext(CLIENT_A).firestore();
    await assertFails(clientA.collection('ratings').doc('ride-1').set({ stars: 1 }, { merge: true }));
  });
});

describe('rides/{rideId}/private (numéro du client)', () => {
  test("un chauffeur ne peut pas lire le numéro du client tant que la course est pending", async () => {
    await seed(async (db) => {
      await db.collection('users').doc(CLIENT_A).set(userDoc({ uid: CLIENT_A }));
      await db.collection('users').doc(DRIVER_APPROVED_BAMAKO).set(
        userDoc({ uid: DRIVER_APPROVED_BAMAKO, role: 'driver_moto', verificationStatus: 'approved' })
      );
      await db.collection('rides').doc('ride-1').set(rideDoc({ clientId: CLIENT_A, status: 'pending' }));
      await db
        .collection('rides')
        .doc('ride-1')
        .collection('private')
        .doc('contact')
        .set({ clientPhone: '+22370000000' });
    });

    const driver = testEnv.authenticatedContext(DRIVER_APPROVED_BAMAKO).firestore();
    await assertFails(
      driver.collection('rides').doc('ride-1').collection('private').doc('contact').get()
    );
  });

  test('le chauffeur assigné peut lire le numéro du client une fois la course acceptée', async () => {
    await seed(async (db) => {
      await db.collection('users').doc(CLIENT_A).set(userDoc({ uid: CLIENT_A }));
      await db.collection('users').doc(DRIVER_APPROVED_BAMAKO).set(
        userDoc({ uid: DRIVER_APPROVED_BAMAKO, role: 'driver_moto', verificationStatus: 'approved' })
      );
      await db.collection('rides').doc('ride-1').set(
        rideDoc({ clientId: CLIENT_A, status: 'accepted', driverId: DRIVER_APPROVED_BAMAKO })
      );
      await db
        .collection('rides')
        .doc('ride-1')
        .collection('private')
        .doc('contact')
        .set({ clientPhone: '+22370000000' });
    });

    const driver = testEnv.authenticatedContext(DRIVER_APPROVED_BAMAKO).firestore();
    await assertSucceeds(
      driver.collection('rides').doc('ride-1').collection('private').doc('contact').get()
    );
  });

  test("un autre chauffeur (qui n'a pas accepté) ne peut pas lire le numéro du client", async () => {
    await seed(async (db) => {
      await db.collection('users').doc(CLIENT_A).set(userDoc({ uid: CLIENT_A }));
      await db.collection('users').doc(DRIVER_APPROVED_BAMAKO).set(
        userDoc({ uid: DRIVER_APPROVED_BAMAKO, role: 'driver_moto', verificationStatus: 'approved' })
      );
      await db.collection('users').doc('driver-other-bamako').set(
        userDoc({ uid: 'driver-other-bamako', role: 'driver_moto', verificationStatus: 'approved' })
      );
      await db.collection('rides').doc('ride-1').set(
        rideDoc({ clientId: CLIENT_A, status: 'accepted', driverId: DRIVER_APPROVED_BAMAKO })
      );
      await db
        .collection('rides')
        .doc('ride-1')
        .collection('private')
        .doc('contact')
        .set({ clientPhone: '+22370000000' });
    });

    const otherDriver = testEnv.authenticatedContext('driver-other-bamako').firestore();
    await assertFails(
      otherDriver.collection('rides').doc('ride-1').collection('private').doc('contact').get()
    );
  });

  test('une course créée par le client ne peut pas contenir son numéro sur le document principal', async () => {
    await seed(async (db) => {
      await db.collection('users').doc(CLIENT_A).set(userDoc({ uid: CLIENT_A }));
    });

    const clientA = testEnv.authenticatedContext(CLIENT_A).firestore();
    await assertFails(
      clientA
        .collection('rides')
        .doc('ride-guarded')
        .set({
          ...rideDoc({ id: 'ride-guarded', clientId: CLIENT_A }),
          createdAt: serverTimestamp(),
        })
    );
  });
});

function placeDoc(overrides = {}) {
  return {
    label: 'Chez moi',
    icon: 'home',
    neighborhood: 'Kalabancoro',
    landmark: 'près du terrain de foot',
    city: 'Bamako',
    country: 'Mali',
    usageCount: 0,
    lastUsedAt: null,
    createdAt: new Date(),
    ...overrides,
  };
}

describe('users/{uid}/places', () => {
  test('le propriétaire peut créer, lire et supprimer un lieu', async () => {
    await seed(async (db) => {
      await db.collection('users').doc(CLIENT_A).set(userDoc({ uid: CLIENT_A }));
    });

    const clientA = testEnv.authenticatedContext(CLIENT_A).firestore();
    const placeRef = clientA.collection('users').doc(CLIENT_A).collection('places').doc();
    await assertSucceeds(placeRef.set(placeDoc()));
    await assertSucceeds(placeRef.get());
    await assertSucceeds(placeRef.delete());
  });

  test("un autre utilisateur ne peut ni lire ni créer un lieu qui n'est pas le sien", async () => {
    await seed(async (db) => {
      await db.collection('users').doc(CLIENT_A).set(userDoc({ uid: CLIENT_A }));
      await db.collection('users').doc(CLIENT_B).set(userDoc({ uid: CLIENT_B }));
      await db
        .collection('users')
        .doc(CLIENT_A)
        .collection('places')
        .doc('place-1')
        .set(placeDoc());
    });

    const clientB = testEnv.authenticatedContext(CLIENT_B).firestore();
    await assertFails(
      clientB.collection('users').doc(CLIENT_A).collection('places').doc('place-1').get()
    );
    await assertFails(
      clientB
        .collection('users')
        .doc(CLIENT_A)
        .collection('places')
        .doc('place-2')
        .set(placeDoc())
    );
  });

  test('un lieu sans quartier ou repère est refusé', async () => {
    await seed(async (db) => {
      await db.collection('users').doc(CLIENT_A).set(userDoc({ uid: CLIENT_A }));
    });

    const clientA = testEnv.authenticatedContext(CLIENT_A).firestore();
    await assertFails(
      clientA
        .collection('users')
        .doc(CLIENT_A)
        .collection('places')
        .doc('place-1')
        .set(placeDoc({ neighborhood: '' }))
    );
    await assertFails(
      clientA
        .collection('users')
        .doc(CLIENT_A)
        .collection('places')
        .doc('place-2')
        .set(placeDoc({ landmark: '' }))
    );
  });

  test('un label de plus de 30 caractères est refusé', async () => {
    await seed(async (db) => {
      await db.collection('users').doc(CLIENT_A).set(userDoc({ uid: CLIENT_A }));
    });

    const clientA = testEnv.authenticatedContext(CLIENT_A).firestore();
    await assertFails(
      clientA
        .collection('users')
        .doc(CLIENT_A)
        .collection('places')
        .doc('place-1')
        .set(placeDoc({ label: 'x'.repeat(31) }))
    );
  });
});

describe('users/{uid}/dismissedSuggestions', () => {
  test('le propriétaire peut lire et écrire, un tiers ne peut pas', async () => {
    await seed(async (db) => {
      await db.collection('users').doc(CLIENT_A).set(userDoc({ uid: CLIENT_A }));
      await db.collection('users').doc(CLIENT_B).set(userDoc({ uid: CLIENT_B }));
    });

    const clientA = testEnv.authenticatedContext(CLIENT_A).firestore();
    const docRef = clientA
      .collection('users')
      .doc(CLIENT_A)
      .collection('dismissedSuggestions')
      .doc('kalabancoro__pres_du_terrain');
    await assertSucceeds(
      docRef.set({
        neighborhood: 'Kalabancoro',
        landmark: 'près du terrain',
        dismissedAt: serverTimestamp(),
      })
    );
    await assertSucceeds(docRef.get());

    const clientB = testEnv.authenticatedContext(CLIENT_B).firestore();
    await assertFails(
      clientB
        .collection('users')
        .doc(CLIENT_A)
        .collection('dismissedSuggestions')
        .doc('kalabancoro__pres_du_terrain')
        .get()
    );
  });
});
