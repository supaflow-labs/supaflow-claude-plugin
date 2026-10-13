import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
let passed = 0;
let failed = 0;
function check(name, fn) {
  try {
    fn();
    passed += 1;
    console.log(`PASS: ${name}`);
  } catch (error) {
    failed += 1;
    console.log(`FAIL: ${name} (${error.message})`);
  }
}
const json = (file) => JSON.parse(fs.readFileSync(file, 'utf8'));
const text = (file) => fs.readFileSync(file, 'utf8');
function walk(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const file = path.join(dir, entry.name);
    assert(!entry.isSymbolicLink(), `packaged symlink: ${file}`);
    return entry.isDirectory() ? walk(file) : [file];
  });
}
function frontmatter(file) {
  const match = text(file).match(/^---\n([\s\S]*?)\n---(?:\n|$)/);
  assert(match, `missing frontmatter: ${file}`);
  return match[1];
}

console.log('Testing independently installable package boundaries...');
const marketplace = json(path.join(repo, '.claude-plugin/marketplace.json'));
check('existing marketplace name is preserved', () => assert.equal(marketplace.name, 'supaflow'));
check('marketplace lists exactly two distinct package IDs', () => {
  assert.deepEqual(marketplace.plugins.map((p) => p.name).sort(), ['supaflow', 'supaflow-code']);
});
check('root is a catalog, not a legacy installable plugin', () => {
  for (const old of ['.claude-plugin/plugin.json', '.mcp.json']) {
    assert(!fs.existsSync(path.join(repo, old)), `legacy root runtime remains: ${old}`);
  }
  for (const old of ['commands', 'skills', 'hooks']) {
    const dir = path.join(repo, old);
    // Empty directories and ignored Finder metadata are not Git package content.
    if (fs.existsSync(dir)) assert.equal(walk(dir).filter((f) => path.basename(f) !== '.DS_Store').length, 0,
      `legacy root runtime remains: ${old}`);
  }
});

const commands = ['check-job', 'create-datasource', 'create-pipeline', 'create-schedule',
  'delete-pipeline', 'edit-datasource', 'edit-pipeline', 'explain-job-failure', 'sync-pipeline'];
