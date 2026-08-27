import { getActivePersonas } from "@/features/agents/lib/catalog";
import { getUsableTeams } from "@/features/agents/lib/teamPersonas";
import type { AgentPersona, AgentTeam } from "@/shared/api/types";

export function isPersonaVisibilityAuthoritative(
  personas: readonly AgentPersona[] | undefined,
  hiddenBuiltinIds: readonly string[] | undefined,
  personasError: unknown,
  hiddenBuiltinIdsError: unknown,
): boolean {
  return (
    personas !== undefined &&
    hiddenBuiltinIds !== undefined &&
    personasError == null &&
    hiddenBuiltinIdsError == null
  );
}

export function visibleLibraryPersonas(
  personas: readonly AgentPersona[],
  hiddenBuiltinIds: ReadonlySet<string>,
): AgentPersona[] {
  return personas.filter(
    (persona) => !persona.isBuiltIn || !hiddenBuiltinIds.has(persona.id),
  );
}

export function getSelectableAgentOptions(
  personas: readonly AgentPersona[],
  teams: readonly AgentTeam[],
  hiddenBuiltinPersonaIds: ReadonlySet<string>,
) {
  const visiblePersonas = visibleLibraryPersonas(
    getActivePersonas(personas),
    hiddenBuiltinPersonaIds,
  );
  return {
    personas: visiblePersonas,
    teams: getUsableTeams(teams, visiblePersonas),
  };
}
