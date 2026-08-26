# How AI was used in this project

This repository is submitted to ETHOnline 2026 under a **Continuity Track**: the codebase
predates the event and is documented as such. This file states, without varnish, where AI was
used, how, and what was done to keep its output honest.

## The short version

AI was used heavily — for drafting, for reading standards, and above all as an **adversary**.
It was never used as an authority. Every claim that survives in this repository survived
because **a deployed contract accepted or rejected it**, not because a model asserted it.

## Where this file answers the event's AI rules

| Rule | Answered in |
|---|---|
| **Attribution** — which parts of the code, which files | §2, per directory, with counts |
| **Involvement** — AI assists, it does not author the project | §3, with commit history and named decisions |
| **Spec-driven work** — ship the files that directed the AI | §4 — `CLAUDE.md` and the guardian hook are in this repository |

## 1. Which tools

| Tool | Role |
|---|---|
| **Claude Code** (Anthropic) | primary drafting: contracts, tests, scripts, prose. Ran inside this repository, under `CLAUDE.md`. |
| **DeepSeek** | adversarial review. Given a contract and told to break it, with no hint as to what checks existed. |
| **Perplexity, ChatGPT, Gemini** | independent refutation passes in the four-family method (§5). Never used for drafting. |

No autocomplete assistant (Copilot, Cursor, or equivalent) was used on this repository.

## 2. Attribution — where AI touched the code

The honest statement first, because a partial one would be worse than none:

> **Every source file in this repository was drafted with AI assistance.** There is no
> hand-written subset to point at. What separates this from generated output is not
> authorship of the first draft — it is what happened to that draft afterwards, which §3
> and §5 document.

121 files are tracked. By area:

| Area | Files | What AI drafted | What that draft went through |
|---|---|---|---|
| `contracts/` | 16 | all Solidity, including the five mandate revisions | compiled, deployed to Base Sepolia, and attacked. V5 entered adversarial review with **7 defects**: 6 found by DeepSeek, 1 by the repository's own bench (an agent surviving 150 days past a lapsed ancestor). All 7 closed before any deployment. |
| `integration/test/` | 27 | all Foundry tests | tests exist *because* a draft claim needed refuting. `V5SixDefauts.t.sol` is one test per defect found by the adversary; `V5Attaque.t.sol` and `V5Totalite.t.sol` likewise. |
| `scripts/` | 24 | deployment and exercise scripts | each was executed against a live chain. A script that was never run is not evidence and is not counted here. |
| `src/` | 12 | the TypeScript agent runtime | exercised by `npm run reproduce` and `tests/invariants.ts`. |
| `method/simulations/` | 4 | the four simulations | they execute and print pass/fail counts. Their described outcomes were rewritten after running them, because the descriptions written from memory were wrong. |
| `method/guardian-tools/` | 2 | the perimeter guard and its suite | 11 conformance cases, 11 conformant. See §4. |
| `interop/`, `conformance/` | 6 | comparison harnesses and the verdict verifier | `standards-map.md` records conclusions drawn from reading 271 ERCs. |
| `eip/`, `whitepaper/`, `vulgarise/` | 6 | prose drafts | argued and revised in public on the standards forum, including where a reviewer refused a position and was right. |

Two git identities appear in the history — `H. Mekaoui <animaticforge_beta@…>` and
`Helmi Mekaoui <helmymekaoui@…>`. Both are the same person, one machine each. No one else
has commit access.

## 3. Involvement — what was not delegated

**54 commits, 30 July to 26 August 2026**, before and during the event. The history is
incremental and public; there is no squashed drop of generated code.

What the human did, that no model did:

- **Chose what the standard would claim, and narrowed it.** On the first day of the
  repository the claim was cut back twice within nine hours (`bb3131f`, `0a3797d`,
  `e0cd972`) after a prior-art reading. Narrowing a claim is not something a drafting model
  proposes.
- **Refused to concede to reviewers on assertion.** When a reviewer reported a contradiction
  in `isActive`, the instruction was to verify it against the deployed source before
  agreeing. It checked out and was conceded; other claims did not and were not.
- **Demanded execution over description.** The standing rule in `CLAUDE.md` is that a
  conformance claim without pasted `npm run check` output is worthless. This rule caught
  the assistant describing simulation outcomes from memory rather than running them.
- **Argued the design in public.** The forum thread is the record; positions changed there,
  in the open, under review by named third parties.
- **Held the line on deployment.** Nothing in V5 reached a chain until all 7 defects were
  closed, over the assistant's readiness to ship.

