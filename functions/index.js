const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {setGlobalOptions} = require("firebase-functions/v2");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

admin.initializeApp();
setGlobalOptions({maxInstances: 10});

/**
 * Fires when the NurvoSync app records a safe-zone breach (see
 * `GeofenceService.recordBreach` on the client, written whenever
 * `GeofenceTracker` detects a session's GPS path exit a configured safe
 * zone). Looks up the patient's family contacts and notifies each one by
 * push (if they've joined via `JoinFamilyContactScreen`, which attaches an
 * FCM token) and by email.
 *
 * Requires, none of which this repo can set up for you:
 *  - The Firebase project on the Blaze (pay-as-you-go) plan -- Cloud
 *    Functions do not run on the free Spark plan.
 *  - `firebase deploy --only functions` run from this directory once, with
 *    the Firebase CLI logged into the `solesync-f7740` project.
 *  - SMTP credentials configured for this function (see `transport()`
 *    below) -- point them at whatever email provider you want to send
 *    through. No email actually sends until these are set; missing
 *    config just logs a warning and skips that recipient rather than
 *    throwing, so a push-only contact still gets notified.
 */
exports.onGeofenceAlertCreated = onDocumentCreated(
    "users/{uid}/geofenceAlerts/{alertId}",
    async (event) => {
      const snapshot = event.data;
      if (!snapshot) return;

      const uid = event.params.uid;
      const alert = snapshot.data();
      const db = admin.firestore();

      const [profileSnap, contactsSnap] = await Promise.all([
        db.collection("users").doc(uid).get(),
        db.collection("users").doc(uid).collection("familyContacts").get(),
      ]);

      if (contactsSnap.empty) return;

      const profile = profileSnap.data() || {};
      const patientName = profile.displayName || "The person you're monitoring";
      const distanceMeters = Math.round(alert.distanceMeters || 0);

      const subject = `${patientName} has left their safe zone`;
      const body =
        `${patientName} moved ${distanceMeters}m outside their configured ` +
        "safe zone.\n\n" +
        `Location: https://www.google.com/maps?q=${alert.latitude},${alert.longitude}\n\n` +
        "This is an automated alert from NurvoSync. It is not a diagnosis " +
        "and does not replace direct supervision.";

      const tokens = contactsSnap.docs
          .map((d) => d.data().fcmToken)
          .filter((t) => typeof t === "string" && t.length > 0);

      const sendPush = tokens.length ?
        admin.messaging().sendEachForMulticast({
          tokens,
          notification: {title: subject, body},
        }).catch((e) => console.error("geofence push failed:", e)) :
        Promise.resolve();

      const sendEmails = Promise.all(
          contactsSnap.docs.map((d) => {
            const email = d.data().email;
            if (!email) return Promise.resolve();
            return sendEmail(email, subject, body)
                .catch((e) => console.error(`geofence email to ${email} failed:`, e));
          }),
      );

      await Promise.all([sendPush, sendEmails]);
    },
);

let cachedTransport;

/** Lazily builds (and caches) the SMTP transport from env config. */
function transport() {
  if (cachedTransport) return cachedTransport;
  cachedTransport = nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port: Number(process.env.SMTP_PORT || 587),
    secure: process.env.SMTP_SECURE === "true",
    auth: {user: process.env.SMTP_USER, pass: process.env.SMTP_PASS},
  });
  return cachedTransport;
}

/** Sends one plain-text email, or logs+skips if SMTP isn't configured. */
function sendEmail(to, subject, text) {
  if (!process.env.SMTP_HOST) {
    console.warn(`SMTP_HOST not configured -- skipping email to ${to}`);
    return Promise.resolve();
  }
  return transport().sendMail({
    from: process.env.SMTP_FROM || process.env.SMTP_USER,
    to,
    subject,
    text,
  });
}