for (const entry of marketplace.plugins) {
  const root = path.resolve(repo, entry.source);
  check(`${entry.name}: source is a contained independent package`, () => {
    assert.equal(entry.source, `./plugins/${entry.name}`);
    assert(!entry.source.split('/').includes('..'));
    assert(root.startsWith(`${repo}${path.sep}plugins${path.sep}`));
    assert(fs.statSync(root).isDirectory());
  });
  const manifest = json(path.join(root, '.claude-plugin/plugin.json'));
  check(`${entry.name}: manifest identity, version and metadata`, () => {
    assert.equal(manifest.name, entry.name);
    assert.equal(manifest.displayName, entry.name === 'supaflow' ? 'Supaflow' : 'Supaflow Code');
    assert.match(manifest.version, /^\d+\.\d+\.\d+$/);
    const [major, minor] = manifest.version.split('.').map(Number);
    assert(major > 0 || minor >= 3, 'the split must advance the previous 0.2.x version');
    assert.equal(manifest.author.name, 'Supaflow, LLC');
    assert(manifest.description.length > 40);
    assert.equal(manifest.author.email, 'support@supa-flow.io');
    assert.equal(manifest.homepage, 'https://www.supa-flow.io/docs');
    assert.equal(manifest.license, 'MIT');
  });
  check(`${entry.name}: package README and license are standalone`, () => {
    const words = text(path.join(root, 'README.md')).replace(/```[\s\S]*?```/g, '').match(/\S+/g);
    assert(words.length >= 40);
    assert.equal(text(path.join(root, 'LICENSE')), text(path.join(repo, 'LICENSE')));
  });
  check(`${entry.name}: expected command inventory`, () => {
    assert.deepEqual(fs.readdirSync(path.join(root, 'commands')).sort(), commands.map((c) => `${c}.md`));
  });
  const files = walk(root);
  for (const file of files.filter((f) => f.endsWith('.md'))) {
    check(`${entry.name}: contained Markdown links in ${path.relative(root, file)}`, () => {
      for (const [, target] of text(file).matchAll(/\[[^\]]*\]\(([^)]+)\)/g)) {
        if (/^(?:https?:|mailto:|#)/.test(target)) continue;
        const resolved = path.resolve(path.dirname(file), target.split('#')[0]);
        assert(resolved.startsWith(`${root}${path.sep}`), `cross-package link: ${target}`);
        assert(fs.existsSync(resolved), `missing link target: ${target}`);
      }
    });
  }
  for (const file of files.filter((f) => f.endsWith('/SKILL.md'))) {
    check(`${entry.name}: skill identity/trigger in ${path.relative(root, file)}`, () => {
      const fm = frontmatter(file);
      assert.match(fm, new RegExp(`^name: ${path.basename(path.dirname(file))}$`, 'm'));
      assert.match(fm, /^description: .{15,}$/m);
    });
  }
  for (const file of files.filter((f) => f.endsWith('.md') && path.dirname(f) === path.join(root, 'commands'))) {
    check(`${entry.name}: command frontmatter in ${path.basename(file)}`, () => {
      const fm = frontmatter(file);
      assert.match(fm, /^description: .+$/m);
      assert.match(fm, /^argument-hint: .+$/m);
      if (entry.name === 'supaflow') assert(!/^allowed-tools:/m.test(fm));
      else assert.match(fm, /^allowed-tools: .*Bash\(supaflow \*\)/m);
    });
  }

  const mcp = json(path.join(root, '.mcp.json'));
  check(`${entry.name}: exact MCP execution boundary`, () => {
    assert.deepEqual(Object.keys(mcp), ['mcpServers']);
    assert.deepEqual(Object.keys(mcp.mcpServers), ['supaflow']);
    assert.deepEqual(mcp.mcpServers.supaflow, entry.name === 'supaflow'
      ? { type: 'http', url: 'https://app.supa-flow.io/mcp' }
      : { command: 'supaflow', args: ['mcp'] });
  });
  if (entry.name === 'supaflow') {
    check('hosted: directory icon and privacy policy are present', () => {
      assert.equal(manifest.privacyPolicyUrl, 'https://www.supa-flow.io/legal/privacy-policy');
      assert.equal(manifest.icon, '.claude-plugin/icon.png');
      const icon = fs.readFileSync(path.join(root, manifest.icon));
      assert(icon.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])));
      assert.equal(icon.toString('ascii', 12, 16), 'IHDR');
      const width = icon.readUInt32BE(16);
      assert.equal(width, icon.readUInt32BE(20));
      assert(width >= 512 && width <= 2048);
      assert(icon.length < 2 * 1024 * 1024);
    });
    check('hosted: no local runtime, scripts, hooks, or agent skill', () => {
      for (const component of ['hooks', 'bin', 'scripts', 'skills/supaflow-agents']) {
        assert(!fs.existsSync(path.join(root, component)), `local component: ${component}`);
      }
      for (const file of files) {
        assert(file.endsWith('.md') || file.endsWith('.json') || path.basename(file) === 'LICENSE'
          || file === path.join(root, manifest.icon),
          `unexpected executable/asset: ${file}`);
      }
    });
    for (const file of files.filter((f) => /\/(?:skills|commands)\//.test(f) && f.endsWith('.md'))) {
      check(`hosted: no CLI leakage in ${path.relative(root, file)}`, () => {
        assert(!/(?:Bash\(|```(?:bash|shell|sh)\b|^allowed-tools:|supaflow (?:auth login|mcp|agent (?:start|stop|upgrade|remove))|npm install|claude_desktop_config)/m.test(text(file)));
      });
    }
    check('hosted: no local credential/client/callback defaults', () => {
      assert(!/client_secret|client_id|redirect_uri|callback|bearer|headers|env/i.test(JSON.stringify(mcp)));
    });
  } else {
    check('Code: local hook and agent support retained', () => {
      const hooks = json(path.join(root, 'hooks/hooks.json'));
      assert.equal(hooks.hooks.SessionStart[0].hooks[0].command,
        'bash ${CLAUDE_PLUGIN_ROOT}/hooks/check-setup.sh');
      assert(fs.existsSync(path.join(root, 'hooks/check-setup.sh')));
      assert(fs.existsSync(path.join(root, 'skills/supaflow-agents/SKILL.md')));
      assert.match(text(path.join(root, 'skills/using-supaflow/setup-preamble.md')),
        /supported only in Claude Code with a local shell/);
    });
  }
}

console.log(`\nResults: ${passed}/${passed + failed} passed, ${failed} failed`);
process.exitCode = failed ? 1 : 0;
