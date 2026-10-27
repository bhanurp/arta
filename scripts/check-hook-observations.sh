#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product CompanionHook
BUILD="$(swift build --show-bin-path)"
/usr/bin/python3 - "$BUILD/CompanionHook" <<'PY'
import json,os,pathlib,subprocess,sys,tempfile,shutil
root=pathlib.Path(tempfile.mkdtemp(prefix='arta-hook-observations.'))
try:
 for provider in ['codex','claude-code']:
  target=root/provider;target.mkdir();(target/'observations-v1').write_text('unavailable observation directory')
  payload={'session_id':'s','turn_id':'t','tool_use_id':'call','hook_event_name':'PostToolUse','tool_name':'Bash','cwd':'/tmp/Arta','tool_input':{'command':'swift test'},'tool_response':{'exit_code':0}}
  env=os.environ.copy();env['ARTA_DATA_DIR']=str(target)
  args=[sys.argv[1]]+(['--integration','codex'] if provider=='codex' else [])
  result=subprocess.run(args,input=json.dumps(payload).encode(),capture_output=True,env=env,timeout=10)
  inbox=target/('events-v1/codex' if provider=='codex' else 'inbox')
  files=list(inbox.glob('*.json'))
  assert result.returncode==0 and files, f'{provider}: observation storage failure suppressed lifecycle'
 print('Optional observation failure preserves Codex and Claude lifecycle/input-resolution delivery.')
finally:shutil.rmtree(root)
PY
