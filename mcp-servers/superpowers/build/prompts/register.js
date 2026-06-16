export function registerPrompts(server, skills) {
    for (const skill of skills) {
        server.prompt(`superpowers:${skill.directoryName}`, skill.metadata.description, () => ({
            messages: [
                {
                    role: "user",
                    content: {
                        type: "text",
                        text: skill.content,
                    },
                },
            ],
        }));
    }
}
//# sourceMappingURL=register.js.map