#!/usr/bin/env node
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';

/**
 * The assertions this repo would otherwise enforce by intention.
 *
 * Everything here is a claim some document makes about itself — a size budget, a
 * precondition in a description, a manifest listing the skills that exist. None
 * of them is checkable by reading one file, and all of them drift silently.
 *
 *   node check.mjs                 lint the repo
 *   node check.mjs run <run-dir>   check that a repro run reviewed what it published
 */

const root = dirname(new URL(import.meta.url).pathname);

/**
 * A budget is not a limit to raise. It exists to hold each skill to one readable
 * file: when a body reaches it, the answer is to move detail into a
 * `references/` file, not to move the number.
 */
const BUDGETS = {
  repro: 10240,
  'github-media-attach': 45056,
};

/**
 * The phrase in each description that says *when not to load this skill*.
 *
 * Three skills in one topic neighbourhood compete for the same triggers, and the
 * only thing separating them is the precondition each one states. A description
 * that loses its precondition still reads fine and starts mis-firing.
 */
const PRECONDITIONS = {
  repro: 'nothing has been captured yet',
  'github-media-attach': 'no dedicated attachment CLI is installed',
};

const failures = [];
const notes = [];
const fail = (message) => failures.push(message);

const walk = (dir, predicate) => {
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return [];
  }
  return entries.flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) return entry.name === '.git' ? [] : walk(path, predicate);
    return predicate(entry.name) ? [path] : [];
  });
};

