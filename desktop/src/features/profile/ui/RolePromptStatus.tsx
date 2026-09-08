import * as React from "react";

import { fetchRolePrompt } from "@/features/profile/lib/rolePromptRelay";
import type { RolePromptRole } from "@/features/profile/lib/rolePrompt";

export function RolePromptStatus({
  owner,
  role,
}: {
  owner: string | null;
  role: RolePromptRole | null;
}) {
  const [prompt, setPrompt] = React.useState<Awaited<
    ReturnType<typeof fetchRolePrompt>
  > | null>(null);
  const [loaded, setLoaded] = React.useState(false);

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
    </section>
  );
}
