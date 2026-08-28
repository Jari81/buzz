import { sendAgentObserverControl } from "@/shared/api/observerRelay";
import type { CancelManagedAgentTurnResult } from "@/shared/api/types";

export async function cancelManagedAgentTurn(
  pubkey: string,
  channelId: string,
): Promise<CancelManagedAgentTurnResult> {
  await sendAgentObserverControl(pubkey, {
    type: "cancel_turn",
    channelId,
  });
  return { status: "sent" };
}

export function buildListModelsControl(requestId: string) {
  return {
    type: "list_models" as const,
    requestId,
  };
}

export type SwitchModelTarget = {
  channelId: string;
  conversationRoot?: string | null;
};

type ObserverControlSender = (
  pubkey: string,
  payload: unknown,
) => Promise<void>;

export function buildSwitchModelControl(
  targets: readonly SwitchModelTarget[],
  modelId: string,
  requestId: string,
) {
  return {
    type: "switch_model" as const,
    modelId,
    requestId,
    targets: targets.map(({ channelId, conversationRoot }) => ({
      channelId,
      ...(conversationRoot ? { conversationRoot } : {}),
    })),
  };
}

/** Send exactly one atomic model-switch control frame. */
export async function sendSwitchModelControl(
  sendControl: ObserverControlSender,
  pubkey: string,
  targets: readonly SwitchModelTarget[],
  modelId: string,
  requestId: string,
): Promise<void> {
  await sendControl(
    pubkey,
    buildSwitchModelControl(targets, modelId, requestId),
  );
}

export async function listManagedAgentModels(
  pubkey: string,
  requestId: string,
): Promise<void> {
  await sendAgentObserverControl(pubkey, buildListModelsControl(requestId));
}

/**
 * Send one live model-switch control frame for all named conversations. The
 * outcome arrives asynchronously as one aggregate `control_result` observer
 * frame, not as the return value here.
 */
export async function switchManagedAgentModel(
  pubkey: string,
  targets: readonly SwitchModelTarget[],
  modelId: string,
  requestId: string,
): Promise<void> {
  await sendSwitchModelControl(
    sendAgentObserverControl,
    pubkey,
    targets,
    modelId,
    requestId,
  );
}
