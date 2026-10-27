import { createHash, timingSafeEqual } from "node:crypto";

export function receiptHash(receipt: unknown): string {
  if (typeof receipt !== "string" || !/^[A-Za-z0-9_-]{43}$/.test(receipt)) {
    throw new Error("invalid-receipt");
  }
  return createHash("sha256").update(receipt).digest("hex");
}

export function sameReceipt(a: string, b: string): boolean {
  return a.length === b.length && timingSafeEqual(Buffer.from(a), Buffer.from(b));
}

export type DeletionStage = "queued" | "firestore" | "auth" | "complete" | "failed";
export function canClaimDeletion(status: unknown, leaseUntil: number, now: number): boolean {
  if (status === "complete") return false;
  if (!["queued", "firestore", "auth", "failed"].includes(String(status))) {
    throw new Error("invalid-job-stage");
  }
  if (leaseUntil > now) throw new Error("job-already-running");
  return true;
}
export interface DeletionEffects {
  removeWallet(): Promise<void>;
  removeAuth(): Promise<void>;
  stage(value: DeletionStage): Promise<void>;
}

export async function executeDeletion(effects: DeletionEffects): Promise<void> {
  await effects.stage("firestore");
  await effects.removeWallet();
  await effects.stage("auth");
  await effects.removeAuth();
  await effects.stage("complete");
}
