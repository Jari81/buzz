import { formatTokenCount } from "@/features/agents/lib/agentContextUsage";
import { cn } from "@/shared/lib/cn";

export { formatTokenCount };

/**
 * BUZZ-DESKTOP-003: compact SVG ring showing how much of an agent's context
 * window is in use. Sits in the composer toolbar of DMs with agent
 * participants.
 *
 * Visual contract (VS-Code Buzz Monitor parity): one filled ring — the arc
 * fraction is the usage ratio, the remainder is a quiet track. Color steps
 * up with usage so degradation long before 100 % is visible at a glance:
 *   < 60 %  muted/foreground   — normal operation
 *   60–85 % amber/warning      — precision starts dropping, consider /compact
 *   > 85 %  destructive        — hallucination risk spikes
 */

type ContextUsageRingProps = {
  className?: string;
  /** Usage ratio in [0, 1]; null renders an empty track (no data yet). */
  ratio: number | null;
  /** Diameter in px. */
  size?: number;
  /** Accessible label, e.g. "Context 62 % used · sonnet-4.5 · 118k/200k". */
  label: string;
};

export function ContextUsageRing({
  className,
  ratio,
  size = 20,
  label,
}: ContextUsageRingProps) {
  const stroke = 3;
  const radius = (size - stroke) / 2;
  const circumference = 2 * Math.PI * radius;
  const clamped = ratio == null ? 0 : Math.min(1, Math.max(0, ratio));
  const dashOffset = circumference * (1 - clamped);

  const tone =
    ratio == null
      ? "text-muted-foreground/40"
      : ratio > 0.85
        ? "text-destructive"
        : ratio > 0.6
          ? "text-amber-500"
          : "text-muted-foreground";

  return (
    <svg
      aria-label={label}
      className={cn("shrink-0", tone, className)}
      data-testid="context-usage-ring"
      height={size}
      role="img"
      viewBox={`0 0 ${size} ${size}`}
      width={size}
    >
      {/* Track */}
      <circle
        cx={size / 2}
        cy={size / 2}
        fill="none"
        r={radius}
        stroke="currentColor"
        strokeOpacity={0.25}
        strokeWidth={stroke}
      />
      {/* Usage arc, rotated so it starts at 12 o'clock */}
      {clamped > 0 ? (
        <circle
          cx={size / 2}
          cy={size / 2}
          fill="none"
          r={radius}
          stroke="currentColor"
          strokeDasharray={circumference}
          strokeDashoffset={dashOffset}
          strokeLinecap="round"
          strokeWidth={stroke}
          transform={`rotate(-90 ${size / 2} ${size / 2})`}
        />
      ) : null}
    </svg>
  );
}
