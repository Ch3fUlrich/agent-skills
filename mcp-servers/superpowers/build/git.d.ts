export declare const SUPERPOWERS_REPO = "https://github.com/obra/superpowers.git";
export declare function gitClone(repoUrl: string, targetDir: string): Promise<void>;
export declare function gitPull(targetDir: string): Promise<void>;
export declare function gitFetch(targetDir: string): Promise<void>;
export declare function gitRevParseBase(targetDir: string): Promise<string>;
export declare function gitRevParseRemote(targetDir: string): Promise<string>;
export declare function checkForUpdates(targetDir: string): Promise<boolean>;
export declare function isGitRepo(targetDir: string): Promise<boolean>;
