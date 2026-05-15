# HTML Working Documents

Use self-contained HTML artifacts for substantial AI-agent work when layout, comparison, diagrams, mockups, tables, interaction, or handoff value would make the result clearer than long markdown.

## Use HTML When

- The output would become a long plan, spec, review, report, explainer, or research note.
- The user needs to compare approaches, designs, components, risks, timelines, or decisions.
- A diagram, mockup, annotated flow, table, or small interactive editor would help the user decide.
- The artifact should be shared with another human or future agent session.

## Prefer Markdown When

- The answer is short, linear, or mostly prose.
- The file is ordinary repository documentation that should stay easy to diff.
- The user explicitly asks for markdown or plain text.

## Artifact Requirements

- Create one standalone `.html` file that opens from disk or a static server.
- Use inline CSS and only small inline JavaScript when it improves the human loop.
- Avoid remote dependencies unless the user explicitly asks for a real app.
- Put browser artifacts in `webpage/` by default unless the repository says otherwise.
- Include source context, assumptions, and evidence.
- End with a recommendation, next implementation slice, validation plan, risk table, open questions, or export button.

## Common Shapes

- Exploration: side-by-side approaches with tradeoffs and a recommendation.
- Implementation plan: architecture, milestones, risks, tests, open questions, and handoff notes.
- Review: findings first, severity labels, file references, evidence, and next steps.
- Explainer: TL;DR, diagrams, examples, collapsible details, and glossary.
- Prototype: clickable interaction or animation with controls and copyable values.
- Editor: purpose-built controls plus copy/export for the changed state.

For the complete skill, read `skills/html-working-documents/SKILL.md` or the repo-local copy at `.codex/skills/html-working-documents/SKILL.md`.
