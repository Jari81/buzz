export type IssueRepositoryScope = "all" | string;

type IssueRepositoryRow = {
  project: { name: string };
  repository: { name: string; repoAddress: string };
};

export type IssueRepositoryScopeOption = {
  label: string;
  value: IssueRepositoryScope;
};

/** Filters the already loaded aggregate issue rows without another relay query. */
export function filterIssueRowsByRepository<TRow extends IssueRepositoryRow>(
  rows: readonly TRow[],
  scope: IssueRepositoryScope,
): TRow[] {
  if (scope === "all") return [...rows];
  return rows.filter((row) => row.repository.repoAddress === scope);
}

export function normalizeIssueRepositoryScope(
  scope: IssueRepositoryScope,
  options: readonly IssueRepositoryScopeOption[],
): IssueRepositoryScope {
  return options.some((option) => option.value === scope) ? scope : "all";
}

/** Lists issue-bearing repositories once, preserving the aggregate row order. */
export function issueRepositoryScopeOptions<TRow extends IssueRepositoryRow>(
  rows: readonly TRow[],
): IssueRepositoryScopeOption[] {
  const options: IssueRepositoryScopeOption[] = [
    { label: "All repositories", value: "all" },
  ];
  const seen = new Set<string>();
  for (const { project, repository } of rows) {
    if (seen.has(repository.repoAddress)) continue;
    seen.add(repository.repoAddress);
    options.push({
      label: `${project.name} / ${repository.name}`,
      value: repository.repoAddress,
    });
  }
  return options;
}
