import type { AgentPersona, ManagedAgent } from "@/shared/api/types";

export function visibleLibraryPersonas(
  personas: readonly AgentPersona[],
  agents: readonly Pick<ManagedAgent, "personaId">[],
  hiddenBuiltinIds: ReadonlySet<string>,
): AgentPersona[] {
  const managedPersonaIds = new Set(
    agents.flatMap((agent) => (agent.personaId ? [agent.personaId] : [])),
  );

  return personas.filter(
    (persona) =>
      !persona.isBuiltIn ||
      !hiddenBuiltinIds.has(persona.id) ||
      managedPersonaIds.has(persona.id),
  );
}
