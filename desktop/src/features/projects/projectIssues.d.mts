import type { RelayEvent } from "@/shared/api/types";

export type ProjectIssueStatus =
  | "Triage"
  | "Backlog"
  | "In Progress"
  | "Approved"
  | "In Review"
  | "Done"
  | "Closed";

export type ProjectIssueComment = {
  id: string;
  content: string;
  tags: string[][];
  author: string;
  createdAt: number;
  recipients: string[];
  actionRequired: boolean;
};

export type ProjectIssue = {
  id: string;
  title: string;
  content: string;
  tags: string[][];
  author: string;
  createdAt: number;
  repoAddress: string | null;
  channelId: string | null;
  originAgentName: string | null;
  labels: string[];
  recipients: string[];
  assignees: string[];
  assigneeOperationHeads: Record<string, string>;
  status: ProjectIssueStatus;
  statusEventId: string | null;
  statusCreatedAt: number | null;
  updatedAt: number;
  comments: ProjectIssueComment[];
};

export const ISSUE_ASSIGNMENT_LABEL: "assignment";
export const ISSUE_UNASSIGNMENT_LABEL: "unassignment";
export const ISSUE_ACTION_REQUIRED_LABEL: "action-required";
export function isHumanDirectedIssueComment(body: string): boolean;

export const PROJECT_ISSUE_STATUS: {
  TRIAGE: "Triage";
  BACKLOG: "Backlog";
  IN_PROGRESS: "In Progress";
  APPROVED: "Approved";
  IN_REVIEW: "In Review";
  DONE: "Done";
  CLOSED: "Closed";
};

export function getTag(event: RelayEvent, name: string): string | undefined;
export function getAllTags(event: RelayEvent, name: string): string[];
export function getImetaTags(event: RelayEvent): string[][];
export function eventToProjectIssue(
  issue: RelayEvent,
  statusEvents?: RelayEvent[],
  commentEvents?: RelayEvent[],
  additionalStatusActors?: string[],
): ProjectIssue;
export function projectIssueEventsToIssues(
  issueEvents: RelayEvent[],
  statusEvents?: RelayEvent[],
  commentEvents?: RelayEvent[],
  additionalStatusActors?: string[],
): ProjectIssue[];
export function nextProjectIssueStatusCreatedAt(
  issue: ProjectIssue,
  now: number,
): number;
export function nextProjectIssueCommentCreatedAt(
  issue: ProjectIssue,
  now: number,
  author: string,
): number;
export function buildGitIssueTags(input: {
  repoAddress: string;
  repoOwner: string;
  title: string;
  labels?: string[];
}): string[][];
export function buildGitStatusTags(input: {
  issueId: string;
  repoAddress?: string | null;
  repoOwner?: string | null;
}): string[][];
