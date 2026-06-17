"""Precise patch: fix only search_memories and get_memories in server.py."""
import re

path = r'C:\Users\mauls\Documents\Code\agent-skills\mcp-servers\mem0-patched\src\mem0_mcp_selfhosted\server.py'
with open(path) as f:
    lines = f.readlines()

# Fix get_memories: find the kwargs line near 'def get_memories'
for i, l in enumerate(lines):
    if 'kwargs: dict[str, Any] = {"user_id": uid}' in l:
        # Check if we're inside get_memories (look back for function def)
        context = ''.join(lines[max(0,i-35):i+5])
        if 'def get_memories' in context:
            indent = l[:len(l) - len(l.lstrip())]
            lines[i] = indent + 'kwargs: dict[str, Any] = {"filters": {"user_id": uid}}\n'
            print(f'Fixed get_memories at line {i+1}')
            break

# Fix search_memories: find the kwargs line near 'def search_memories'
for i, l in enumerate(lines):
    if 'kwargs: dict[str, Any] = {"user_id": uid, "query": query}' in l:
        context = ''.join(lines[max(0,i-35):i+15])
        if 'def search_memories' in context:
            indent = l[:len(l) - len(l.lstrip())]
            lines[i] = indent + 'search_filters: dict[str, Any] = {"user_id": uid}\n'
            # Fix the next 5 lines
            for j in range(i+1, min(i+8, len(lines))):
                if 'kwargs["agent_id"]' in lines[j]:
                    lines[j] = lines[j].replace('kwargs["agent_id"]', 'search_filters["agent_id"]')
                elif 'kwargs["run_id"]' in lines[j]:
                    lines[j] = lines[j].replace('kwargs["run_id"]', 'search_filters["run_id"]')
                elif 'kwargs["filters"] = filters' in lines[j]:
                    lines[j] = lines[j].replace(
                        'kwargs["filters"] = filters',
                        'search_filters.update(filters)\n' + indent + 'kwargs: dict[str, Any] = {"query": query, "filters": search_filters}'
                    )
                    break
            print(f'Fixed search_memories at line {i+1}')
            break

with open(path, 'w') as f:
    f.writelines(lines)
print('Done - 2 functions patched')
