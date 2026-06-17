import sys
f = sys.argv[1]
with open(f, 'r') as fh:
    content = fh.read()

# Fix get_memories: move agent_id and run_id into filters too
old = '''        kwargs: dict[str, Any] = {"filters": {"user_id": uid}}
        if agent_id:
            kwargs["agent_id"] = agent_id
        if run_id:
            kwargs["run_id"] = run_id
        if limit is not None:
            kwargs["limit"] = limit
'''

new = '''        get_filters: dict[str, Any] = {"user_id": uid}
        if agent_id:
            get_filters["agent_id"] = agent_id
        if run_id:
            get_filters["run_id"] = run_id
        kwargs: dict[str, Any] = {"filters": get_filters}
        if limit is not None:
            kwargs["limit"] = limit
'''

count = content.count(old)
content = content.replace(old, new)
with open(f, 'w') as fh:
    fh.write(content)
print(f'Replaced {count} occurrences')
print('Done - agent_id/run_id now inside filters for get_memories')
