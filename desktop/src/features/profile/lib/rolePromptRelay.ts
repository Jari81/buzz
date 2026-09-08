import { relayClient } from "@/shared/api/relayClient";
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
