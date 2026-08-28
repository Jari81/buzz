import type { ControlResultFrame } from "@/shared/api/observerRelay";

/**
 * Resolve the outcome of a live `switch_model` across one or more channels.
 *
 * A live switch fires a `switch_model` frame per active channel and learns each
 * channel's result asynchronously over the observer relay. The fail-fast rule:
 * any failure result rejects the whole pick immediately; `other_turns_in_flight`
 * is surfaced as ambiguous; only `sent`, `switched`, and `turn_ending` count
 * toward success.
 * If the harness never replies, the fallback timeout resolves `"ok"` — the
 * override still rides the requeued/next session, we just can't confirm it
 * synchronously.
 *
 * The counting lives here, isolated from React and the relay so it can be unit
 * tested with synthetic frames and a fake clock. The caller injects the
 * relay subscription, the per-channel sends, and the timeout scheduler.
 */
export async function awaitLiveSwitchOutcome({
  channelCount,
  modelId,
  requestId,
  conversationRoot = null,
  subscribe,
  sendSwitches,
  scheduleTimeout,
}: {
  /** Number of channels the switch was fired to — the success threshold. */
  channelCount: number;
  /** Model being switched to; frames for any other model are ignored. */
  modelId: string;
  /** Correlation id echoed by every control result for this switch request. */
  requestId: string;
  /** Optional thread scope; root-less legacy replies remain accepted. */
  conversationRoot?: string | null;
  /** Register a control-result listener; returns an unsubscribe function. */
  subscribe: (listener: (frame: ControlResultFrame) => void) => () => void;
  /** Fire the per-channel `switch_model` sends. Resolves when all are sent. */
  sendSwitches: () => Promise<void>;
  /** Schedule the no-reply fallback; returns a cancel function. */
  scheduleTimeout: (onTimeout: () => void) => () => void;
}): Promise<"ok" | "unsupported" | "ambiguous"> {
  type Outcome = "ok" | "unsupported" | "ambiguous";
  const settled = new Promise<Outcome>((resolve, reject) => {
    let unsubscribe = () => {};
    let cancelTimeout = () => {};
    let remaining = channelCount;
    const finish = (outcome: Outcome) => {
      cancelTimeout();
      unsubscribe();
      resolve(outcome);
    };
    const fail = (status: string) => {
      cancelTimeout();
      unsubscribe();
      reject(new Error(`Live model switch failed: ${status}`));
    };
    cancelTimeout = scheduleTimeout(() => finish("ok"));
    unsubscribe = subscribe((frame) => {
      if (
        frame.type !== "switch_model" ||
        frame.modelId !== modelId ||
        frame.requestId !== requestId ||
        (conversationRoot !== null &&
          frame.conversationRoot != null &&
          frame.conversationRoot !== conversationRoot)
      ) {
        return;
      }
      if (frame.status === "unsupported_model") {
        // Any single failure rejects the whole pick immediately.
        finish("unsupported");
        return;
      }
      if (frame.status === "other_turns_in_flight") {
        finish("ambiguous");
        return;
      }
      if (
        frame.status !== "sent" &&
        frame.status !== "switched" &&
        frame.status !== "turn_ending"
      ) {
        fail(frame.status);
        return;
      }
      remaining -= 1;
      if (remaining <= 0) {
        finish("ok");
      }
    });
  });

  await sendSwitches();

  return settled;
}
