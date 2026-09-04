# Claude Code Config Starter

Portable [Claude Code](https://claude.com/claude-code) configuration: global
context, a curated skill library, and a Codex-backed development pipeline. Clone
this repo on any machine, run `install.sh`, and Claude Code is ready with the
full setup.

This is Ali's fork of
[AidenSbVevo/claude-code-starter](https://github.com/AidenSbVevo/claude-code-starter)
(kept as the `upstream` remote). What differs from upstream: the hook *scripts*
moved to the private `agent-hooks` repo (one core per rule, shared with Cursor,
parity-tested) so this repo only registers them; `attribution` is suppressed;
`CLAUDE.md` imports a machine-local `git-identity.md`; and everything
machine-specific lives in a gitignored `settings.local.json`. The one thing to
customize on a new machine is the "About the User" block in
[`CLAUDE.md`](CLAUDE.md).

Clone it under `~/phd/`: on this machine git and `gh` identity follow the
repo's tree (`~/.claude/git-identity.md`), and a clone anywhere else cannot
commit.

> **This repo ships no hook scripts.** `settings.json` registers ten hooks by
> path under `~/.claude/hooks/`, but the scripts come from the separate,
> private [`agent-hooks`](https://github.com/AliChegini97/agent-hooks) repo —
> clone it to `~/phd/agent-hooks` and run its `install.sh` (step 4 below).
> Until you do, `install.sh` here prints "registered but not installed" for
> each one and Claude Code treats every missing script as a non-blocking hook
> error: tools still run, the guardrails are simply absent.

**Contents:** [Quick Start](#quick-start) ·
[New Machine Setup](#new-machine-setup) ·
[What's Included](#whats-included) ·
[Skill Library](#skill-library) ·
[The Dev Pipeline](#the-dev-pipeline) ·
[How It Works](#how-it-works) ·
[Customization](#customization)

## Quick Start

```bash
git clone git@github.com:AliChegini97/claude-code-starter.git ~/phd/claude-code-starter
cd ~/phd/claude-code-starter
./install.sh                  # links CLAUDE.md + skills into ~/.claude/, writes the merged settings.json
~/phd/agent-hooks/install.sh  # links the hook scripts that settings.json registers
claude                        # launch — everything is loaded
```

## New Machine Setup

```bash
# 1. Claude Code (requires Node.js 18+)
npm install -g @anthropic-ai/claude-code

# 2. Codex CLI — powers the cross-review / ship-issue pipeline
#    (install per OpenAI's instructions, then authenticate)
codex login

# 3. Clone and install this config (under ~/phd — identity follows the tree)
git clone git@github.com:AliChegini97/claude-code-starter.git ~/phd/claude-code-starter
cd ~/phd/claude-code-starter && ./install.sh

# 4. Hook scripts (private repo; settings.json only registers them)
git clone git@github.com:AliChegini97/agent-hooks.git ~/phd/agent-hooks
~/phd/agent-hooks/install.sh   # also seeds ~/.config/agent-identity.env
```

The pipeline **degrades gracefully** without Codex — cross-review falls back to
a Claude-side adversarial pass (a mandatory independent reviewer; decorrelation
is lost, review is not) and flags the substitution at the next gate — so step 2
is optional if you don't use the Linear-driven flow.

## What's Included

### `settings.json` — permissions, hooks, plugins
Full tool permissions (Bash/Read/Write/Edit/Glob/Grep/WebFetch/WebSearch/Task)
with a **deny list guarding the credential surface** — `Read(...)` rules for
the `agent-hooks` secret-path list (`.env*`, `~/.ssh`, `~/.aws`, `~/.config/gh*`,
`~/.kube`, the token files), an `Edit(...)` mirror for the same stores plus
`~/.gitconfig` and its per-tree fragments, and `Bash(sudo:*)`; regenerate from
`agent-hooks/docs/secret-paths-claude.md` — the MCP allow-list this config relies on (Linear and Google
Drive reads promptless; Drive writes and Linear project/milestone writes
prompt-on-use so skill-level approval gates hold), `xhigh` effort, and the
SessionStart/guardrail hooks below, and `attribution` set to empty strings so
Claude never adds Co-Authored-By / "Generated with" footers (the
`attribution-veto` hook is the backstop). It is **fully portable** — no
machine-absolute paths and no machine-taste keys — so the same tracked file
works on every machine.

Everything machine-specific lives in **`settings.local.json` next to it in this
repo, gitignored**: the plugin-marketplace path (the location of this clone), the
`~/.claude` access grant, and taste keys (model, theme, tui, outputStyle,
ultracode, voice, push-notifications, …). `install.sh` seeds that file (deep-merge,
never overwriting an existing value) and then writes the **real file**
`~/.claude/settings.json` = deep-merge(`settings.json`, `settings.local.json`).
Claude Code reads exactly five settings levels — managed, `--settings`,
`<project>/.claude/settings.local.json`, `<project>/.claude/settings.json`, and
`~/.claude/settings.json` — so a user-level `~/.claude/settings.local.json` is
**not** read (earlier versions of this installer wrote there; the installer
migrates that file once). Paths go in the local file because settings files do
not expand `$HOME`/`~`
([anthropics/claude-code#4276](https://github.com/anthropics/claude-code/issues/4276)).
To change a machine-local value, edit `settings.local.json` and re-run
`./install.sh`; do not hand-edit `~/.claude/settings.json` — it is regenerated
(and `/config` changes land there, so copy them into `settings.local.json`).

### Hooks — registered here, implemented in `agent-hooks` (no scripts in this repo)
`settings.json` registers ten hook scripts by file name under `~/.claude/hooks/`.
The scripts live in the private `agent-hooks` repo (`~/phd/agent-hooks`): each
rule is implemented **once** as a platform-agnostic core with a thin Claude
Code adapter and a thin Cursor adapter, and a parity suite proves both editors
decide identically. `~/phd/agent-hooks/install.sh` symlinks the adapters in;
this installer only warns when a registered script is missing. The identity
hooks read the machine's tree→identity mapping from
`~/.config/agent-identity.env` (outside every repo, never committed) and no-op
where it is absent, so the registration itself stays portable.

- **`session-context.sh`** (SessionStart) — injects branch, behind-count vs
  freshly-fetched `origin/<default>` (fetch capped at ~5s, startup only), and
  dirty-file count; on startup also a `[starter-drift]` line when this repo,
  cursor-starter or agent-hooks is dirty. Installs the scratch excludes.
- **`identity-env.sh`** (SessionStart + CwdChanged) — writes the current
  tree's `GH_CONFIG_DIR` into `CLAUDE_ENV_FILE`, so plain `gh` inside `~/phd`
  or `~/work` uses that tree's login; leaving both trees clears it (`gh` is
  logged out there by design).
- **`attribution-veto.sh`** (PreToolUse: Bash, blocking) — denies `git commit`
  / `gh pr create|edit` whose text carries AI attribution (Co-Authored-By
  trailer, "Generated with <tool>", Cursor/Claude footers) — including inside
  files passed via `-F`/`--file`/`--body-file`/`--template`. One marker list
  for both editors. `settings.json` also sets `attribution` to empty so the
  model is never told to add a footer; the hook is the backstop.
- **`gate-guard.sh`** (PreToolUse: Bash, blocking) — on a branch with an
  active ship-issue plan (`.plans/<issue-id>.md`), denies `git push` /
  `gh pr create` until `.plans/<issue-id>.approved` exists — the SHIP GATE as
  a mechanism, not prose. Resolves the target repo from the command
  (`git -C`, `cd` chains) and the agent's cwd, so worktrees are gated too.
- **`scratch-guard.sh`** (PreToolUse: Bash) — asks for confirmation when a
  `git add` would stage `.plans/` or `.review/`; keeps both dirs in the
  shared `.git/info/exclude` (worktrees included).
- **`identity-guard.sh`** (PreToolUse: Bash, blocking) — denies
  `gh auth login|switch|setup-git|token`, identity-config writes
  (`git config user.*`, `-c user.*`, `--author`, `GIT_AUTHOR_*`, `GH_TOKEN=`),
  HTTPS GitHub remotes, the other tree's identity files, and `direnv exec`
  into another tree. Read forms (`git config user.email`) stay allowed.
- **`secrets-shell-guard.sh`** (PreToolUse: Bash, blocking) — the shell twin
  of the `Read(...)` deny list: command tokens under a secret path, `sudo`,
  keychain readers; `.env*` asks instead of denying.
- **`worktree-guard.sh`** (PreToolUse: Bash, blocking) — `git worktree add`
  must stay in the repo's identity tree and `git clone` in the session's tree
  (never `/tmp`, never `~/.cursor`).
- **`format-fast-check.sh`** (PostToolUse: Edit/Write) — runs the repo's own
  formatter (ruff/black/prettier/rustfmt/gofmt) on the edited file only, plus
  a fast lint; real findings are fed back to Claude (exit 2 — the edit
  stands); a crashing linter is never reported as findings.
- **`retro-nag.sh`** (Stop) — when a shipped issue (`.approved` marker
  present) has no `RETRO <issue>` line in `.review/journal.md`, blocks the
  stop **once** with a reminder (once per issue across both editors).

Every adapter allows on any internal error. The deliberate blocks are the
attribution veto, the ship gate, the identity / secrets / worktree denies, the
one-time retro reminder, and lint findings surfaced to the model. Cursor gets
the same rules from `~/.cursor/hooks.json` (cursor-starter), plus a
`tool-path-guard` for its editor and search tools; Claude covers that surface
with the `Read(...)`/`Edit(...)` deny rules instead.

### `CLAUDE.md` — global context
Loaded into every session: working environment, code standards, interaction
preferences, and the **dev-pipeline conventions** block (one-writer rule, hard
gates, fresh-base, no AI attribution, `uv` for Python, scratch dirs,
superpowers interop, the debugging route) — the single home for standing rules
promoted by ship-issue retros.

## Skill Library

Skills are ambient knowledge — each ships a `SKILL.md` whose description Claude
matches against your request. Say something that sounds like the trigger and
the skill activates on its own; you can also name one explicitly ("use the viz
skill"). Each entry below: what the skill does, then *phrases that trigger it*.

### Dev pipeline

The disciplined Linear-issue → PR flow — design and Codex setup in
[The Dev Pipeline](#the-dev-pipeline) below.

- **`epic-planning`** — turns a goal, epic, or feature area into one-PR-sized
  Linear issues, each with acceptance criteria and verification commands;
  files them only after explicit approval.
  *"scope out the auth epic"*, *"break this into tickets"*
- **`ship-issue`** — drives a Linear issue end-to-end to a shipped PR:
  plan + decorrelated review, hard **plan gate**, TDD (or
  subagent-driven-development for large plans), diff review, a dedicated
  **test-quality review**, hard **ship gate** (machine-enforced by
  `gate-guard.sh`), PR follow-through, Linear update, mandatory retro. Also
  runs **anchorless** from a spec path or plain description — same gates, no
  Linear bookends. Prefer it over ad-hoc implementation whenever a Linear
  issue ID is the starting point.
  *"start ABC-123"*, *"take ABC-42 to a PR"*
- **`execute-epic`** — the sequencer between epic-planning and ship-issue:
  re-derives epic state from Linear each session, picks the next unblocked
  issue in dependency order, drives it through ship-issue (its gates fire
  unchanged), records dispositions, rolls up the epic at the end.
  *"run the epic"*, *"next issue in the epic"*, *"continue the epic"*
- **`cross-review`** — decorrelated second opinion from local Codex (read-only
  `codex exec --profile review`) on a plan or a diff; findings triaged
  FIX / REBUT / ESCALATE with one bounded verification pass (discovery-only
  variant for pre-code artifacts). Falls back to a Claude adversarial pass
  when Codex is unavailable. Invoked automatically at ship-issue's
  checkpoints, or standalone.
  *"cross-review this diff"*, *"get a second opinion"*, *"ask codex"*

### Engineering

- **`ml-engineer`** — ML/AI systems end to end: training and fine-tuning
  pipelines, LLMs (LoRA/QLoRA, RLHF/DPO, quantization, vLLM), agentic
  workflows, RAG, evaluation/benchmarking, experiment tracking, model serving,
  PyTorch/JAX/TensorFlow.
  *"debug this training loop"*, *"add LoRA fine-tuning"*, *"build a RAG eval"*
- **`software-dev`** — senior-engineer project mechanics: scaffolding new
  projects, `uv`/conda environments, Dockerfiles, CI/CD pipelines, testing,
  packaging and publishing, CLIs and APIs, pre-commit hooks, productionizing
  prototype code.
  *"set up CI for this repo"*, *"package this as a library"*
- **`frontend-engineer`** — React/Next.js/TypeScript apps, dashboards and
  admin panels, interactive data viz (D3, Plotly, Recharts, deck.gl,
  Three.js), Python dashboards (Dash, Streamlit, Gradio), state management,
  real-time UIs, Tailwind, Vitest/Playwright testing.
  *"build an admin panel for this API"*, *"the websocket UI drops updates"*
- **`ui-designer`** — how a UI should look and feel: layouts, component
  libraries, visual hierarchy, color systems and theming, typography, design
  tokens, dark/light mode, accessibility, wireframes, design critique.
  *"critique this dashboard's layout"*, *"design tokens for our brand"*
- **`viz`** — production-quality charts and figures: choosing the right chart
  type, matplotlib/seaborn/plotly/Altair and R/ggplot2, multi-panel figures,
  colorblind-safe palettes, ML-evaluation plots (ROC/PR, confusion matrix,
  calibration).
  *"make this figure publication-ready"*, *"which chart type for this data?"*

### Delivery

- **`linear-issues`** — creates, updates, comments on, and closes Linear
  issues in a consistent house style (TL;DR/Resolution header, type-specific
  bug/feature/research/infra sections), drafting from git/PR context and
  filing via the Linear MCP after approval.
  *"file a bug for this"*, *"write the resolution for ENG-142"*
- **`handoff`** — ends a long session cleanly instead of relying on
  auto-compaction: writes a curated `HANDOFF.md` at the repo root (reading
  order, git state, decisions made, things to avoid, next concrete action) so
  a fresh session can pick up at full speed.
  *"/handoff"*, *"context is filling — let's start fresh"*

### Security review

`security-audit` is the orchestrator; the `tob-*` bundles are a
Trail-of-Bits-style audit toolkit. The bundles are plugin-layout (nested
`skills/`, `agents/`, `commands/`), so they install as **plugins** via the
local marketplace, not as personal skills — see
**Plugins on a new machine** under [File Structure](#file-structure).

- **`security-audit`** — multi-phase audit orchestrator for whole codebases:
  static analysis, supply-chain audit, insecure defaults, sharp edges, variant
  and differential analysis — ending in a severity-ranked markdown report.
  *"run a security audit"*, *"check this project for vulnerabilities"*
- **`tob-static-analysis`** *(plugin)* — Semgrep scans with parallel
  per-language workers, CodeQL interprocedural data-flow and taint tracking,
  and SARIF parsing/dedup for either.
  *"run semgrep"*, *"scan with codeql"*, *"parse these scan results"*
- **`tob-audit-context`** *(plugin)* — ultra-granular, line-by-line context
  building before bug hunting (includes a per-function analyzer agent), so
  findings rest on real architectural understanding.
  *"build audit context for this codebase"*
- **`tob-differential-review`** *(plugin)* — security-focused review of a
  specific change (PR, commit, diff): blast radius, git-history context, test
  coverage, security-regression detection.
  *"security-review this PR"*, *"/diff-review"*
- **`tob-variant-analysis`** *(plugin)* — after one bug is found, hunts its
  siblings across the codebase with pattern-based analysis and generated
  CodeQL/Semgrep queries.
  *"find variants of this vulnerability"*
- **`tob-supply-chain`** *(plugin)* — flags dependencies at heightened risk of
  exploitation or takeover; scopes supply-chain attack surface.
  *"audit our dependencies"*
- **`tob-insecure-defaults`** *(plugin)* — detects fail-open defaults that let
  an app run insecurely in production: hardcoded secrets, weak auth,
  permissive security config.
  *"check for insecure defaults"*
- **`tob-sharp-edges`** *(plugin)* — identifies error-prone APIs, dangerous
  configurations, and footgun designs; evaluates code against
  secure-by-default principles.
  *"where are the footguns in this API?"*

### Authoring & platform

- **`skill-creator`** — create, improve, and eval-test skills; ships
  eval-runner, grader, benchmark, viewer, and description-optimizer scripts.
  *"create a skill for X"*, *"optimize this skill's description"*
- **`mcp-builder`** — build high-quality MCP servers in Python (FastMCP) or
  TypeScript (MCP SDK), with tool-design best practices, transport guidance,
  and a runnable eval harness.
  *"expose this API as MCP tools"*
- **`claude-api`** — build apps on the Claude API, Anthropic SDKs, or Agent
  SDK (not for other AI SDKs or general ML work).
  *"add tool use to this anthropic client"*
- **`pdf`** — anything PDF: extract text/tables/images, merge, split, rotate,
  watermark, fill forms, encrypt/decrypt, OCR scanned documents, create new
  PDFs.
  *"fill this PDF form"*, *"merge these reports into one PDF"*

## The Dev Pipeline

`epic-planning` → `execute-epic` → `ship-issue` → `cross-review` (described in
the [Skill Library](#skill-library) above) implement a disciplined
Linear-issue → PR flow built on three ideas. See
[`docs/project-workflow.md`](docs/project-workflow.md) for how Linear projects,
epics, and issues structure the work — and why we size each issue to one session
and one PR.

- **One writer.** Claude is the only writer; Codex reviews read-only — an
  independent failure distribution whose blind spots don't correlate with the
  implementer's.
- **Gates are real stops.** ship-issue's **plan gate** and **ship gate** wait
  for explicit human approval — never a banner walked past in the same turn.
- **Verifiers vs. critics.** Iterate unboundedly against verifiers (tests,
  types, lint — loop to green) but boundedly against critics (model reviews:
  1 discovery + 1 verification pass, 1 exchange per contested finding);
  surviving disagreements escalate to the human at a gate. A mandatory retro
  turns recurring findings into config diffs.

The pipeline treats the superpowers plugin's planning skills as **scoped
subroutines, never the pipeline**: brainstorming produces the spec
(`docs/specs/`, committed on the work branch) and returns control;
writing-plans contributes its task *format* (plans stay scratch in `.plans/`);
subagent-driven-development is the execution engine for large plans — while
the gates, cross-review, and retro always remain ship-issue's. The standing
rules live in `CLAUDE.md`'s dev-pipeline block.

**Codex setup:** the recommended Codex configuration lives in the
[`codex/`](codex/) directory — `config.reference.toml` (global model/reasoning
to merge into `~/.codex/config.toml`) and `review.config.toml` (the read-only,
no-approvals, max-reasoning `review` profile — copy to
`~/.codex/review.config.toml`, which is where current Codex CLI reads
standalone profiles). cross-review invokes it with
`codex exec --profile review` and additionally hardcodes `--sandbox read-only`
per command — the one-writer rule is enforced belt-and-suspenders, not by the
profile alone.

## How It Works

`install.sh` creates **symlinks** from `~/.claude/` into this repo for
`CLAUDE.md` and `skills/`, and writes `~/.claude/settings.json` as a merged
real file (see `settings.json` above). Hook scripts are linked into
`~/.claude/hooks/` by `agent-hooks/install.sh`, not by this repo:

- Edits to skills and `CLAUDE.md` in the repo are reflected immediately — no
  re-install needed. Edits to either settings file need `./install.sh`; hook
  behaviour changes happen in `agent-hooks` (run its parity suite there).
- `git pull` on any machine updates everything (re-run `./install.sh` if
  `settings.json` changed).
- `install.sh` prunes dangling symlinks and backs up any real files it replaces.
- `uninstall.sh` removes only the symlinks, leaving backups and the merged
  `~/.claude/settings.json` intact.

## File Structure

```
claude-code-starter/
├── install.sh              # symlinks skills/CLAUDE.md; merges settings into ~/.claude/settings.json; checks registered hooks exist
├── uninstall.sh            # removes the symlinks (hook links: agent-hooks/uninstall.sh)
├── settings.json           # permissions, hooks, plugins, attribution (portable; no abs paths)
├── settings.local.json     # per-machine paths + taste keys (gitignored; created by install.sh)
├── CLAUDE.md               # global session context + pipeline conventions
│                           # (hook scripts: ~/phd/agent-hooks — registered in settings.json)
├── .claude-plugin/
│   └── marketplace.json    # local marketplace serving the tob-* plugins
├── codex/
│   └── config.reference.toml   # recommended Codex CLI setup for the pipeline
└── skills/                 # ambient knowledge (auto-invoked)
    ├── epic-planning/ execute-epic/ ship-issue/ cross-review/
    ├── ml-engineer/ software-dev/ frontend-engineer/ ui-designer/ viz/
    ├── linear-issues/ handoff/
    ├── security-audit/ tob-*/          # tob-* install as plugins, not skills
    └── skill-creator/ mcp-builder/ claude-api/ pdf/
```

**Plugins on a new machine:** `install.sh` covers skills, settings, the
hook-registration check, **and the marketplace registration** — it writes this clone's path into
`settings.local.json` (merged into `~/.claude/settings.json`), so there's no
`claude plugin marketplace add` step and nothing is machine-absolute in the
tracked config. The tob-* security
plugins still need a one-time install:

```bash
for p in audit-context differential-review insecure-defaults sharp-edges \
         static-analysis supply-chain variant-analysis; do
  claude plugin install "$p@claude-code-config"
done
```

## Customization

**Add a skill:**
```bash
mkdir skills/my-skill
$EDITOR skills/my-skill/SKILL.md   # frontmatter: name + description
./install.sh                        # re-run to symlink it
```

**Project-specific overrides:** create `.claude/settings.local.json` in any
project — gitignored, and it overrides these globals for that project only.

## Uninstall

```bash
cd ~/phd/claude-code-starter && ./uninstall.sh   # this repo's symlinks + nothing else
~/phd/agent-hooks/uninstall.sh                   # the hook symlinks, if wanted
```
