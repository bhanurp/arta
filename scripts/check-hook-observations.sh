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
 target=root/'questions';target.mkdir()
 env=os.environ.copy();env['ARTA_DATA_DIR']=str(target)
 payload={'session_id':'question-session','turn_id':'question-turn','cwd':'/tmp/Arta','tool_name':'request_user_input_async','tool_use_id':'question-call','tool_input':{'questions':[{'title':'Continue the Arta test?'}]}}
 args=[sys.argv[1],'--integration','codex']
 def deliver(hook,**fields):
  result=subprocess.run(args,input=json.dumps(dict(payload,hook_event_name=hook,**fields)).encode(),capture_output=True,env=env,timeout=10)
  assert result.returncode==0 and json.loads(result.stdout)=={}, 'Observer must not answer Codex approvals/questions'
  inbox=target/'events-v1/codex'
  events=[json.loads(p.read_text()) for p in inbox.glob('*.json')]
  for p in inbox.glob('*.json'):p.unlink()
  return events
 opened=deliver('PreToolUse')
 requests=[v['requestID'] for v in opened if v['kind']=='input.requested']
 assert len(requests)==1, 'Question was not normalized as pending input'
 accepted=deliver('PostToolUse',tool_response='{"accepted":true}')
 assert not any(v['kind']=='input.resolved' and v.get('requestID') in requests for v in accepted), 'Async acceptance incorrectly answered the question'
 prompt='<send_user_message_question_reply>\n'+json.dumps([{'questionItemId':json.dumps(['request_user_input_async','question-call',0]),'answer':'Continue'}])+'\n</send_user_message_question_reply>'
 answered=deliver('UserPromptSubmit',prompt=prompt)
 assert any(v['kind']=='input.resolved' and v.get('requestID')==requests[0] for v in answered), 'The matching answer did not resolve its question'
 print('Codex question delivery, async persistence, exact reply resolution, and observation-only output passed.')
finally:shutil.rmtree(root)
PY
