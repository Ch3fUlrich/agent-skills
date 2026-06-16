import matter from "gray-matter";
import { readdir, readFile, stat } from "node:fs/promises";
import { readdirSync, existsSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
export function parseSkillContent(raw) {
    const { data, content } = matter(raw);
    return {
        name: typeof data.name === "string" ? data.name : "",
        description: typeof data.description === "string" ? data.description : "",
        body: content,
    };
}
export async function discoverSkillsFromDirectory(dirPath) {
    const skills = [];
    let entries;
    try {
        entries = await readdir(dirPath);
    }
    catch {
        return skills;
    }
    for (const entry of entries) {
        const entryPath = join(dirPath, entry);
        // Ignore dotfiles/directories like .DS_Store
        if (entry.startsWith("."))
            continue;
        const entryStat = await stat(entryPath).catch(() => null);
        if (!entryStat?.isDirectory())
            continue;
        const skillMdPath = join(entryPath, "SKILL.md");
        let skillContent;
        try {
            skillContent = await readFile(skillMdPath, "utf-8");
        }
        catch {
            continue;
        }
        const parsed = parseSkillContent(skillContent);
        // Enumerate supporting files
        const allFiles = await readdir(entryPath);
        const supportingFiles = allFiles
            .filter((f) => f !== "SKILL.md" && !f.startsWith("."))
            .map((f) => ({
            name: f,
            relativePath: `${entry}/${f}`,
        }));
        skills.push({
            metadata: {
                name: parsed.name || entry,
                description: parsed.description,
            },
            directoryName: entry,
            content: skillContent,
            files: supportingFiles,
        });
    }
    return skills;
}
export function resolveSkillsDirectory(env = process.env, claudeConfigDir) {
    // 1. Env var override
    if (env.SUPERPOWERS_SKILLS_DIR) {
        if (existsSync(env.SUPERPOWERS_SKILLS_DIR)) {
            return env.SUPERPOWERS_SKILLS_DIR;
        }
        return null;
    }
    // 2. Plugin cache
    const configDir = claudeConfigDir ?? join(homedir(), ".claude");
    const superpowersBase = join(configDir, "plugins", "cache", "claude-plugins-official", "superpowers");
    if (!existsSync(superpowersBase))
        return null;
    const versions = readdirSync(superpowersBase).filter((v) => /^\d+\.\d+\.\d+$/.test(v));
    if (versions.length === 0)
        return null;
    // Sort semver descending, pick latest
    versions.sort((a, b) => {
        const pa = a.split(".").map(Number);
        const pb = b.split(".").map(Number);
        for (let i = 0; i < 3; i++) {
            if (pa[i] !== pb[i])
                return pb[i] - pa[i];
        }
        return 0;
    });
    const skillsDir = join(superpowersBase, versions[0], "skills");
    if (existsSync(skillsDir))
        return skillsDir;
    return null;
}
//# sourceMappingURL=discovery.js.map