import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import type { Skill } from "../skills/types.js";
import {
    buildSkillIntelligenceIndex,
    composeWorkflow,
    inferIntent,
    recommendSkills,
    semanticSearchSkills,
    validateNextSkill,
    validateWorkflow,
} from "./intelligence.js";

describe("intelligence", () => {
    let testDir: string;
    let skills: Skill[];

    beforeAll(() => {
        testDir = join(tmpdir(), `superpowers-mcp-intelligence-${Date.now()}`);
        mkdirSync(testDir, { recursive: true });

        const debuggingDir = join(testDir, "systematic-debugging");
        mkdirSync(debuggingDir, { recursive: true });
        writeFileSync(
            join(debuggingDir, "root-cause-tracing.md"),
            "Trace symptoms to the underlying failure source using evidence."
        );

        skills = [
            {
                metadata: { name: "brainstorming", description: "Design and ideation" },
                directoryName: "brainstorming",
                content: "Explore approaches and clarify intent.",
                files: [],
            },
            {
                metadata: { name: "tdd", description: "Test-driven development" },
                directoryName: "test-driven-development",
                content: "Write a failing test first, then green and refactor.",
                files: [],
            },
            {
                metadata: { name: "debugging", description: "Root cause analysis" },
                directoryName: "systematic-debugging",
                content: "Investigate and isolate the root cause before fixing.",
                files: [
                    {
                        name: "root-cause-tracing.md",
                        relativePath: "systematic-debugging/root-cause-tracing.md",
                    },
                ],
            },
            {
                metadata: { name: "verification", description: "Verification" },
                directoryName: "verification-before-completion",
                content: "Run tests and verify output before completion.",
                files: [],
            },
            {
                metadata: { name: "planning", description: "Planning" },
                directoryName: "writing-plans",
                content: "Create implementation plans and tasks.",
                files: [],
            },
        ];
    });

    afterAll(() => {
        rmSync(testDir, { recursive: true, force: true });
    });

    it("inferIntent should classify goals", () => {
        expect(inferIntent("Debug flaky tests in production")).toBe("debugging");
        expect(inferIntent("Design architecture options")).toBe("creative");
        expect(inferIntent("Implement feature with tests first")).toBe("implementation");
    });

    it("recommendSkills should rank the most relevant skills", async () => {
        const index = await buildSkillIntelligenceIndex(skills, testDir);
        const recommendations = recommendSkills(
            index,
            "Implement API authentication with tests first",
            "Node MCP server",
            3
        );
        expect(recommendations).toHaveLength(3);
        expect(recommendations[0].name).toBe("test-driven-development");
        expect(recommendations[0].score).toBeGreaterThan(0);
    });

    it("composeWorkflow should prepend required skills", async () => {
        const index = await buildSkillIntelligenceIndex(skills, testDir);
        const workflow = composeWorkflow(index, "Design a migration strategy", 4);
        expect(workflow.intent).toBe("creative");
        expect(workflow.required_skills).toContain("brainstorming");
        expect(workflow.steps[0].skill).toBe("brainstorming");
        expect(workflow.steps[0].required).toBe(true);
    });

    it("validateWorkflow should detect missing required skills", () => {
        const validation = validateWorkflow(
            "Implement a caching layer",
            ["verification-before-completion"],
            {
                availableSkillNames: new Set(skills.map((skill) => skill.directoryName)),
            }
        );
        expect(validation.valid).toBe(false);
        expect(validation.missing_required_skills).toContain("test-driven-development");
    });

    it("validateNextSkill should block optional skills before required ones", () => {
        const validation = validateNextSkill(
            "Implement a caching layer",
            [],
            "verification-before-completion",
            new Set(skills.map((skill) => skill.directoryName))
        );
        expect(validation.valid).toBe(false);
        expect(validation.violations[0]).toContain("Required skills must be used first");
        expect(validation.violations[0]).toContain("test-driven-development");
    });

    it("semanticSearchSkills should search supporting files", async () => {
        const index = await buildSkillIntelligenceIndex(skills, testDir);
        const results = semanticSearchSkills(index, "underlying failure source trace", {
            maxResults: 3,
        });
        expect(results.length).toBeGreaterThan(0);
        expect(results[0].skill).toBe("systematic-debugging");
        expect(results[0].file).toBe("root-cause-tracing.md");
        expect(results[0].score).toBeGreaterThan(0);
    });
});
