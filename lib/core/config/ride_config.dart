/// Durée de vie d'une course en attente. Doit rester identique à la
/// durée codée dans firestore.rules (duration.value(30, 'm')).
const int kRideExpiryMinutes = 30;
