/**
 * BUZZ-DESKTOP-003: merge thread-scoped bot typing pubkeys with the
 * channel-level working set (observer-derived turns + typing) for the
 * thread composer activity bar. Observer frames carry channel scope only
 * (no threadHeadId), so a thread previously rendered bot typing at best;
 * merging the channel-level working set lets threads show the same
 * activity bar as the main composer. Case-insensitive dedupe preserves
 * first-seen order.
 */
export function mergeThreadComposerActivityPubkeys(
  threadTypingPubkeys: readonly string[],
  channelWorkingPubkeys: readonly string[],
): string[] {
  return [...threadTypingPubkeys, ...channelWorkingPubkeys].filter(
    (pubkey, index, all) =>
      all.findIndex(
        (candidate) => candidate.toLowerCase() === pubkey.toLowerCase(),
      ) === index,
  );
}
