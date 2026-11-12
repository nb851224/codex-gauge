import json, sys
from pathlib import Path
state = Path(sys.argv[1])
attempt = int(state.read_text()) + 1 if state.exists() else 1
state.write_text(str(attempt))
for line in sys.stdin:
    request = json.loads(line)
    method = request.get('method')
    if method == 'initialize':
        if attempt == 1:
            continue  # simulate a hung handshake
        result = {}
    elif method == 'account/rateLimits/read':
        if attempt == 2:
            continue  # simulate a hung usage request
        result = {'rateLimits': {'primary': {'usedPercent': 17, 'resetsAt': 1792649829, 'windowDurationMins': 10080}}}
    else:
        continue
    print(json.dumps({'id': request['id'], 'result': result}), flush=True)
