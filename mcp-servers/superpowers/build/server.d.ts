import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Skill } from "./skills/types.js";
export interface ServerOptions {
    skillsDir?: string;
}
export interface ServerResult {
    server: McpServer;
    skills: Skill[];
    skillsDir: string | null;
}
export declare function createSuperpowersServer(options?: ServerOptions): Promise<ServerResult>;