const markdownFiles = () => walk(root, (name) => name.endsWith('.md'));
const skillDirs = () =>
  readdirSync(join(root, 'skills'), { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name);

const readJson = (path) => JSON.parse(readFileSync(path, 'utf8'));
const rel = (path) => relative(root, path);

function lint() {
  const skills = skillDirs();

  // (a) Example profiles have to parse, or they are decoration a reader will
  // copy and then debug.
  const examples = walk(join(root, 'skills'), (name) => name.endsWith('.json')).filter((path) =>
    path.includes(`${'examples'}/`),
  );
  if (examples.length === 0) {
    // Said out loud rather than passing silently: an assertion with nothing to
    // assert over is not evidence of anything.
    notes.push('no example profiles yet — assertion (a) had nothing to check');
  }
  for (const path of examples) {
    try {
      const parsed = readJson(path);
      if (parsed.version !== 1) fail(`${rel(path)}: version is ${parsed.version}, expected 1`);
    } catch (error) {
      fail(`${rel(path)}: does not parse — ${error.message}`);
    }
  }

  for (const skill of skills) {
    const skillMd = join(root, 'skills', skill, 'SKILL.md');
    let body;
    try {
      body = readFileSync(skillMd, 'utf8');
    } catch {
      fail(`skills/${skill}/SKILL.md is missing`);
      continue;
    }

    // (b) Size budget.
    const budget = BUDGETS[skill];
    if (budget === undefined) {
      fail(`skills/${skill}: no budget in check.mjs — add one, deliberately`);
    } else {
      const bytes = statSync(skillMd).size;
      if (bytes >= budget) {
        fail(
          `skills/${skill}/SKILL.md is ${bytes} bytes, over its ${budget}-byte budget by ${bytes - budget}. ` +
            'Move detail into references/ rather than raising the number.',
        );
      }
    }

    // (c) A relative link that escapes its own skill directory breaks the moment
    // the skill is installed anywhere other than this checkout. Compared with
    // `relative`, not `startsWith`: a sibling named `repro-extra` starts with
    // `repro` and would otherwise pass.
    const skillDir = join(root, 'skills', skill);
    for (const [, link] of body.matchAll(/\]\((?!https?:|#|mailto:)([^)]+)\)/g)) {
      const target = resolve(dirname(skillMd), link.split('#')[0]);
      const inside = relative(skillDir, target);
      if (inside.startsWith('..') || inside === '') {
        fail(`skills/${skill}/SKILL.md links outside its own directory: ${link}`);
      }
    }

    // (e) The precondition is the only thing keeping three neighbouring skills
    // apart at trigger time.
    const description = /^description:\s*(.+)$/m.exec(body)?.[1] ?? '';
    const phrase = PRECONDITIONS[skill];
    if (phrase === undefined) {
      fail(`skills/${skill}: no precondition phrase in check.mjs — add one, deliberately`);
    } else if (!description.includes(phrase)) {
      fail(`skills/${skill}: description no longer states its precondition ("${phrase}")`);
    }
  }

  // (d) The rule is "no path that is right on exactly one machine" — not "no
  // slashes". `/dev/null` and `/usr/share/fonts/...` are the same everywhere and
  // belong in a shell example; `/home/someone/checkout` does not.
  //
  // Written as an allowlist of portable roots with everything else flagged,
  // rather than a denylist of machine-specific ones. A denylist keeps missing the
  // next root (/workspace, /mnt, /srv); this way a new one is caught by default
  // and the portable set is small and stable.
  // macOS system roots belong here for the same reason /usr does: identical on
  // every machine that has them.
  const PORTABLE_ROOTS = /^\/(?:dev|usr|etc|proc|sys|bin|sbin|lib|System|Library|var\/log|var\/run)\//;
  // Two segments minimum, and `$` allowed inside them so `/home/$USER/project` is
  // caught. A *single*-segment rooted token is deliberately not matched: `/plugin
  // marketplace add` and `/repro` are slash-commands, and this repo's own README
  // is full of them. Bare `/workspace` therefore slips through, which is the
  // price of not flagging every command example in every document.
  const ABSOLUTE = /(?:^|[\s(`"'])((?:\/[A-Za-z_$][\w.$-]*\/[\w.$-]|[A-Za-z]:[\\/]|\\\\)[^\s)`"']*)/gm;
  for (const path of markdownFiles()) {
    for (const [, hit] of readFileSync(path, 'utf8').matchAll(ABSOLUTE)) {
      if (PORTABLE_ROOTS.test(hit)) continue;
      fail(`${rel(path)}: contains a machine-specific absolute path (${hit.slice(0, 44)}…)`);
      break;
    }
  }

  // (f) A skill the manifest does not list is a skill the plugin does not ship.
  const plugin = readJson(join(root, '.claude-plugin', 'plugin.json'));
  const listed = new Set((plugin.skills ?? []).map((entry) => entry.replace(/^\.\/skills\/|\/$/g, '')));
  for (const skill of skills) {
    if (!listed.has(skill)) fail(`skills/${skill} is not listed in plugin.json skills[]`);
  }

  // (g) Two manifests, one version. They are read by different installers, and a
  // mismatch means the two channels ship different things under one name.
  const marketplace = readJson(join(root, '.claude-plugin', 'marketplace.json'));
  const entry = (marketplace.plugins ?? []).find((candidate) => candidate.name === plugin.name);
  if (!entry) {
    fail(`marketplace.json has no plugins[] entry named ${plugin.name}`);
  } else if (entry.version !== plugin.version) {
    fail(`version mismatch: plugin.json ${plugin.version} vs marketplace.json ${entry.version}`);
  }
}

/**
 * The seam check.
 *
 * `repro` decides what to capture and `easy-cast` publishes it, and the
 * obligation that somebody *looked* at each frame lives in the gap between them.
 * No CLI can check it. What can be checked is that the run wrote down what it
 * saw — so every artifact the spec names must appear under `reviewed:` in
 * notes.md, and a "not reproduced" verdict must have an iteration log behind it.
 */
function checkRun(runDir) {
  const specPath = join(runDir, 'spec.json');
  const notesPath = join(runDir, 'notes.md');

  let spec;
  try {
    spec = readJson(specPath);
  } catch (error) {
    fail(`${specPath}: could not read the spec — ${error.message}`);
    return;
  }

  let notesBody;
  try {
    notesBody = readFileSync(notesPath, 'utf8');
  } catch {
    fail(`${notesPath} is missing. A run that reviewed nothing has nothing to publish.`);
    return;
  }

  const paths = (spec.sections ?? []).flatMap((section) => [
    ...(section.artifacts ?? []).map((artifact) => artifact.path),
    ...(section.compare ? [section.compare.before?.path, section.compare.after?.path] : []),
  ]).filter(Boolean);

  // All four headings, so a run cannot answer the easy ones and skip the rest.
  // Everything from this heading up to the next top-level `word:` heading, or to
  // the end of the file. Written as an index walk rather than one regex: JS has
  // no `\Z`, and the lookahead spelling of "end of input" is where this went
  // wrong the first time.
  const headings = [...notesBody.matchAll(/^([a-z][\w -]*):[ \t]*/gm)];
  const section = (name) => {
    const index = headings.findIndex((match) => match[1] === name);
    if (index === -1) return undefined;
    const start = headings[index].index + headings[index][0].length;
    const end = index + 1 < headings.length ? headings[index + 1].index : notesBody.length;
    return notesBody.slice(start, end);
  };
  for (const heading of ['account', 'data', 'iterations', 'reviewed']) {
    if (section(heading) === undefined) fail(`notes.md has no "${heading}:" section`);
  }

  // Bullets under `reviewed:`, each keyed by the path exactly as the spec writes
  // it. Matching on the basename alone would let one line satisfy two different
  // `after.png`s in different directories, and would let `not-after.png` satisfy
  // `after.png`.
  // The bullet is `- <path> — <what I saw>`. Split on the em or en dash only,
  // never the ASCII hyphen: a path may contain spaces *and* hyphens, and
  // `my screenshot - before.png` would otherwise be reviewed as `my screenshot`.
  // Splitting on whitespace instead would truncate at the first space.
  const reviewed = new Set(
    [...(section('reviewed') ?? '').matchAll(/^[ \t]*-[ \t]+(.+)$/gm)].map((match) =>
      match[1].split(/\s+[—–]\s+/)[0].trim(),
    ),
  );
  for (const path of paths) {
    if (!reviewed.has(path)) {
      fail(
        `"${path}" is named in the spec but has no "- ${path}" bullet under "reviewed:" in notes.md — ` +
          'was it opened?',
      );
    }
  }

  const data = (section('data') ?? '').trim();
  if (/NOT SANITISED/i.test(data)) {
    fail('notes.md says the data is NOT SANITISED — this run must be re-recorded, not published');
  } else if (!/^(fixtures|synthetic)\b/i.test(data)) {
    fail(`notes.md "data:" says ${JSON.stringify(data.slice(0, 40))}; expected fixtures, synthetic, or NOT SANITISED`);
  }

  if (/not reproduced/i.test(String(spec.title ?? ''))) {
    const iterations = section('iterations') ?? '';
    if (!/^[ \t]*-[ \t]+\S/m.test(iterations)) {
      fail('a "not reproduced" verdict needs a non-empty "iterations:" log behind it');
    }
  }
}

const [mode, target] = process.argv.slice(2);
if (mode === 'run') {
  if (!target) {
    console.error('usage: node check.mjs run <run-dir>');
    process.exit(2);
  }
  checkRun(target);
} else if (mode === undefined) {
  lint();
} else {
  console.error(`unknown mode ${JSON.stringify(mode)}; expected nothing, or "run <run-dir>"`);
  process.exit(2);
}

for (const note of notes) console.log(`note: ${note}`);
if (failures.length > 0) {
  for (const failure of failures) console.error(`FAIL ${failure}`);
  console.error(`\n${failures.length} check(s) failed`);
  process.exit(1);
}
console.log(mode === 'run' ? `ok — ${target} reviewed everything it names` : 'ok');
