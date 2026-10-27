import { randomUUID } from "node:crypto";
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getFunctions } from "firebase-admin/functions";
import { onRequest } from "firebase-functions/v2/https";
import { onTaskDispatched } from "firebase-functions/v2/tasks";
import { logger } from "firebase-functions";
import { canClaimDeletion, executeDeletion, receiptHash, sameReceipt } from "./deletion-job.js";

initializeApp();
const db = getFirestore();
const region = process.env.FUNCTIONS_REGION ||
  (process.env.FUNCTIONS_EMULATOR === "true" ? "us-central1" : undefined);
if (!region) throw new Error("FUNCTIONS_REGION must be configured before deployment.");
const cors = process.env.FUNCTIONS_EMULATOR === "true"
  ? true : (process.env.APP_ORIGINS ?? "").split(",").filter(Boolean);
function serviceIdentity(key: string): string | undefined {
  const identity = process.env[key];
  const isolated = process.env.FUNCTIONS_EMULATOR === "true" &&
    process.env.GCLOUD_PROJECT?.startsWith("demo-");
  if (!identity && !isolated) throw new Error(`${key} must be configured before deployment.`);
  return identity;
}
const requestIdentity = serviceIdentity("FUNCTIONS_REQUEST_SERVICE_ACCOUNT");
const statusIdentity = serviceIdentity("FUNCTIONS_STATUS_SERVICE_ACCOUNT");
const workerIdentity = serviceIdentity("FUNCTIONS_WORKER_SERVICE_ACCOUNT");
const jobs = db.collection("accountDeletionJobs");
const allowedUid = (uid: unknown): uid is string =>
  typeof uid === "string" && uid.length > 0 && uid.length <= 128 && !uid.includes("/");

export const requestAccountDeletion = onRequest(
  { region, cors, maxInstances: 5, serviceAccount: requestIdentity },
  async (request, response) => {
    if (request.method !== "POST") { response.sendStatus(405); return; }
    if (request.rawBody.length > 4096) { response.sendStatus(413); return; }
    try {
      const token = request.headers.authorization?.match(/^Bearer (.+)$/)?.[1];
      if (!token) { response.status(401).json({ error: "authentication-required" }); return; }
      const auth = await getAuth().verifyIdToken(token, true);
      if (!allowedUid(auth.uid) || Date.now() / 1000 - auth.auth_time > 300) {
        response.status(401).json({ error: "recent-authentication-required" }); return;
      }
      const hash = receiptHash(request.body?.receipt);
      const ref = jobs.doc(auth.uid);
      const complete = await db.runTransaction(async (transaction) => {
        const existing = await transaction.get(ref);
        if (existing.exists) {
          if (!sameReceipt(String(existing.get("receiptHash")), hash)) {
            throw new Error("deletion-already-requested");
          }
          if (existing.get("status") === "failed") {
            transaction.update(ref, { status: "queued", updatedAt: Timestamp.now() });
          }
          return existing.get("status") === "complete";
        }
        transaction.create(ref, {
          uid: auth.uid, receiptHash: hash, status: "queued", attempts: 0,
          requestedAt: Timestamp.now(), updatedAt: Timestamp.now(),
        });
        return false;
      });
      if (!complete) {
        if (process.env.FUNCTIONS_EMULATOR === "true" &&
            (!process.env.GCLOUD_PROJECT?.startsWith("demo-") ||
             !process.env.CLOUD_TASKS_EMULATOR_HOST)) {
          throw new Error("isolated-task-emulator-required");
        }
        await getFunctions().taskQueue(
          `locations/${region}/functions/deleteAccountWorker`,
        ).enqueue({ uid: auth.uid });
      }
      response.status(202).json({ status: complete ? "complete" : "queued" });
    } catch (error) {
      const code = error && typeof error === "object" && "code" in error
        ? String(error.code) : error instanceof Error &&
          ["deletion-already-requested", "invalid-receipt"].includes(error.message)
          ? error.message : "request-failed";
      logger.error("Account deletion request failed", { code });
      const conflict = code === "deletion-already-requested";
      response.status(conflict ? 409 : code.startsWith("auth/") ? 401 : code === "invalid-receipt" ? 400 : 503)
        .json({ error: conflict ? code : "deletion-request-failed" });
    }
  },
);

export const accountDeletionStatus = onRequest(
  { region, cors, maxInstances: 5, serviceAccount: statusIdentity },
  async (request, response) => {
    if (request.method !== "POST") { response.sendStatus(405); return; }
    if (request.rawBody.length > 4096) { response.sendStatus(413); return; }
    try {
      const hash = receiptHash(request.body?.receipt);
      const matches = await jobs.where("receiptHash", "==", hash).limit(1).get();
      const job = matches.docs[0];
      if (!job || !sameReceipt(String(job.get("receiptHash")), hash)) {
        response.status(404).json({ error: "operation-not-found" }); return;
      }
      response.json({ status: job.get("status"), remoteComplete: job.get("status") === "complete" });
    } catch (error) {
      logger.warn("Deletion status unavailable", {
        code: error instanceof Error ? error.message : "status-failed",
      });
      response.status(400).json({ error: "status-unavailable" });
    }
  },
);

export const deleteAccountWorker = onTaskDispatched(
  { region, timeoutSeconds: 540, serviceAccount: workerIdentity,
    retryConfig: { maxAttempts: 8, minBackoffSeconds: 600 },
    rateLimits: { maxConcurrentDispatches: 2 } },
  async (request) => {
    const uid: unknown = request.data?.uid;
    if (!allowedUid(uid)) throw new Error("invalid-job");
    const ref = jobs.doc(uid);
    const lease = randomUUID();
    const claimed = await db.runTransaction(async (transaction) => {
      const snap = await transaction.get(ref);
      if (!snap.exists) return false;
      if (snap.get("uid") !== uid) throw new Error("job-owner-mismatch");
      const until: unknown = snap.get("leaseUntil");
      if (!canClaimDeletion(snap.get("status"),
        until instanceof Timestamp ? until.toMillis() : 0, Date.now())) return false;
      transaction.update(ref, {
        lease, leaseUntil: Timestamp.fromMillis(Date.now() + 600000),
        attempts: Number(snap.get("attempts") ?? 0) + 1, updatedAt: Timestamp.now(),
      });
      return true;
    });
    if (!claimed) return;
    const stage = async (value: string) => {
      await db.runTransaction(async (transaction) => {
        const snap = await transaction.get(ref);
        if (snap.get("lease") !== lease) throw new Error("job-lease-lost");
        transaction.update(ref, { status: value, updatedAt: Timestamp.now() });
      });
    };
    try {
      await executeDeletion({
        stage,
        removeWallet: () => db.recursiveDelete(db.collection("users").doc(uid)),
        removeAuth: async () => {
          try { await getAuth().deleteUser(uid); }
          catch (error) {
            if (!(error && typeof error === "object" && "code" in error &&
                error.code === "auth/user-not-found")) throw error;
          }
        },
      });
      await ref.update({ leaseUntil: Timestamp.fromMillis(0), lastErrorCode: null });
    } catch (error) {
      logger.error("Account deletion task failed", {
        code: error && typeof error === "object" && "code" in error
          ? String(error.code) : "worker-failed",
      });
      await stage("failed");
      await ref.update({ leaseUntil: Timestamp.fromMillis(0), lastErrorCode: "worker-failed" });
      throw error;
    }
  },
);
