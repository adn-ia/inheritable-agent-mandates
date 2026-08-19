# `method/` — how the claims in this repository were tested

This folder holds the working artifacts behind the project's security claims. It is referenced
from [`../AI-USAGE.md`](../AI-USAGE.md), which explains the method itself.

Nothing here is decorative. Every file runs.

## `simulations/`

Four executable simulations, TypeScript. Run them with the repo's toolchain.

- **`simu.ts`** — the same API flaw, bounded two ways. Under an enclosure (denylist), the
  agent reaches it and a third party is harmed. Under capabilities (allowlist), the identical
  flaw is never reached: it was not fixed, it became unreachable. The forbidden name chosen in
  advance (`supprimerMembre`) did not match the real function. A denylist protects only against
  what someone thought to name.
- **`simu2-failles-imprevues.ts`** — five escape routes, both models: **denylist 5/5 exploited,
  allowlist 0/5**. The denylist carries a debt: every function added to the world requires
  updating the forbidden list, or it is open by default. Nobody maintains that debt in a system
  they do not control. The allowlist has no debt — the world may grow without bound, the
  agent's surface does not move.
- **`simu3-heritage-plafond.ts`** — the telomere bounds the *number of generations*, not the
  spend. Generation 1 is born with telomere 1, generation 2 with 0, generation 3 is refused.
  Cap and telomere are independent limits: one closes the depth of the lineage, the other the
  depth of the budget. Both are required.
- **`simu4-identite-soudee.ts`** — identity alone is insufficient: an intact agent simply takes
  the unguarded route. Granted paths alone are insufficient: an agent that modifies itself keeps
  them. And the condition binding both — **they only have effect where something verifies.**
  Outside that zone, neither identity nor capability is consulted. That is the honest boundary
  of the standard, already stated in the *Off-chain / rogue runtimes* clause.

## `guardian-tools/`

- **`garde-perimetre-v2.py`** — a write-refusing hook, active across every assistant session
  touching this repository. Its own files sit inside its own locked list, so no session can
  authorise itself out of it.
- **`test-garde.py`** — its conformance suite. 11 cases, 11 conformant.

The guardian is included because it demonstrates, on the tooling rather than on-chain, the
claim the standard makes: **a boundary that can be lifted by the party it constrains is not a
boundary.** It once refused a change its own operator had approved out loud. That is the
behaviour it was built for.

## What this folder is not

It is not the test suite. The contract's invariants live in `../tests/` and run with
`npm run check`; the reproducible end-to-end demonstration is `npm run reproduce`. This folder
holds the *reasoning* artifacts — the things that decided what to build, before there was
anything to test.
