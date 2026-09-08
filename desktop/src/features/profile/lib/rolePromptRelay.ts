import { relayClient } from "@/shared/api/relayClient";
import { signRelayEvent } from "@/shared/api/tauri";
import { KIND_ROLE_PROMPT } from "@/shared/constants/kinds";
import {
  parseRolePrompt,
  type RolePrompt,
  type RolePromptRole,
} from "@/features/profile/lib/rolePrompt";

export async function fetchRolePrompt(
  owner: string,
  role: RolePromptRole,
): Promise<RolePrompt | null> {
  const events = await relayClient.fetchEvents({
    authors: [owner],
    kinds: [KIND_ROLE_PROMPT],
    "#d": [role],
    limit: 2,
  });
  if (events.length !== 1) return null;
  return parseRolePrompt(events[0]);
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

export function canEditRolePrompt(isCurrentUserOwner: boolean): boolean {
  return isCurrentUserOwner;
}

export async function buildRolePromptDraft({
  prompt,
  revision,
  role,
}: {
  prompt: string;
  revision: number;
  role: RolePromptRole;
}) {
  if (!prompt.trim()) throw new Error("Role prompt must not be empty.");
  const payload = {
    v: 1,
    role,
    revision: revision + 1,
    prompt,
    sha256: await sha256(prompt),
  };
  return { payload, tags: [["d", role]] };
}

export async function publishRolePrompt({
  owner,
  prompt,
  revision,
  role,
}: {
  owner: string;
  prompt: string;
  revision: number;
  role: RolePromptRole;
}): Promise<RolePrompt | null> {
  const draft = await buildRolePromptDraft({ prompt, revision, role });
  const event = await signRelayEvent({
    kind: KIND_ROLE_PROMPT,
    content: JSON.stringify(draft.payload),
    tags: draft.tags,
  });
  await relayClient.publishEvent(
    event,
    "Timed out publishing role prompt.",
    "Failed to publish role prompt.",
  );
  const readback = await fetchRolePrompt(owner, role);
  return readback?.eventId === event.id &&
    readback.revision === draft.payload.revision
    ? readback
    : null;
}
