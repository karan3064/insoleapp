const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {setGlobalOptions} = require("firebase-functions/v2");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

admin.initializeApp();
setGlobalOptions({maxInstances: 10});

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

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
      const patientName = await patientDisplayName(uid);
      const distanceMeters = Math.round(alert.distanceMeters || 0);

      const subject = `${patientName} has left their safe zone`;
      const body =
        `${patientName} moved ${distanceMeters}m outside their configured ` +
        "safe zone.\n\n" +
        `Location: https://www.google.com/maps?q=${alert.latitude},${alert.longitude}\n\n` +
        "This is an automated alert from NurvoSync. It is not a diagnosis " +
        "and does not replace direct supervision.";

      await notifyFamilyContacts(uid, subject, body);
    },
);

/**
 * Fires when the app records a completed Freezing-of-Gait episode (see
 * `GeofenceService.recordFogEvent`, written by `FreezeIndexDetector` on
 * the client). Same delivery path as a geofence breach: push + email to
 * every joined family contact.
 *
 * This is a real-time signal-processing detection (frequency-domain
 * freeze-index analysis of the insole pressure signal), not a medical
 * diagnosis -- the alert text below says so explicitly.
 */
exports.onFogAlertCreated = onDocumentCreated(
    "users/{uid}/fogAlerts/{alertId}",
    async (event) => {
      const snapshot = event.data;
      if (!snapshot) return;

      const uid = event.params.uid;
      const alert = snapshot.data();
      const patientName = await patientDisplayName(uid);
      const durationSec = ((alert.durationMs || 0) / 1000).toFixed(1);

      const subject = `${patientName} may have had a freezing-of-gait episode`;
      const body =
        `A ${durationSec}s episode with gait-freezing signal characteristics ` +
        `was detected during ${patientName}'s insole session.\n\n` +
        "This is an automated signal-processing alert from NurvoSync, not a " +
        "diagnosis -- please check on them.";

      await notifyFamilyContacts(uid, subject, body);
    },
);

/**
 * Turns one session's already-computed gait metrics into a short,
 * plain-language narrative via the Claude API -- never given raw sensor
 * frames, only the small set of numbers `RecordSummary`/`ClinicalGaitReport`
 * already compute on the client (see `AiNarrativeService` on the client for
 * exactly what's sent). This is a narration layer on top of the app's own
 * trained/rule-based analysis (`GaitScreeningModel`, `PersonalBaselineModel`,
 * `RecoveryAnalysis`), not a replacement for it -- the LLM is never asked to
 * invent a clinical judgment of its own from the raw numbers, only to
 * narrate the judgments those already made.
 *
 * Requires:
 *  - This project on the Blaze plan (external network calls aren't allowed
 *    on Spark, same as every other Cloud Function here).
 *  - `firebase functions:secrets:set ANTHROPIC_API_KEY` run once, with a
 *    real Anthropic API key (console.anthropic.com) -- stored in Secret
 *    Manager, never in this source file or any committed env file.
 *  - `firebase deploy --only functions`.
 *
 * Callable only by a signed-in user (`onCall` verifies the Firebase Auth ID
 * token automatically); the API key never reaches the client.
 */
exports.generateSessionNarrative = onCall(
    {secrets: [anthropicApiKey]},
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Sign in required.");
      }

      const metrics = request.data && request.data.metrics;
      if (!metrics || typeof metrics !== "object") {
        throw new HttpsError("invalid-argument", "metrics object is required.");
      }

      const prompt = buildNarrativePrompt(
          metrics,
          request.data.recoverySummary,
          request.data.personalBaselineSummary,
          request.data.screeningBand,
      );

      const model = process.env.ANTHROPIC_MODEL || "claude-sonnet-5-5";

      let response;
      try {
        response = await fetch("https://api.anthropic.com/v1/messages", {
          method: "POST",
          headers: {
            "content-type": "application/json",
            "x-api-key": anthropicApiKey.value(),
            "anthropic-version": "2023-06-01",
          },
          body: JSON.stringify({
            model,
            max_tokens: 400,
            messages: [{role: "user", content: prompt}],
          }),
        });
      } catch (e) {
        console.error("Anthropic API request failed:", e);
        throw new HttpsError("unavailable", "Could not reach the narrative service.");
      }

      if (!response.ok) {
        const body = await response.text().catch(() => "");
        console.error(`Anthropic API returned ${response.status}: ${body}`);
        throw new HttpsError("internal", "The narrative service returned an error.");
      }

      const json = await response.json();
      const narrative = (json.content || [])
          .filter((block) => block.type === "text")
          .map((block) => block.text)
          .join("\n")
          .trim();

      if (!narrative) {
        throw new HttpsError("internal", "The narrative service returned no text.");
      }

      return {narrative};
    },
);

/**
 * Builds the prompt sent to Claude: the session's own numbers plus this
 * app's own already-computed findings (recovery trend, personal-baseline
 * deviation, screening band), with explicit instructions not to add any
 * diagnosis or claim beyond what those numbers say.
 */
function buildNarrativePrompt(metrics, recoverySummary, personalBaselineSummary, screeningBand) {
  const lines = [
    "You are writing a short plain-language summary of one gait-analysis " +
    "session for a patient or their caregiver, using a smart-insole app " +
    "called NurvoSync. Use only the data below -- do not invent numbers, " +
    "do not add a diagnosis or risk claim beyond what's stated, and do not " +
    "recommend any treatment. If a value is missing, simply don't mention " +
    "it. Write 2-4 short sentences, warm but clinical in tone.",
    "",
    "Session metrics:",
    JSON.stringify(metrics, null, 2),
  ];

  if (recoverySummary) {
    lines.push("", "Recovery trend (already computed by the app):", recoverySummary);
  }
  if (personalBaselineSummary) {
    lines.push("", "Comparison to this patient's own baseline (already computed by the app):",
        personalBaselineSummary);
  }
  if (screeningBand) {
    lines.push("", `Gait screening signal (already computed by the app): ${screeningBand}`);
  }

  return lines.join("\n");
}

/** Looks up the patient's display name, falling back to a generic label. */
async function patientDisplayName(uid) {
  const profileSnap = await admin.firestore().collection("users").doc(uid).get();
  const profile = profileSnap.data() || {};
  return profile.displayName || "The person you're monitoring";
}

/** Pushes + emails every joined family contact for this patient. */
async function notifyFamilyContacts(uid, subject, body) {
  const contactsSnap = await admin.firestore()
      .collection("users").doc(uid).collection("familyContacts").get();
  if (contactsSnap.empty) return;

  const tokens = contactsSnap.docs
      .map((d) => d.data().fcmToken)
      .filter((t) => typeof t === "string" && t.length > 0);

  const sendPush = tokens.length ?
    admin.messaging().sendEachForMulticast({
      tokens,
      notification: {title: subject, body},
    }).catch((e) => console.error("push failed:", e)) :
    Promise.resolve();

  const sendEmails = Promise.all(
      contactsSnap.docs.map((d) => {
        const email = d.data().email;
        if (!email) return Promise.resolve();
        return sendEmail(email, subject, body)
            .catch((e) => console.error(`email to ${email} failed:`, e));
      }),
  );

  await Promise.all([sendPush, sendEmails]);
}

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
