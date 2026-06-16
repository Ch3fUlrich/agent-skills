import type { Skill } from "./types.js";
export interface ParsedSkillContent {
    name: string;
    description: string;
    body: string;
}
export declare function parseSkillContent(raw: string): ParsedSkillContent;
export declare function discoverSkillsFromDirectory(dirPath: string): Promise<Skill[]>;
export declare function resolveSkillsDirectory(env?: Record<string, string | undefined>, claudeConfigDir?: string): string | null;
