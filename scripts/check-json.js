// JXA is built into macOS; no Node, Python, or jq is required on a new machine.
ObjC.import('Foundation');
function run(argv) {
  const bytes = $.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile;
  const input = ObjC.unwrap($.NSString.alloc.initWithDataEncoding(bytes, $.NSUTF8StringEncoding));
  const mode = argv[0];
  function check(ok, message) { if (!ok) throw new Error(message); }
  if (mode === 'models') {
    const data = JSON.parse(input);
    const ids = (data.data || []).map(x => x.id);
    const expected = argv.slice(1);
    check(expected.length > 0, 'No expected model IDs were given.');
    const missing = expected.filter(x => !ids.includes(x));
    check(!missing.length, 'Expected model IDs missing: ' + missing.join(', '));
    return 'PASS: all configured model IDs are advertised.';
  }
  if (mode === 'chat' || mode === 'vision') {
    const data = JSON.parse(input);
    const text = ((data.choices || [])[0] || {}).message?.content || '';
    check(mode === 'chat' ? text.trim() === 'OK' : /red\W+blue/i.test(text),
          mode === 'chat' ? 'Expected OK response was not received.' : 'Image colors were not identified in the expected order.');
    return 'PASS: ' + (mode === 'chat' ? 'chat completion' : 'vision (red left, blue right)') +
      (data.backend ? ' via ' + data.backend : '');
  }
  if (mode === 'reasoning') {
    let reason = '', answer = '';
    for (const line of input.split('\n')) {
      if (!line.startsWith('data:') || line.slice(5).trim() === '[DONE]') continue;
      const data = JSON.parse(line.slice(5));
      for (const c of data.choices || []) {
        const d = c.delta || {};
        reason += d.reasoning_content || d.reasoning || '';
        answer += d.content || '';
      }
    }
    // Pass "require" to insist on separate reasoning output; by default only streaming and the answer are checked.
    const requireReasoning = argv[1] === 'require';
    check(!requireReasoning || reason.length > 0 || /<think>[\s\S]+?<\/think>/.test(answer), 'No separate reasoning was received.');
    check(/323/.test(answer), 'Arithmetic answer check failed.');
    return 'PASS: streaming response' + (reason.length ? ' with reasoning' : '') + ' and 16,384-token request ceiling.';
  }
  if (mode === 'opencode') {
    let answer = '', reasoning = 0;
    for (const line of input.split('\n').filter(x => x.trim())) {
      const event = JSON.parse(line);
      check(!event.error && event.type !== 'error', 'OpenCode reported an error.');
      if (event.type === 'text') answer += event.part?.text || '';
      if (event.type === 'reasoning') reasoning += (event.part?.text || '').length;
    }
    check(answer.trim() === 'OK', 'OpenCode did not return OK.');
    return 'PASS: OpenCode returned OK' + (reasoning ? ' with reasoning.' : '.');
  }
  throw new Error('Unknown diagnostic mode.');
}
