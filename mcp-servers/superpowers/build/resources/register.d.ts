import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Skill } from "../skills/types.js";
export declare function registerResources(server: McpServer, skills: Skill[], skillsDir?: string): void;
