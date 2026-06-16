interface SuperpowersConfig {
    skillsDir?: string;
    lastUpdateCheck?: number;
    useLocalSkills?: boolean;
}
export declare function getConfig(): SuperpowersConfig;
export declare function setConfig(newConfig: Partial<SuperpowersConfig>): void;
export declare function getSkillsDir(): string | undefined;
export declare function setSkillsDir(dir: string): void;
export declare function getLastUpdateCheck(): number | undefined;
export declare function setLastUpdateCheck(timestamp: number): void;
export {};
