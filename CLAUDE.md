# Sira Transport

## Produit

Sira Transport met en relation, dans une ville d'Afrique de l'Ouest (Bamako
en premier), des **clients** (envoi de colis ou demande de passager) et des
**chauffeurs** (moto-taxi ou taxi voiture).

Principes non négociables du produit :
- **Pas de GPS, pas de carte.** La localisation se fait par **quartier +
  repère parlé** ("Kalabancoro, près du terrain de foot"). C'est un choix
  produit volontaire (coût data, APK plus léger, adapté aux rues sans nom/
  numéro) — voir `design/maquette.html`, section "La question de la carte".
- **Le prix est négocié entre client et chauffeur, toujours en FCFA**, jamais
  calculé automatiquement (pas de distance connue puisqu'il n'y a pas de
  carte).
- Le paiement de la course se fait **de la main à la main** ; l'app ne touche
  pas à l'argent de la course elle-même (seul un futur crédit prépayé
  chauffeur passera par mobile money — voir maquette, écran V2).
- Cycle d'une course en 5 états : `pending` → (notification chauffeurs) →
  `accepted` → `completed`, avec une branche `cancelled`.

## Maquette de référence — À LIRE avant de créer ou modifier un écran

`design/maquette.html` est la référence visuelle et textuelle du produit
fini (12 écrans : C1-C6 côté client, D1-D4 + P1 + V2 côté chauffeur).

**Avant de créer ou de modifier un écran, ouvre et lis ce fichier** pour
l'écran concerné, et respecte :
- la **mise en page** (structure des cartes, hiérarchie de l'information),
- les **couleurs exactes** : encre `#0E1420`, indigo `#1B2A4A` /
  `#2C4271`, safran `#F5B301` / `#FFF0C2`, vert `#0F7A5A`,
  brique `#B03A2E`, écran `#F5F5F2`, gris `#71767F`,
- les **textes** (libellés de boutons, messages, ton) donnés dans la
  maquette — ne pas les réinventer,
- le fait que la maquette est en HTML statique de présentation (desktop,
  "téléphones" simulés) : elle sert de guide de design, pas de gabarit
  Flutter à copier littéralement. Adapter en Material 3 idiomatique tout en
  gardant palette/texte/hiérarchie fidèles.

Les écrans existants (login/register/profile/client_home/create_ride/
driver_dashboard) utilisent encore le thème Material 3 par défaut
(`ColorScheme.fromSeed(seedColor: Colors.green)`) et **pas** la palette de la
maquette — écart connu, à corriger progressivement, jamais à l'aveugle sur
un écran non demandé.

## Conventions de code

- **Material 3** partout (`useMaterial3: true`, déjà activé dans
  `main.dart`). Étendre le thème plutôt que hardcoder des couleurs dans les
  widgets, une fois la palette de la maquette adoptée.
- **Architecture par feature** : `lib/features/<feature>/{models,services,
  screens}/`. Ne pas créer de dossier `lib/widgets/` ou `lib/utils/`
  fourre-tout — un composant partagé reste dans la feature qui l'utilise
  tant qu'une deuxième feature n'en a pas besoin.
- **Un service par domaine** (`AuthService`, `RideService`, ...). Toute
  logique métier et tout appel Firebase (Auth/Firestore) passe par un
  service, jamais d'appel direct à `FirebaseFirestore.instance` ou
  `FirebaseAuth.instance` depuis un widget.
- **Jamais de logique métier dans un widget.** Un `StatefulWidget`
  orchestre l'UI et appelle un service ; il ne décide pas des règles
  (transitions de statut, validation de montant, calculs).
- Modèles (`UserModel`, `RideModel`) : immuables, avec `fromMap`/`toMap`
  explicites — garder ce pattern pour tout nouveau modèle.
- Nommage et commentaires : code et UI en français (cohérent avec
  l'existant), noms de champs Firestore en anglais (cohérent avec le schéma
  déjà en place, voir `firestore.rules`).

## Règles absolues

- **NE JAMAIS assouplir `firestore.rules` pour faire disparaître une
  erreur.** Si une règle bloque une opération, corriger le modèle de
  données, le code client, ou écrire une règle plus précise et toujours
  aussi stricte — jamais élargir `allow read, write: if ...` pour
  contourner le problème.
- **Tous les montants en FCFA sont des `int`, jamais des `double`.** FCFA
  n'a pas de sous-unité ; un prix, un solde, un gain est toujours un entier
  (actuellement `RideModel.offeredPrice` est un `double` — bug connu à
  corriger, ne pas reproduire ce pattern ailleurs).
- **Toutes les dates/horodatages Firestore viennent de
  `FieldValue.serverTimestamp()`**, jamais de `DateTime.now()` construit
  côté client (actuellement `createRideRequest`/`RideModel.createdAt`
  utilisent `DateTime.now()` côté client — bug connu à corriger).
- **Ne jamais modifier un fichier en dehors du périmètre explicitement
  demandé.** Un correctif ciblé ne doit pas entraîner de renommage, de
  reformatage ou de "nettoyage" de fichiers non concernés par la tâche.

## Commandes utiles

```bash
flutter pub get              # installer les dépendances
flutter analyze               # vérifier le code (lint + erreurs) — à faire après chaque changement
firebase deploy --only firestore   # déployer firestore.rules / firestore.indexes.json
```

**Ne jamais lancer `flutter run`, `flutter build apk`, ou tout autre build/
compilation en local** : la machine de dev n'est pas assez puissante pour
ça. La compilation de l'APK se fait automatiquement dans GitHub Actions
(`.github/workflows/build_apk.yml`) à chaque push sur `main` (le workflow
fait déjà `flutter analyze` puis `flutter build apk --release`). Pour
valider un changement, se limiter à `flutter analyze` en local et laisser
la CI GitHub faire le reste après push.
