import type { Skill } from "../skills/types.js";
export type WorkflowIntent = "creative" | "planning" | "implementation" | "debugging" | "review" | "completion" | "general";
export interface SkillRecommendation {
    name: string;
    display_name: string;
    description: string;
    score: number;
    reasons: string[];
}
export interface ComposedWorkflowStep {
    skill: string;
    required: boolean;
    score: number;
    reason: string;
}
export interface ComposedWorkflow {
    goal: string;
    intent: WorkflowIntent;
    required_skills: string[];
    steps: ComposedWorkflowStep[];
}
export interface WorkflowValidation {
    valid: boolean;
    intent: WorkflowIntent;
    required_skills: string[];
    missing_required_skills: string[];
    selected_skills: string[];
    violations: string[];
}
export interface NextSkillValidation {
    valid: boolean;
    intent: WorkflowIntent;
    required_skills: string[];
    missing_required_skills: string[];
    violations: string[];
}
export interface SemanticSearchMatch {
    skill: string;
    file: string;
    source: "skill" | "supporting-file";
    uri: string;
    score: number;
    snippet: string;
}
interface IndexedDocument {
    skill: string;
    file: string;
    source: "skill" | "supporting-file";
    uri: string;
    content: string;
    tokens: string[];
    tokenSet: Set<string>;
    embedding: number[];
}
interface IndexedSkill {
    name: string;
    displayName: string;
    description: string;
    tokens: string[];
    tokenSet: Set<string>;
    embedding: number[];
}
export interface SkillIntelligenceIndex {
    documents: IndexedDocument[];
    skills: IndexedSkill[];
}
export declare function inferIntent(input: string): WorkflowIntent;
export declare function buildSkillIntelligenceIndex(skills: Skill[], skillsDir?: string): Promise<SkillIntelligenceIndex>;
export declare function recommendSkills(index: SkillIntelligenceIndex, task: string, repoContext?: string, maxResults?: number): SkillRecommendation[];
export declare function composeWorkflow(index: SkillIntelligenceIndex, goal: string, maxSteps?: number): ComposedWorkflow;
export declare function validateWorkflow(goal: string, selectedSkills: string[], options?: {
    enforceOrder?: boolean;
    availableSkillNames?: Set<string>;
}): WorkflowValidation;
export declare function validateNextSkill(goal: string, usedSkills: string[], nextSkill: string, availableSkillNames?: Set<string>): NextSkillValidation;
export declare function semanticSearchSkills(index: SkillIntelligenceIndex, query: string, options?: {
    maxResults?: number;
    skillFilter?: string;
}): SemanticSearchMatch[];
export {};
