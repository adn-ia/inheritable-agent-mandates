# How AI was used in this project

This repository is submitted to ETHOnline 2026 under a **Continuity Track**: the codebase
predates the event and is documented as such. This file states, without varnish, where AI was
used, how, and what was done to keep its output honest.

## The short version

AI was used heavily — for drafting, for reading standards, and above all as an **adversary**.
It was never used as an authority. Every claim that survives in this repository survived
because **a deployed contract accepted or rejected it**, not because a model asserted it.

## The method: four model families, one arbiter that is not a model

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

## What is in `method/`

### `method/simulations/` — four executable simulations

These are not illustrations. They run, and they print pass/fail counts.

| File | What it establishes |
|---|---|
| `simu.ts` | the same API flaw, twice. Under an **enclosure** (denylist) the agent reaches it and a third party is harmed; under **capabilities** (allowlist) the identical flaw is never reached — not fixed, unreachable. The forbidden name chosen in advance did not match the real function. A denylist only protects against what someone thought to name. |
| `simu2-failles-imprevues.ts` | the same five escape routes, run against both models: **denylist 5/5 exploited, allowlist 0/5**. The denylist carries a debt — every new function in the world requires updating the forbidden list, or it is open by default. Nobody maintains that debt in a system they do not control. |
| `simu3-heritage-plafond.ts` | the telomere bounds the **number of generations**, not the spend: generation 1 born with telomere 1, generation 2 with 0, generation 3 refused. Cap and telomere are **independent** limits — one closes the depth of the lineage, the other the depth of the budget. Both are needed. |
| `simu4-identite-soudee.ts` | identity alone is not enough (an intact agent walks through the unguarded route); granted paths alone are not enough (a self-modifying agent keeps them). And the condition that binds both: **they only have effect where something verifies.** Outside that zone neither is consulted — the honest boundary the EIP's *Off-chain / rogue runtimes* clause already states. |

Written in TypeScript, no dependencies beyond the repo's own toolchain. Comments are in French;
the code is the argument.

### `method/guardian-tools/` — the constraint that refused its author

`garde-perimetre-v2.py` is a hook that refuses any write into a locked path, across every
session of the assistant driving this repository. It protects itself: its own three files are
inside its own locked list, so no session can grant itself an exemption.

`test-garde.py` is its conformance suite: **11 cases, 11 conformant**.

The point worth recording, and the reason this file is in a repository about inheritable
mandates: **it once refused a change that the human operator had verbally authorised.** That
was not a bug. A boundary that yields to consent is not a boundary — it is a suggestion. This
is the same claim ERC-8370 makes about agent mandates, demonstrated on the tooling that built
it.

## What AI did not do

- It did not decide what the standard should say. Design positions were argued on the public
  forum thread and revised there, in the open, including when a reviewer refused a request and
  was right to.
- It did not validate a single security claim. Every one was executed.
- It did not write the whitepaper's argument. It drafted prose, which was then cut.

## What is deliberately not published

A private working notebook exists and stays private for now: exploratory design ideas that
have not been built, and a set of first-hand incident write-ups. Publishing unbuilt ideas on
the eve of a competition is not transparency, and incident material needs to be stripped of
its origin before it is useful to anyone. The mechanisms drawn from those incidents will be
published separately, anonymised.

This omission is stated here rather than hidden: what is absent is exploratory and
first-person, not evidential. Nothing that supports a claim made in this repository is
withheld.