## 4. How the AI was directed

Both artifacts are tracked in this repository. Neither is a prompt log; both are enforced
constraints that the assistant could not talk its way past.

**`CLAUDE.md`** — read at the start of every session. Its founding line: *the checks are the
source of truth, not the assistant's assertions; the verifier must never be the verified.*
It fixes the inheritance invariants as non-negotiable (`child ⊆ parent`, the telomere only
decreases, the mandate is welded into the identity), forbids touching `.env` or any private
key, requires small diffs shown rather than summarised, and requires that an unfollowable
rule be declared rather than faked.

**`.githooks/pre-commit`** — runs `npm run check` and **refuses the commit** if it fails.
The rule is not advice to a model; it is a gate in the tooling.

**`method/guardian-tools/garde-perimetre-v2.py`** — refuses any write into a locked path,
across every session. It protects itself: its own three files are inside its own locked
list, so no session can grant itself an exemption. Its suite is 11 cases, 11 conformant.

The point worth recording, and the reason this tooling lives in a repository about
inheritable mandates: **it once refused a change the human operator had verbally
authorised.** That was not a bug. A boundary that yields to consent is not a boundary — it
is a suggestion. This is the same claim ERC-8370 makes about agent mandates, demonstrated
on the tooling that built it.

## 5. The method: four model families, one arbiter that is not a model

When a claim about the reference implementation needed testing, four **independent model
families** — DeepSeek, Perplexity, ChatGPT, Gemini — were each given the same three things:

1. the source of the **deployed** contract,
2. the claim to refute,
3. nothing else.

No expected outcomes. No hints about which checks exist. No cross-contamination between
models: none of them saw another's answer.

Each model proposed attack sequences. **Every proposed sequence was then executed** against
the deployed contract on Base Sepolia, or against a local fork. The transaction either
reverted or it did not.

**The chain decided, not the model.**

This inverts the usual objection to AI-assisted security work. The normal complaint is that a
model will produce a confident, plausible, wrong answer. That complaint is correct — and it is
neutralised here, because a model's output is never the verdict. It is only a *candidate*, and
the candidate is executed. A hallucinated attack simply fails to reproduce, and dies.

The results of one such pass are public on the standards forum:
[ERC-8370 thread, post #41](https://ethereum-magicians.org/t/29275/41).

## 6. What is in `method/simulations/`

These are not illustrations. They run, and they print pass/fail counts.

| File | What it establishes |
|---|---|
| `simu.ts` | the same API flaw, twice. Under an **enclosure** (denylist) the agent reaches it and a third party is harmed; under **capabilities** (allowlist) the identical flaw is never reached — not fixed, unreachable. The forbidden name chosen in advance did not match the real function. A denylist only protects against what someone thought to name. |
| `simu2-failles-imprevues.ts` | the same five escape routes, run against both models: **denylist 5/5 exploited, allowlist 0/5**. The denylist carries a debt — every new function in the world requires updating the forbidden list, or it is open by default. Nobody maintains that debt in a system they do not control. |
| `simu3-heritage-plafond.ts` | the telomere bounds the **number of generations**, not the spend: generation 1 born with telomere 1, generation 2 with 0, generation 3 refused. Cap and telomere are **independent** limits — one closes the depth of the lineage, the other the depth of the budget. Both are needed. |
| `simu4-identite-soudee.ts` | identity alone is not enough (an intact agent walks through the unguarded route); granted paths alone are not enough (a self-modifying agent keeps them). And the condition that binds both: **they only have effect where something verifies.** Outside that zone neither is consulted — the honest boundary the EIP's *Off-chain / rogue runtimes* clause already states. |

Written in TypeScript, no dependencies beyond the repo's own toolchain. Comments are in French;
the code is the argument.

## 7. What AI did not do

- It did not decide what the standard should say. Design positions were argued on the public
  forum thread and revised there, in the open, including when a reviewer refused a request and
  was right to.
- It did not validate a single security claim. Every one was executed.
- It did not write the whitepaper's argument. It drafted prose, which was then cut.

## 8. What is deliberately not published

A private working notebook exists and stays private for now: exploratory design ideas that
have not been built, and a set of first-hand incident write-ups. Publishing unbuilt ideas on
the eve of a competition is not transparency, and incident material needs to be stripped of
its origin before it is useful to anyone. The mechanisms drawn from those incidents will be
published separately, anonymised.

This omission is stated here rather than hidden: what is absent is exploratory and
first-person, not evidential. Nothing that supports a claim made in this repository is
withheld.
