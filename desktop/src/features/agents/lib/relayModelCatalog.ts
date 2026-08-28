import type { ControlResultFrame } from "@/shared/api/observerRelay";

export type RelayModelCatalogResult = ControlResultFrame & {
  type: "list_models";
  requestId: string;
};

export type RelayModelCatalogPresentation = {
  currentModelId: string | null;
  models: string[];
  message: string | null;
  truncated: boolean;
};

export function presentRelayModelCatalog(
  result: RelayModelCatalogResult,
): RelayModelCatalogPresentation {
  if (result.status !== "ok") {
    return {
      currentModelId: result.desiredModelId ?? result.currentModelId ?? null,
      models: [],
      message:
        result.status === "timeout"
          ? "Agent did not return a model catalog."
          : "Model catalog is not available for this agent yet.",
      truncated: false,
    };
  }

  return {
    currentModelId: result.desiredModelId ?? result.currentModelId ?? null,
    models: Array.isArray(result.models) ? result.models : [],
    message: null,
    truncated: result.truncated === true,
  };
}

/**
 * Subscribe before sending so a fast relay reply cannot race past the picker.
 * Only the caller's requestId is accepted; cleanup runs on every terminal path.
 */
export function awaitRelayModelCatalog({
  requestId,
  subscribe,
  sendRequest,
  scheduleTimeout,
}: {
  requestId: string;
  subscribe: (listener: (frame: ControlResultFrame) => void) => () => void;
  sendRequest: () => Promise<void>;
  scheduleTimeout: (onTimeout: () => void) => () => void;
}): Promise<RelayModelCatalogResult> {
  return new Promise((resolve, reject) => {
    let settled = false;
    let unsubscribe = () => {};
    let cancelTimeout = () => {};

    const cleanup = () => {
      cancelTimeout();
      unsubscribe();
    };
    const finish = (result: RelayModelCatalogResult) => {
      if (settled) return;
      settled = true;
      cleanup();
      resolve(result);
    };
    const fail = (error: unknown) => {
      if (settled) return;
      settled = true;
      cleanup();
      reject(error);
    };

    unsubscribe = subscribe((frame) => {
      if (frame.type !== "list_models" || frame.requestId !== requestId) {
        return;
      }
      finish(frame as RelayModelCatalogResult);
    });
    cancelTimeout = scheduleTimeout(() =>
      finish({ type: "list_models", requestId, status: "timeout" }),
    );
    void sendRequest().catch(fail);
  });
}
