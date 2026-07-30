/**
 * Usage ponctuel, à exécuter par toi-même en local — jamais depuis l'app :
 *
 *   cd scripts
 *   npm install firebase-admin
 *   GOOGLE_APPLICATION_CREDENTIALS=/chemin/vers/serviceAccountKey.json node set-admin-claim.js <uid>
 *
 * La clé de compte de service se télécharge dans la console Firebase :
 * Paramètres du projet > Comptes de service > Générer une nouvelle clé privée.
 * NE JAMAIS committer ce fichier (voir .gitignore : serviceAccountKey*.json).
 *
 * L'utilisateur ciblé doit se déconnecter/reconnecter (ou rafraîchir son
 * token) pour que le custom claim admin:true apparaisse dans son ID token.
 */
const admin = require('firebase-admin');

const uid = process.argv[2];
if (!uid) {
  console.error('Usage: node set-admin-claim.js <uid>');
  process.exit(1);
}

admin.initializeApp({ credential: admin.credential.applicationDefault() });

admin
  .auth()
  .setCustomUserClaims(uid, { admin: true })
  .then(() => {
    console.log(`Claim admin:true posé sur ${uid}.`);
    process.exit(0);
  })
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
