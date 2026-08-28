import * as React from "react";

import {
  getMentionableAgentPubkeys,
  isAgentMentionChannelType,
} from "@/features/agents/lib/agentAutocompleteEligibility";
import type {
  ChannelMember,
  ChannelType,
  RelayAgent,
} from "@/shared/api/types";
import { normalizePubkey } from "@/shared/lib/pubkey";

export function useMentionAgentEligibility({
  channelId,
  channelType,
  currentPubkey,
  managedAgentPubkeys,
  members,
  membersError,
  membersFetching,
  relayAgents,
  sharedChannelIds,
}: {
  channelId: string | null;
  channelType?: ChannelType | null;
  currentPubkey: string | null;
  managedAgentPubkeys: ReadonlySet<string>;
  members: ChannelMember[] | undefined;
  membersError: unknown;
  membersFetching: boolean;
  relayAgents: readonly RelayAgent[] | undefined;
  sharedChannelIds: ReadonlySet<string>;
}) {
  const mentionChannelId = isAgentMentionChannelType(channelType)
    ? channelId
    : null;
  const memberPubkeys = React.useMemo(
    () =>
      new Set(
        members !== undefined && membersError === null && !membersFetching
          ? members.map((member) => normalizePubkey(member.pubkey))
          : [],
      ),
    [members, membersError, membersFetching],
  );
  const mentionableAgentPubkeys = React.useMemo(
    () =>
      getMentionableAgentPubkeys({
        currentPubkey,
        eligibilityScope: mentionChannelId
          ? { type: "channel", channelId: mentionChannelId, memberPubkeys }
          : { type: "managed-only" },
        managedAgentPubkeys,
        relayAgents,
        sharedChannelIds,
      }),
    [
      currentPubkey,
      managedAgentPubkeys,
      memberPubkeys,
      mentionChannelId,
      relayAgents,
      sharedChannelIds,
    ],
  );

  return { memberPubkeys, mentionableAgentPubkeys, mentionChannelId };
}
