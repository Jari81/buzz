import * as React from "react";

import {
  canEditRolePrompt,
  fetchRolePrompt,
  publishRolePrompt,
} from "@/features/profile/lib/rolePromptRelay";
import type { RolePromptRole } from "@/features/profile/lib/rolePrompt";

export function RolePromptStatus({
  owner,
  role,
  isCurrentUserOwner,
}: {
  owner: string | null;
  role: RolePromptRole | null;
  isCurrentUserOwner: boolean;
}) {
  const [prompt, setPrompt] = React.useState<Awaited<
    ReturnType<typeof fetchRolePrompt>
  > | null>(null);
  const [loaded, setLoaded] = React.useState(false);
  const [draft, setDraft] = React.useState("");
  const [editing, setEditing] = React.useState(false);
  const [publishing, setPublishing] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);

  React.useEffect(() => {
    let active = true;
    setLoaded(false);
    setPrompt(null);
    if (!owner || !role) {
      setLoaded(true);
      return;
    }
    void fetchRolePrompt(owner, role)
      .then((next) => {
        if (active) setPrompt(next);
      })
      .catch(() => {})
      .finally(() => {
        if (active) setLoaded(true);
      });
    return () => {
      active = false;
    };
  }, [owner, role]);

  if (!loaded) {
    return (
      <p className="text-sm text-muted-foreground">Loading prompt status...</p>
    );
  }
  if (!prompt) {
    return (
      <p
        className="text-sm text-muted-foreground"
        data-testid="role-prompt-unavailable"
      >
        Prompt status unavailable
      </p>
    );
  }
  return (
    <section
      className="space-y-2 rounded-2xl bg-muted/20 px-4 py-3"
      data-testid="role-prompt-status"
    >
      <div className="text-xs font-medium text-foreground">Role prompt</div>
      <dl className="grid gap-1 text-sm">
        <div>
          <dt className="inline text-muted-foreground">Role: </dt>
          <dd className="inline">{prompt.role}</dd>
        </div>
        <div>
          <dt className="inline text-muted-foreground">Revision: </dt>
          <dd className="inline">{prompt.revision}</dd>
        </div>
        <div className="break-all">
          <dt className="inline text-muted-foreground">Digest: </dt>
          <dd className="inline font-mono text-xs">{prompt.sha256}</dd>
        </div>
      </dl>
      <pre className="whitespace-pre-wrap break-words rounded-md bg-background/50 p-3 text-sm leading-6">
        {prompt.prompt}
      </pre>
      {canEditRolePrompt(isCurrentUserOwner) ? (
        <div className="space-y-2">
          {editing ? (
            <>
              <textarea
                aria-label="Role prompt draft"
                className="min-h-32 w-full rounded-md border bg-background p-3 text-sm"
                value={draft}
                onChange={(event) => setDraft(event.target.value)}
              />
              <div className="flex gap-2">
                <button
                  className="rounded-md bg-primary px-3 py-2 text-sm text-primary-foreground disabled:opacity-50"
                  disabled={publishing || !draft.trim()}
                  onClick={() => {
                    if (
                      !window.confirm(
                        "Publish this role prompt for future controlled agent starts?",
                      )
                    )
                      return;
                    setPublishing(true);
                    setError(null);
                    void publishRolePrompt({
                      owner: owner ?? "",
                      prompt: draft,
                      revision: prompt.revision,
                      role: prompt.role,
                    })
                      .then((next) => {
                        if (!next) {
                          setError("Prompt status unavailable");
                          return;
                        }
                        setPrompt(next);
                        setEditing(false);
                      })
                      .catch(() => setError("Failed to publish role prompt."))
                      .finally(() => setPublishing(false));
                  }}
                  type="button"
                >
                  {publishing ? "Publishing..." : "Confirm and publish"}
                </button>
                <button
                  className="rounded-md px-3 py-2 text-sm"
                  disabled={publishing}
                  onClick={() => setEditing(false)}
                  type="button"
                >
                  Cancel
                </button>
              </div>
            </>
          ) : (
            <button
              className="rounded-md border px-3 py-2 text-sm"
              onClick={() => {
                setDraft(prompt.prompt);
                setEditing(true);
              }}
              type="button"
            >
              Edit prompt
            </button>
          )}
          {error ? <p className="text-sm text-destructive">{error}</p> : null}
          <p className="text-sm text-muted-foreground">
            Changes apply on the next controlled agent start.
          </p>
        </div>
      ) : null}
    </section>
  );
}
