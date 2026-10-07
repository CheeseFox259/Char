#!/usr/bin/env python3
"""Check published Markdown links and accidental developer-home paths."""
import pathlib
import re
import sys
from urllib.parse import unquote, urlsplit
root = pathlib.Path(__file__).resolve().parent.parent
files = [root/name for name in ('README.md','CONTRIBUTING.md','SECURITY.md','CONTEXT.md','AGENTS.md')]
for directory in ('docs','integrations','examples','Resources'):
    files += [p for p in (root/directory).rglob('*.md') if not any(x in p.parts for x in ('build','reports','preview','__pycache__'))]
errors = []
for path in files:
    if not path.exists(): continue
    source = path.read_text()
    if '/Users/superhacker' in source:
        errors.append(f'{path.relative_to(root)}: developer home path')
    content = re.sub(r'```.*?```|~~~.*?~~~','',source,flags=re.S)
    targets = re.findall(r'\[[^\]]*\]\(([^)]+)\)',content)
    targets += re.findall(r'(?:src|href)="([^"]+)"',content)
    for target in targets:
        target = target.strip().strip('<>').split(' "')[0]
        parsed = urlsplit(target)
        if parsed.scheme or target.startswith(('#','//')): continue
        local = unquote(parsed.path)
        if local and not (path.parent/local).exists():
            errors.append(f'{path.relative_to(root)}: missing {local}')
if errors:
    print('\n'.join(errors)); sys.exit(1)
print(f'Public docs: {len(files)} Markdown files checked; links and developer paths passed')
