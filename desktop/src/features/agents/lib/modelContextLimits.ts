/**
 * BUZZ-DESKTOP-003: Model context window lookup with fallback heuristic.
 *
 * Resolution order:
 * 1. Exact match in the static model limits table.
 * 2. Prefix match (e.g. "claude-sonnet-4-20250514" matches "claude-sonnet-4").
 * 3. Observed-max heuristic: if any turn in this session exceeded the
 *    default window, promote to 1M (same logic as the VS-Code Buzz Monitor).
 * 4. Default (200k).
 */
import limitsJson from "./modelContextLimits.json";

const DEFAULT_CONTEXT_WINDOW =
  (limitsJson as { defaultContextWindow?: number }).defaultContextWindow ??
  200_000;

const MODEL_LIMITS: Record<string, number> = (
  limitsJson as { models: Record<string, number> }
).models;

/** Sorted prefix keys for longest-prefix-first matching. */
const PREFIX_KEYS = Object.keys(MODEL_LIMITS).sort(
  (a, b) => b.length - a.length,
);

/**
 * Resolve the context window for a model identifier.
 *
 * @param modelId - Model string from session_config_captured or kind:44200.
 * @param observedMaxInputTokens - Highest input-token count seen in this
 *   session so far. Used for the 200k→1M promotion heuristic.
 * @returns Context window in tokens.
 */
export function resolveContextWindow(
  modelId: string | null | undefined,
  observedMaxInputTokens = 0,
): number {
  if (!modelId)
    return promoteIfObserved(DEFAULT_CONTEXT_WINDOW, observedMaxInputTokens);

  const normalized = modelId.trim().toLowerCase();

  // Exact match
  const exact = MODEL_LIMITS[normalized];
  if (exact) return promoteIfObserved(exact, observedMaxInputTokens);

  // Strip provider prefix (e.g. "anthropic/claude-sonnet-4" → "claude-sonnet-4")
  const withoutProvider = normalized.includes("/")
    ? normalized.slice(normalized.lastIndexOf("/") + 1)
    : normalized;
  if (withoutProvider !== normalized) {
    const stripped = MODEL_LIMITS[withoutProvider];
    if (stripped) return promoteIfObserved(stripped, observedMaxInputTokens);
  }

  // Prefix match (longest first)
  for (const key of PREFIX_KEYS) {
    if (withoutProvider.startsWith(key)) {
      return promoteIfObserved(MODEL_LIMITS[key], observedMaxInputTokens);
    }
  }

  return promoteIfObserved(DEFAULT_CONTEXT_WINDOW, observedMaxInputTokens);
}

/**
 * If observed usage already exceeds the resolved window, the model likely
 * has a larger context than our table knows. Promote to 1M.
 */
function promoteIfObserved(base: number, observed: number): number {
  if (observed > base) return 1_048_576;
  return base;
}
