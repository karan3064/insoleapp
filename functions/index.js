const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {setGlobalOptions} = require("firebase-functions/v2");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

admin.initializeApp();
setGlobalOptions({maxInstances: 10});

const geminiApiKey = defineSecret("GEMINI_API_KEY");

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
 * plain-language narrative via the Gemini API -- never given raw sensor
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
 *  - `firebase functions:secrets:set GEMINI_API_KEY` run once, with a free
 *    Gemini API key (aistudio.google.com -- no payment method needed) --
 *    stored in Secret Manager, never in this source file or any committed
 *    env file.
 *  - `firebase deploy --only functions`.
 *
 * Callable only by a signed-in user (`onCall` verifies the Firebase Auth ID
 * token automatically); the API key never reaches the client.
 */
exports.generateSessionNarrative = onCall(
    {secrets: [geminiApiKey]},
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

      const narrative = await callGemini({
        contents: [{role: "user", parts: [{text: prompt}]}],
        maxOutputTokens: 400,
      });

      return {narrative};
    },
);

/**
 * Lets a patient/caregiver ask follow-up questions about a session they're
 * already viewing ("why are my numbers elevated", "what should I do") --
 * same session-metrics context as `generateSessionNarrative`, plus the
 * running conversation so far (stateless on this end: the client resends
 * the full transcript each turn, same as `generateSessionNarrative` is
 * given the session's numbers fresh each call).
 *
 * The system prompt is the one place in this feature doing real safety
 * work: explicit, repeated instructions not to diagnose or prescribe
 * treatment, and to defer medical decisions to the patient's own
 * clinician -- a patient asking "what should I do" here is exactly the
 * question an LLM is most tempted to over-answer.
 */
exports.chatAboutSession = onCall(
    {secrets: [geminiApiKey]},
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Sign in required.");
      }

      const metrics = request.data && request.data.metrics;
      if (!metrics || typeof metrics !== "object") {
        throw new HttpsError("invalid-argument", "metrics object is required.");
      }

      const messages = request.data.messages;
      if (!Array.isArray(messages) || messages.length === 0) {
        throw new HttpsError("invalid-argument", "messages array is required.");
      }
      // Caps both cost/abuse and prompt size -- a chat this long has long
      // since stopped being about one session's numbers anyway.
      if (messages.length > 20) {
        throw new HttpsError("invalid-argument", "Too many messages in this conversation.");
      }
      for (const m of messages) {
        if (!m || (m.role !== "user" && m.role !== "assistant") ||
            typeof m.content !== "string" || m.content.length === 0 ||
            m.content.length > 4000) {
          throw new HttpsError("invalid-argument", "Malformed message in conversation.");
        }
      }

      const system = buildChatSystemPrompt(
          metrics,
          request.data.recoverySummary,
          request.data.personalBaselineSummary,
          request.data.screeningBand,
      );

      const reply = await callGemini({
        systemInstruction: system,
        // Gemini's roles are "user"/"model", not "user"/"assistant".
        contents: messages.map((m) => ({
          role: m.role === "assistant" ? "model" : "user",
          parts: [{text: m.content}],
        })),
        maxOutputTokens: 500,
      });

      return {reply};
    },
);

/** POSTs to the Gemini `generateContent` API and returns the concatenated text content. */
async function callGemini({systemInstruction, contents, maxOutputTokens}) {
  const model = process.env.GEMINI_MODEL || "gemini-3.8-flash";
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent` +
    `?key=${geminiApiKey.value()}`;

  let response;
  try {
    response = await fetch(url, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        contents,
        ...(systemInstruction ? {systemInstruction: {parts: [{text: systemInstruction}]}} : {}),
        generationConfig: {maxOutputTokens},
      }),
    });
  } catch (e) {
    console.error("Gemini API request failed:", e);
    throw new HttpsError("unavailable", "Could not reach the narrative service.");
  }

  if (!response.ok) {
    const body = await response.text().catch(() => "");
    console.error(`Gemini API returned ${response.status}: ${body}`);
    throw new HttpsError("internal", "The narrative service returned an error.");
  }

  const json = await response.json();
  const text = ((json.candidates || [])[0]?.content?.parts || [])
      .map((part) => part.text || "")
      .join("\n")
      .trim();

  if (!text) {
    throw new HttpsError("internal", "The narrative service returned no text.");
  }

  return text;
}

/** Shared context block: this session's numbers plus this app's own already-computed findings. */
function sessionContextLines(metrics, recoverySummary, personalBaselineSummary, screeningBand) {
  const lines = [
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

  return lines;
}

/**
 * Builds the prompt sent to Gemini: the session's own numbers plus this
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
    ...sessionContextLines(metrics, recoverySummary, personalBaselineSummary, screeningBand),
  ];

  return lines.join("\n");
}

/**
 * System prompt for `chatAboutSession` -- same session-context block as
 * the narrative prompt, with guardrails aimed specifically at the
 * follow-up questions this is for ("why is this elevated", "what should I
 * do"): explain what the numbers and the app's own findings mean in plain
 * language, but never diagnose, never prescribe or rule out a specific
 * treatment/exercise, and always point a "what should I do" question back
 * to the patient's own clinician/physiotherapist rather than answering it
 * directly.
 */
function buildChatSystemPrompt(metrics, recoverySummary, personalBaselineSummary, screeningBand) {
  const lines = [
    "You are a gait-analysis assistant inside a smart-insole app called " +
    "NurvoSync, answering a patient or caregiver's follow-up questions " +
    "about one specific test session. You have only the data below -- do " +
    "not invent numbers or claim data you don't have.",
    "",
    "Rules, which apply to every reply in this conversation:",
    "- You may explain what a metric means and why the app's own findings " +
    "below say what they say (e.g. why a value counts as 'elevated' or " +
    "'asymmetric' relative to typical ranges or this patient's own history).",
    "- Never provide a diagnosis, never state or imply a medical condition, " +
    "and never prescribe, recommend, or rule out a specific treatment, " +
    "exercise, or medication change.",
    "- When asked what to do (e.g. 'what should I do', 'how do I fix this'), " +
    "say this is a question for their treating clinician or physiotherapist, " +
    "and you can help them prepare for that conversation (e.g. what to " +
    "mention), but you will not tell them what action to take.",
    "- If a question goes beyond what this session's data can answer, say so " +
    "plainly rather than guessing.",
    "- Keep replies short (2-5 sentences) and in plain language, not clinical " +
    "jargon.",
    "",
    ...sessionContextLines(metrics, recoverySummary, personalBaselineSummary, screeningBand),
  ];

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
