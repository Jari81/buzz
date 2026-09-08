import { KIND_ROLE_PROMPT } from "@/shared/constants/kinds";
import type { RelayEvent } from "@/shared/api/types";

export type RolePromptRole = "writer" | "review" | "host";

export type RolePrompt = {
  eventId: string;
  role: RolePromptRole;
  revision: number;
  prompt: string;
  sha256: string;
};

const roles = new Set<RolePromptRole>(["writer", "review", "host"]);
const sha256Pattern = /^[0-9a-f]{64}$/;

function roleCoordinate(event: RelayEvent): RolePromptRole | null {
  const dTags = event.tags.filter((tag) => tag.length === 2 && tag[0] === "d");
  if (dTags.length !== 1) return null;
  const role = dTags[0]?.[1];
  return role && roles.has(role as RolePromptRole)
    ? (role as RolePromptRole)
    : null;
}

function sha256(value: string): Promise<string> {
  return crypto.subtle
    .digest("SHA-256", new TextEncoder().encode(value))
    .then((digest) =>
      [...new Uint8Array(digest)]
        .map((byte) => byte.toString(16).padStart(2, "0"))
        .join(""),
    );
}

export async function parseRolePrompt(
  event: RelayEvent,
): Promise<RolePrompt | null> {
  if (event.kind !== KIND_ROLE_PROMPT) return null;
  const role = roleCoordinate(event);
  if (!role) return null;

  let payload: unknown;
  try {
    payload = JSON.parse(event.content);
  } catch {
    return null;
  }
  if (
    !payload ||
    typeof payload !== "object" ||
    Array.isArray(payload) ||
    Object.keys(payload).length !== 5 ||
    !["v", "role", "revision", "prompt", "sha256"].every((key) =>
      Object.hasOwn(payload, key),
    )
  ) {
    return null;
  }

  const {
    v,
    role: payloadRole,
    revision,
    prompt,
    sha256: digest,
  } = payload as {
    v: unknown;
    role: unknown;
    revision: unknown;
    prompt: unknown;
    sha256: unknown;
  };
  if (
    v !== 1 ||
    payloadRole !== role ||
    !Number.isSafeInteger(revision) ||
    typeof revision !== "number" ||
    revision <= 0 ||
    typeof prompt !== "string" ||
    prompt.length === 0 ||
    typeof digest !== "string" ||
    !sha256Pattern.test(digest) ||
    (await sha256(prompt)) !== digest
  ) {
    return null;
  }

  return { eventId: event.id, role, revision, prompt, sha256: digest };
}
