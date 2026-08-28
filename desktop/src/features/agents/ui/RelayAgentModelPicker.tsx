import * as React from "react";
import { ChevronDown } from "lucide-react";
import { toast } from "sonner";

import { awaitLiveSwitchOutcome } from "@/features/agents/lib/liveSwitchOutcome";
import {
  awaitRelayModelCatalog,
  presentRelayModelCatalog,
  type RelayModelCatalogPresentation,
} from "@/features/agents/lib/relayModelCatalog";
import { subscribeControlResults } from "@/features/agents/observerRelayStore";
import {
  listManagedAgentModels,
  switchManagedAgentModel,
} from "@/shared/api/agentControl";
import { Button } from "@/shared/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuTrigger,
} from "@/shared/ui/dropdown-menu";
import { Spinner } from "@/shared/ui/spinner";

const CONTROL_TIMEOUT_MS = 8_000;

function requestId(): string {
  return (
    globalThis.crypto?.randomUUID?.() ??
    `control-${Date.now()}-${Math.random().toString(36).slice(2)}`
  );
}

export function RelayAgentModelPicker({
  agentPubkey,
  channelId,
  conversationRoot = null,
}: {
  agentPubkey: string;
  channelId: string;
  conversationRoot?: string | null;
}) {
  const [catalog, setCatalog] =
    React.useState<RelayModelCatalogPresentation | null>(null);
  const [loading, setLoading] = React.useState(false);
  const [saving, setSaving] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);

  const loadCatalog = React.useCallback(async () => {
    setLoading(true);
    setError(null);
    const id = requestId();
    try {
      const result = await awaitRelayModelCatalog({
        requestId: id,
        subscribe: (listener) => subscribeControlResults(agentPubkey, listener),
        sendRequest: () => listManagedAgentModels(agentPubkey, id),
        scheduleTimeout: (onTimeout) => {
          const timeout = window.setTimeout(onTimeout, CONTROL_TIMEOUT_MS);
          return () => window.clearTimeout(timeout);
        },
      });
      setCatalog(presentRelayModelCatalog(result));
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : String(cause));
    } finally {
      setLoading(false);
    }
  }, [agentPubkey]);

  const handleOpenChange = React.useCallback(
    (open: boolean) => {
      if (open && !loading && !catalog && !error) {
        void loadCatalog();
      }
    },
    [catalog, error, loadCatalog, loading],
  );

  const handleModelChange = React.useCallback(
    async (modelId: string) => {
      if (modelId === catalog?.currentModelId) return;
      setSaving(true);
      setError(null);
      const id = requestId();
      try {
        const outcome = await awaitLiveSwitchOutcome({
          channelCount: 1,
          modelId,
          requestId: id,
          conversationRoot,
          subscribe: (listener) =>
            subscribeControlResults(agentPubkey, listener),
          sendSwitches: () =>
            switchManagedAgentModel(
              agentPubkey,
              [{ channelId, conversationRoot }],
              modelId,
              id,
            ),
          scheduleTimeout: (onTimeout) => {
            const timeout = window.setTimeout(onTimeout, CONTROL_TIMEOUT_MS);
            return () => window.clearTimeout(timeout);
          },
        });
        if (outcome === "unsupported") {
          toast.error("That model is not available for this agent.");
          return;
        }
        if (outcome === "ambiguous") {
          toast.error(
            "Another conversation is using this agent. Try again when that turn finishes.",
          );
          return;
        }
        setCatalog((current) =>
          current ? { ...current, currentModelId: modelId } : current,
        );
        toast.success("Model switched for this conversation.");
      } catch (cause) {
        setError(cause instanceof Error ? cause.message : String(cause));
      } finally {
        setSaving(false);
      }
    },
    [agentPubkey, catalog?.currentModelId, channelId, conversationRoot],
  );

  const label = catalog?.currentModelId ?? "Model";

  return (
    <DropdownMenu modal={false} onOpenChange={handleOpenChange}>
      <DropdownMenuTrigger asChild>
        <Button
          aria-label="Change model for this agent"
          className="h-7 min-w-0 max-w-36 gap-1 rounded-full px-2 text-xs"
          disabled={saving}
          size="sm"
          type="button"
          variant="ghost"
        >
          <span className="truncate">{label}</span>
          <ChevronDown className="h-3.5 w-3.5 shrink-0" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent
        align="end"
        className="max-h-72 min-w-64 overflow-y-auto"
        onCloseAutoFocus={(event) => event.preventDefault()}
      >
        {loading ? (
          <div className="flex items-center gap-2 px-3 py-2 text-sm text-muted-foreground">
            <Spinner className="h-4 w-4 border-2" />
            Loading models...
          </div>
        ) : error ? (
          <div className="space-y-2 px-3 py-2 text-sm">
            <p className="text-destructive">Failed to contact this agent.</p>
            <button
              className="text-xs text-muted-foreground underline underline-offset-2 hover:text-foreground"
              onClick={() => {
                setError(null);
                void loadCatalog();
              }}
              type="button"
            >
              Retry
            </button>
          </div>
        ) : catalog?.message ? (
          <div className="px-3 py-2 text-sm text-muted-foreground">
            {catalog.message}
          </div>
        ) : catalog && catalog.models.length > 0 ? (
          <>
            <DropdownMenuRadioGroup
              onValueChange={(value) => void handleModelChange(value)}
              value={catalog.currentModelId ?? ""}
            >
              {catalog.models.map((modelId) => (
                <DropdownMenuRadioItem
                  disabled={saving}
                  key={modelId}
                  value={modelId}
                >
                  {modelId}
                </DropdownMenuRadioItem>
              ))}
            </DropdownMenuRadioGroup>
            {catalog.truncated ? (
              <div className="px-3 py-1.5 text-xs text-muted-foreground">
                Catalog truncated by the agent.
              </div>
            ) : null}
          </>
        ) : (
          <div className="px-3 py-2 text-sm text-muted-foreground">
            Open to request available models.
          </div>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
