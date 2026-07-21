import { EdgeError } from "./edge.ts";

const threadIdentifierPattern = /^[A-Za-z0-9._:-]+$/;
const objectNamePattern = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type OwnedChatMediaPath = {
  threadId: string;
  ownerId: string;
  objectName: string;
  storagePath: string;
};

/**
 * Accept only the canonical private chat-media namespace. Keeping this parser
 * independent from Storage metadata makes it usable before any privileged
 * lookup or deletion is attempted.
 */
export function validateOwnedChatMediaPath(
  threadIdValue: unknown,
  storagePathValue: unknown,
  authenticatedUserId: string,
): OwnedChatMediaPath {
  const threadId = String(threadIdValue ?? "").trim();
  const storagePath = String(storagePathValue ?? "").trim();
  const ownerId = authenticatedUserId.trim();

  if (
    threadId.length < 1 ||
    threadId.length > 200 ||
    !threadIdentifierPattern.test(threadId)
  ) {
    throw new EdgeError(400, "invalid_thread_id", "thread_id is invalid");
  }
  if (!uuidPattern.test(ownerId)) {
    throw new EdgeError(401, "invalid_session", "Authentication required");
  }
  if (storagePath.length < 1 || storagePath.length > 500) {
    throw new EdgeError(
      400,
      "invalid_storage_path",
      "storage_path is invalid",
    );
  }

  const parts = storagePath.split("/");
  if (
    parts.length !== 4 ||
    parts[0] !== "threads" ||
    parts[1] !== threadId ||
    parts[2] !== ownerId ||
    parts[3].length < 1 ||
    parts[3].length > 200 ||
    !objectNamePattern.test(parts[3]) ||
    parts[3] === "." ||
    parts[3] === ".."
  ) {
    throw new EdgeError(
      403,
      "storage_path_forbidden",
      "Only an owned chat-media object can be cleaned up",
    );
  }

  return {
    threadId,
    ownerId,
    objectName: parts[3],
    storagePath: `threads/${threadId}/${ownerId}/${parts[3]}`,
  };
}

export function isMissingChatMembersRelation(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const record = error as Record<string, unknown>;
  const code = String(record.code ?? "").toUpperCase();
  if (code === "42P01" || code === "PGRST205") return true;

  const message = String(record.message ?? "").toLowerCase();
  return message.includes("chat_thread_members") &&
    (message.includes("schema cache") || message.includes("does not exist"));
}
