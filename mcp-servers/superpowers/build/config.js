import Conf from "conf";
const config = new Conf({
    projectName: "superpowers-mcp",
    defaults: {
        useLocalSkills: false,
    },
});
export function getConfig() {
    return config.store;
}
export function setConfig(newConfig) {
    config.set(newConfig);
}
export function getSkillsDir() {
    return config.get("skillsDir");
}
export function setSkillsDir(dir) {
    config.set("skillsDir", dir);
}
export function getLastUpdateCheck() {
    return config.get("lastUpdateCheck");
}
export function setLastUpdateCheck(timestamp) {
    config.set("lastUpdateCheck", timestamp);
}
//# sourceMappingURL=config.js.map