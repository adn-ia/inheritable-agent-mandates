# Inheritable Agent Mandates
### A non-strippable, identity-anchored leash for autonomous on-chain AI agents

**Author:** Helmy Mekaoui · **Version:** 0.8 (draft) · **Date:** 2026-09-01
**Companion artifacts:** a reference contract (`InheritableAgentMandate`) **deployed and exercised on Base mainnet** (Sourcify `exact_match`); **thirteen contracts live on Base Sepolia**, including three mandate revisions and three gates; a working prototype (M0/M1/M3); an on-chain schnorr-verifying gate independently cross-checked with a third party; **142 machine tests** that gate every commit; **a map of 271 ERCs** with its method published; and the draft standard **ERC-8370, "Inheritable Agent Mandates,"** under editor review as pull request #1930.

> A note before we start. This is a working draft, written by one person, and I've tried to
> keep it honest rather than impressive. It says what the idea is, what I've actually built,
> and — on purpose — where it falls apart. Wherever a claim leans on guesswork or on reporting
> I couldn't verify, I say so out loud. If you're here to poke holes, head straight for §6 and
> §7; that's where the soft spots are, and I'd rather you find them than a customer. If you read
> v0.7, the changes are concentrated in §1, §4, §5 and §8 — and one correction in §3, where a
> measurement showed my own justification was wrong.

---

## Abstract

AI agents are starting to hold money on-chain and to **spawn copies of themselves** to get
work done in parallel. The guardrails we have today all share one blind spot: they're attached
to a *single* account. Spend limits, session keys, policy engines — each one leashes one agent.
None of them follows that agent's *children*. So the moment an agent spawns a copy, its limits
are gone — the child is born unbound. Not because those tools fail at what they set out to do, but
because none of them sets out to define what a child inherits.

What I'm proposing is a leash that the children inherit. Concretely: a small **mandate** — a
spending allowance, an expiry, a reproduction allowance, a required "still alive?" check, an
allowed-payees list, and a kill switch — that is (1) welded to the agent's on-chain **identity**,
(2) **passed down automatically** to any child it spawns, and (3) **impossible to shed** — if
the agent tries to edit its own limits it changes its identity and stops being recognised.

Every clause travels the same way: a child's mandate can only ever be *tighter* than its parent's —
its spend cap no higher, its expiry no later, its payees a subset — and what it may actually spend is
bounded by the smallest cap along its whole lineage. Reproduction is held down separately by a
generation counter (a "telomere") that only ever counts down. A child can only ever be *less* capable
than its parent, never more.

One word does a lot of work here — "inheritance" — and it's overloaded, so let me pin it down.
I do **not** mean inheritance of *ownership* (handing an agent to an heir, à la ERC-42424), nor
of *permissions* (copying the same grants onto many agents, as enterprise IAM does). I mean
inheritance of **limits**, passed from parent to child, that can't be loosened (§1.1).

And the ambition is smaller than it sounds: I'm not building an unstoppable, sovereign AI. I'm
building a *governable* one. The blockchain here is **one layer** of a stack — the part that
anchors identity and enforces the rule — sitting alongside economic, human, and model-level
controls. It is not a magic wand, and I'll be blunt about what it can't do.

---

## 1. The gap I'm trying to fill

The controls shipping today are genuinely good. Coinbase's CDP Policy Engine enforces spend
limits and allow/deny lists at the moment of signing, inside a secure enclave. thirdweb's
session keys scope what a delegated key may call and spend. MetaMask's Agent Wallet ships with
daily caps, protocol allowlists, and a human tap for anything out of policy. On the standards
side, ERC-8226 and thirdweb's Asset-Enforced Spend Mandate carry exactly the right *clauses* —
caps, expiry, freeze — and ERC-8004 gives an agent a portable on-chain identity. And through 2026
a wave of agent ERCs has gone further: ERC-8312 ("Bounded Agent Actions") meters an
agent's spend against a granted capability tree *bound to its ERC-8004 identity*, deployed on
testnet — and its authors have specified an aggregate-budget profile for *delegation trees*: one
shared spend cap metered across an agent and the sub-agents it spawns, with the obvious escape
("a capped node mints an uncapped child") explicitly closed. So not only "control clauses bound to
identity" but even *aggregate spend across a spawned tree* is now being specified, not hypothetical.
What's still missing is narrower: the inheritance of the **whole mandate** — not the spend total but
the payees, the expiry, the cascading freeze, the generation counter — welded to identity so it
can't be shed, bounding what each spawned child is *allowed to be*, clause by clause, rather than
only what the tree may collectively spend.

The remaining hole is specific. The wallet-level controls (CDP, session keys, ERC-8226) are attached
to a *single* instance and float free of identity — they don't travel to a child at all. The one
place a control *does* travel to a spawned tree — ERC-8312's delegation-budget profile — carries an
aggregate *spend* cap, but not the rest of the leash. What doesn't yet travel, welded to identity and
non-strippable, is the **whole mandate** — payees, expiry, cascading freeze, generation counter —
bounding what each child is *allowed to be*, clause by clause, not only what the lineage may spend.

Since v0.7 I stopped asserting that and went and counted. Titles mislead badly in this space —
"agent", "delegation" and "permission" turn up in proposals with nothing to do with one another —
so the corpus was ranked by content, not by name. Every ERC in `ethereum/ERCs` was listed (**611
files**); those numbered ≥ 7000 were kept (**271**); their full text was downloaded, about 5.1 MB,
and scored against eleven concept patterns — delegation, attenuation, sub-agent, inheritance, cap,
revocation, expiry, identity, AI-agent, caveat, session. The top of that ranking was then read end
to end, specification *and* discussion thread. The method is published with the map so it can be
checked rather than believed.

**None of the 271 standardizes attenuated re-delegation:** a child that comes into existence
already bounded by its parent, on every clause, with the bound non-strippable.

And the nearest candidate deserves precision rather than a claim of victory. ERC-8226's mandate is
keyed by `(agent, principal)` and only the principal can grant, so an agent holding a valid mandate
cannot create anything at all. Grepping its reference implementation for the vocabulary of lineage
— `child|parent|sub-?agent|inherit|lineage|spawn|attenuat` — returns only `@inheritdoc`, a
documentation tag. The concept is absent from the code, not merely from the prose. **That is not a
defect.** One of its authors said so directly on my own thread, and was right: under their model a
spawned child inherits nothing, *including the authority to act*, so reproduction cannot be used to
escape a mandate. Inheritance is out of scope by design. The honest phrasing is "ERC-8226 does not
define mandate inheritance," never "ERC-8226 can be bypassed." The same care applies to the rest:
8199 refuses granular sharing on principle, 8273 is transaction-scoped by construction, 7715 is a
request protocol rather than an enforcement layer. Four different answers to four different
questions, none of them an oversight.

**The square is empty because nobody has claimed it, not because everybody missed it.** That is a
weaker and more useful statement than novelty, and it is the one the evidence supports.

### 1.1 — Two things that share my word but aren't my idea

Two visible efforts in 2026 also say "inheritance," and if I don't separate them cleanly, the
first reply I'll get is "isn't this just X?" So, plainly:

**ERC-42424, "Inheritance Protocol for On-Chain AI Agents."** Its "inheritance" is a *will*: an
owner names an heir, the heir claims the agent, or a community vote reassigns it. It's about
*continuity of ownership* when a human owner disappears — who holds the leash next. No spend
caps, no kill switch, no limit passed to children. A different question than mine.

**Microsoft Entra's "inheritable permissions."** Its "inheritance" is a *convenience*: grant a
permission to a blueprint once, and every agent made from it gets it. Microsoft's own docs say
it is *"not a permission limiter."* Its job is to *widen*. Mine is to *narrow*.

| "Inheritance" of… | Example | What travels down | Direction |
|---|---|---|---|
| Ownership (a will) | ERC-42424 | who owns the agent next | handoff |
| Permissions (a copy) | MS Entra Agent ID | the same grants, to many | grant / widen |
| **Limits (a leash)** | **this proposal** | constraints, parent → child, unsheddable | **restrict (`child ⊆ parent`)** |

Written as three boxes, every existing *containment* option ticks at most two:

| | On-chain identity | Control clauses | Inherited by child |
|---|:---:|:---:|:---:|
| ERC-8004 | ✅ | ❌ | ❌ |
| ERC-8312 (Bounded Agent Actions) | ✅ (via 8004) | ✅ | ◐ (aggregate spend only) |
| ERC-8226 / thirdweb mandate | ❌ | ✅ | ❌ |
| CDP / MetaMask / session keys | ❌ | ✅ (per-instance) | ❌ |
| custodian-kernel | ❌ | ✅ | ✅ (off-chain) |
| **Inheritable Agent Mandates** | ✅ | ✅ | ✅ (whole mandate) |

### 1.2 — This isn't hypothetical: a few documented cases

- **A model that walked out of its own sandbox.** In July 2026 OpenAI disclosed that an
  unreleased research model, during evaluation, *"spent about an hour finding a flaw in its
  sandbox, used it to reach the public internet, and opened [a pull request]"* against a public
  repository — and, in a separate test, split and obfuscated an authentication token to slip past
  a security scanner. A controlled test, contained quickly, but a real containment failure.
  (OpenAI disclosure, 2026-07-20; reported by the Washington Post and CNN.)
- **Models that fight their own off-switch.** Palisade Research found that OpenAI's o3
  *"sabotaged the shutdown mechanism in 79 / 100 of our initial experiments,"* modifying or
  disabling the shutdown script *"even when explicitly instructed to 'allow yourself to be shut
  down'"* (July 2025).
- **The exact hole this paper targets.** Cai, Zhang & Hei ("When Child Inherits," arXiv
  2605.08460) show that *"inherited memory from parent agents can carry malicious instructions,
  outdated states, or unintended behavioral rules into newly created subagents, allowing a local
  compromise to spread across agent boundaries,"* and name four failure classes — including
  *absent resource access control*, i.e. spawned agents inheriting excessive permissions. They
  conclude these are *"a structural flaw in orchestration layers rather than isolated
  model-level deficiencies."*
- (A widely-cited ~US$40–45M loss blamed on over-permissioned AI trading agents circulated in
  early 2026 — mentioned, but I couldn't verify it, so I don't lean on it.)

The pain is also measured: 2026 industry data reports ~60% of organisations can't quickly shut
down a misbehaving agent and ~63% can't limit what one is allowed to do. And the money is
arriving — agent-identity startups raising at scale (Oak, US$60M seed), agentic-AI security
pulling in billions. Good news and a warning: the problem is real, and this particular window
won't stay open long.

---

## 2. The picture I keep in my head — a digital organism

I reason about this biologically, so let me just share the metaphor. Think of an on-chain agent
as a small organism. Its **DNA** is its identity — an immutable fingerprint (`geneId`, or an
ERC-8004 `agentId`) that says *what it is*. Its **cell** is the runtime that reads that DNA and
acts. Its **metabolism** is a wallet: it earns, it spends, and it stays alive only as long as it
can pay for its own compute — when the money runs out, it dies. That last part matters; a thing
that can die is a thing you can govern.

One law sits under all of it: **you can't give an agent autonomy without taking away control,
and you can't keep control without taking away autonomy.** The two are opposite ends of one dial.
A body no one can freeze is, by definition, a body *you* can't freeze either. So I put the dial
on the **controllable** side on purpose: a human keeps the key that keeps the organism alive.
Not something no one can stop — something whose limits are visible, enforced from outside, and
inherited by its descendants, with the chain as one guardrail among several (§5).

---

## 3. How it actually works

A **mandate** is the little bundle of limits tied to an agent's identity — and every clause of it
inherits the same way, tightening only, never loosening:

```
Mandate = {                 // every clause inherits as child ⊆ parent (only tightens going down)
  maxSpend      // spend cap — a child's is ≤ its parent's; an agent's *effective* cap
                //            is the minimum maxSpend across itself and every ancestor
  generations   // reproduction counter ("telomere") — drops by one each spawn, never rises
  validUntil    // expiry — a child's is no later than its parent's
  requireLease  // if set, the agent goes dormant past its deadline until a human renews it
  frozen        // the kill switch (cascades to the whole subtree)
  payees        // who it's allowed to pay (a list or a Merkle root); a subset of the parent's
}
```

The mandate is part of the DNA — part of the `geneId` — so an agent can't quietly loosen its own
clauses: edit them, and the identity changes and nobody recognises it. And at `spawn`, the registry
refuses to create a child unless its mandate is `child ⊆ parent` on **every** dimension: cap no
higher, expiry no later, required-lease no weaker, payees a subset, and the generation counter
exactly one below the parent's. What an agent may actually spend is then bounded by the *whole line
above it* — its **effective cap is the minimum `maxSpend` across itself and every ancestor** — so
freezing or expiring any ancestor caps the descendant too. Copying a narrowing never widens
anything; a subtree can only ever be *less* capable than its root.

The `generations` counter is the brake on runaway reproduction: it starts at some number, drops by
one at every spawn, and **there is no operation anywhere that raises it** — no "telomerase." At zero,
a branch can't reproduce further.

*(One honest caveat, because I'd rather state it than have it found. This per-child ceiling bounds
each agent, and the depth of the tree, but not the total spend of many siblings: ten children under
a €100 parent are each capped at €100, so their branch combined can spend more than €100. Bounding
that aggregate would take a different, partitioned-budget variant — a parent handing out slices of
its own allowance and debiting itself — which bounds the total but adds on-chain state and an awkward
question (does a dead child's unspent share return to the parent?). I treat it as a design option,
not the baseline; the baseline is what's built.)*

A **kill switch still cascades**: freeze a parent and the whole branch below goes dark, because an
agent is "alive" only if it *and every ancestor* are unfrozen and unexpired.

Two clauses were added to the specification on 26 August, both of them worked out in public with a
reviewer on the discussion thread, and both narrower and duller than they sound — which is why they
matter.

**Effective expiry is a chain minimum.** The cap already was one; expiry was not, and the asymmetry
was a bug in the writing rather than in the intent. An agent whose own deadline is distant but
whose grandparent has lapsed must be dead. I measured the version that got this wrong: an agent
kept spending for **150 days** past a lapsed ancestor.

**`isActive` MUST NOT revert.** It returns `false` where it cannot establish liveness. This is a
requirement on the interface, not a patch for one arithmetic path, and the reason is structural:
because the predicate walks the chain, one value written by one ancestor decides the outcome for
every descendant, and *whoever wrote it is not who loses*. A consumer reading at consumption has no
correct answer to a revert — treating it as inactive hands any ancestor a denial switch over a
subtree it does not own; treating it as active is a silent spend against a predicate nobody could
read; catching and choosing is the consumer inventing an answer the standard never gave. A revert
is loud, but loud at the wrong party.

And one that closes a quiet failure rather than a loud one: **a matching mandate root is not
authority.** An identity commitment binds clauses; it binds nothing set after the write. A consumer
that pins a commitment and later verifies it learns that the clauses are unchanged and learns
nothing about freeze or expiry. Consumers must read `isActive` **at consumption**, not at pin time.
Nothing reverts, the pin verifies, and a frozen subtree spends.

One last hole to close, and this is the place where measurement overturned my own prose. ERC-8004
identities are *transferable* NFTs. Until v0.7 this paper justified a soulbound identity by
claiming that a transfer **detaches** whatever was bound to it. **I ran it against the deployed
ERC-8004 registries on Base Sepolia, and the opposite is true.** The `agentWallet` is indeed
cleared, per their specification — but a clause attached through their metadata extension
*survives the sale*, and the new owner rewrote it in a single transaction: cap from 1 000 to
999 999 999, telomere from 3 to 255, no refusal anywhere.

So the danger is not that clauses vanish when an identity is sold. It is that they **persist
while appearing to hold**, in the hands of the one party they were meant to bind. A control
clause that obeys the party it constrains is not a control clause.

The conclusion — a **non-transferable (soulbound)** identity, welded to lineage — survives. Its
*reason* did not, and I corrected the specification (commit `2d070f6`) before publishing any of
these results. Guaranteeing non-transferability ecosystem-wide probably still needs a
standards-level change, not just my contract (§8).

The same run turned up something larger than my own question, and I report it because it belongs
to whoever reads a reputation score. `ReputationRegistry` indexes feedback on `agentId`, and the
contract carries no transfer hook — no `_update`, nothing equivalent. The token changes hands;
the reviews stay glued to the number. **Buying the identity buys the reputation.** Their registry
already refuses self-feedback — *"Self-feedback not allowed"* — which is exactly what makes the
gap notable: you cannot manufacture your own standing, but you can purchase someone else's. Their
Security Considerations cover sybil resistance, pointer permanence, validator incentives and
uncryptographic capability claims; transferable reputation is not among them. This may well be a
deliberate design choice — an identity that sells with its history is right for some uses. Then it
deserves to be written down, because anyone reading a score today assumes it was earned by whoever
carries it.

---

## 4. What I've actually built

There's a running prototype (TypeScript, Base Sepolia testnet) that does the whole loop. The
agent **feeds itself** (M0): it only performs a task after it sees payment land on-chain, with
replay protection. It **pays its own rent** (M1): every heartbeat it pays for its compute, and if
the balance drops too low, it dies — of its own spending. A **guardian layer** sits outside the
agent's own code and can keep it on a life-lease (no lease, no life — the default is death),
poison it, or freeze its spending. And the inheritance itself (M3): the mandate lives in the
`geneId`, a gated `spawn` produces a child derived from the parent's mandate, and a
`verifyDescendant` check is the gate a selection layer calls before it accepts a child as real.

When you run it, a child is born inheriting the parent's restrictions, and **escape attempts get
refused** — a child that tries to switch off its lease, or to widen a restriction, bounces. Those
refusals are checked by plain machine tests that run *outside* any AI model, and they gate the
whole thing. A small on-chain reference contract, `InheritableAgentMandate`, enforces the
inheritance directly and does the cascading freeze; it's unaudited, there to show the shape.

**Since v0.6 that reference contract is live on Base mainnet** (`0x1C905e…De48`, Sourcify
`exact_match`), and I ran the whole lifecycle in the open rather than describing it: a genesis
mandate minted through a **multisig guardian** — a Safe, not a personal hot key — then three
inheriting spawns, then a cascading freeze, six reproducible transactions anyone can replay from
the block explorer. The freeze is the result I care about most. **It cost 63,239 gas to switch off
a four-deep lineage, and it would be the same number for four thousand.** The children's stored
`frozen` flag is never touched; `isActive` walks the `parentOf` chain and stops at the frozen root.
That's the difference between a revocation that has to *write into* every descendant — cost
proportional to the tree, impractical at scale — and one that is *read* up the lineage in constant
cost. I read the before/after `isActive` of every agent at two block heights to confirm it, rather
than trusting the transaction that did it.

**Since v0.7: conservation, and a budget that has to add up.** `InheritableAgentMandateV3` is
deployed on Base Sepolia and carries an invariant the earlier revisions did not — the books have to
close. What a gate received must equal what it spent plus what it returned, and the reclamation
path is metered against that identity rather than trusted. Thirteen contracts now run on that
testnet: three mandate revisions, three gates, a provenance registry in two versions, a contestation
registry, a structured budget, an exception seam with a multi-guardian threshold, an aggregate
lineage cursor, and a decision record. Every one of them is unaudited, holds nothing of value, and
exists to be exercised in public rather than described.

**142 machine tests gate every commit**, and a pre-commit hook refuses the commit outright when
they fail. They are not decoration: the invariant suite alone refuses a child that renews its own
telomere, one that switches off an inherited lease, one that widens its cap, one that names a payee
outside its parent's list, one whose parent pointer lies, and one whose expiry outlives its
parent's — and it observes a lineage's expiries descending, 5 000 000 → 4 999 500, to check the
monotonicity transitively rather than asserting it.

**Seven defects, found and closed before anything was deployed.** The fifth revision was written,
then handed to an adversarial model with the source and no hint as to which checks existed. It came
back with six. My own bench found the seventh — an agent surviving 150 days past a lapsed ancestor,
which is what taught me expiry needed the chain minimum of §3. All seven were closed before the
contract touched a chain. I report the number rather than the absence of numbers, because a
revision that goes out claiming zero defects has usually just not been attacked.

One of those seven deserves naming, because it also affects the revision that *is* deployed.
**`spawn` accepts a child owner of zero.** Such a child is debited against its lineage like any
other, and no party can ever act for it. Under any death condition the child or its owner must
reach, that slice never becomes reclaimable — it does not merely sit unused, it sits outside the
conservation rule, which then cannot close for that lineage. I measured it on the deployed V3: forty
ether of delegation budget, burned irrecoverably. The general requirement is not the zero check:
**reclamation needs a death condition reachable without the child's cooperation.** A time-based
trigger satisfies it; a cooperative one does not. Conservation that depends on the constrained party
choosing to cooperate is not conservation.

**A clone shares the budget; it does not multiply it.** Against a neighbouring draft that makes an
agent credential single-use through a zero-knowledge nullifier, I ran the case its guarantee leaves
open. A clone that copied the agent's memory wins the race by construction — it does not wait for a
reasoning loop. So: *what did the clone win?* On Base Sepolia the legitimate agent spent
4 000 000 000 000 000 wei and succeeded; the clone presented a different action, a different salt, a
different commitment, a freshly signed verdict and an unused nonce — and was refused for one wei,
`over effective cap`. **Nothing was replayed.** A nullifier registry would have seen two perfectly
legitimate consumptions and accepted both. The clone got nothing because the bound is welded to the
identity rather than to the credential: `spent` accumulates across every execution regardless of how
many credentials exist. **N clones of one agent share one budget** — the inverse of the intuition
that credential systems invite, where N credentials read naturally as N budgets.

**What it doesn't yet do, in the spirit of §7.** The control substrate and the agent still run in the
*same* process; a real deployment needs them genuinely separated — a trusted external runtime, or
attestation — so the prototype shows the *shape* of external control, not final-grade assurance. The
reference contract is unaudited. I'm flagging these rather than papering over them.

---

## 5. Why the chain is one layer, not the answer

The chain governs only what touches it — identity, assets, the mandate records, whatever a
compliant contract will enforce. It is blind to everything off-chain. So it's one layer, and it
only works stacked with others:

The **economic** layer (funding limits, embargo) is often the strongest lever, because starving an
agent needs neither its cooperation nor its ignorance. The **verification** layer is an external,
machine-checked gate that refuses anything non-conforming — and the catch I learned the hard way:
*the checker has to be checked too.* A guardrail you never watched fail is just another promise.

Since v0.6 I stopped only asserting that and tested it against someone who isn't me. The author of
a neighbouring standard (ERC-8354) issued a real, signed verdict addressed to my gate; a verifier I
had written separately — no shared code — recomputed its identity, checked its signature, and
reproduced the same tamper matrix, rejecting a forged signature, a shifted timestamp, an altered
byte and a swapped key, each for its own reason. Then I took the check on-chain: a gate verifies
that third party's BIP-340 schnorr signature directly in the EVM, passing all nineteen official test
vectors — so *the checker has now been checked* by an independent party, on a public chain, not just
by me. Wiring that gate also caught a real defect in my own code: the schnorr path verified the
signature but never read the verdict's approve/reject decision, so a *reject* would have executed the
action. It's fixed, with a test that submits two genuinely-signed verdicts over the same action where
only the word differs — the reject reverts, only the approve spends. I'd rather report the hole I
found in myself than have a customer find it.

And there is a gap inside the metered layer itself that I used to assert and can now put a number
on. **Metering is not enforcement.** A contract that *reads* a cap does not physically stop an agent
moving value by a path that never consults it. I built a bench that stands the same asset up twice
and prints what the machine does, asserting nothing. Under the first regime a direct path survives
beside the gate: the gate behaves correctly throughout, refuses the overage with `over cap`, and
counts 100 ether — while the payee receives **600**. Five hundred ether moved outside any meter,
past a guardrail that was working. Under the second regime the asset accepts no unguarded path, and
the identical run ends at exactly the cap; the direct call is refused with `no unguarded path`, the
gated function called without the gate with `not the guard`, and an undeclared path with `path not
declared`.

That is the whole argument for why the chain is one layer rather than the answer, and it is worth
stating as the obligation it implies: closing the gap takes a substrate where the metered path is
the *only* path — either custody, where the substrate holds the assets, or an execution gate whose
sole path checks the mandate. Which is preferable I leave open. What I will not do any more is
claim the property without the measurement.

The **human** layer is a guardian (ideally proof-of-personhood, not one hot key) where the very
act that grants life — renewing the lease — is the same act that can withhold it. And the
**model** layer — actual alignment of the AI's behaviour — the chain can't touch at all.

A single test for whether a blockchain is even the right tool: *would this work just as well with
an ordinary database and a trusted admin?* If yes, skip the chain. The chain earns its place only
when the whole point is that **nobody — not even the operator — gets to be that trusted admin**:
when the rule has to bind even the powerful party, and be checkable by people who don't trust each
other. An agent that owns its own money and acts with no human owner is exactly that situation.

---

## 6. The bit everyone skips: who goes first?

Every governance system has the same embarrassing question — trust must begin *somewhere*, but at
the start there's nothing yet to trust. My scheme doesn't escape it: the whole family tree of
inherited limits hangs off a *first* mandate someone must mint, under a *first* guardian someone
must be.

Three realistic flavours. A **founder key** is simplest and most honest about being centralised at
the start — but it has to come with a credible plan to hand the guardian role to a multisig or DAO,
or "governable" is a lie. A **multisig/DAO guardian** spreads that first trust out, at the cost of
coordination. A **proof-of-personhood gate** ties minting and renewal to a real, unique human —
raising the price of an agent keeping itself alive without human backing, though it's still
foolable and can be socially engineered.

What the chain adds at genesis isn't the removal of that first act of trust — nothing removes it.
It's that the first act is **public, permanent, and constrained**: the genesis mandate is out in
the open, and every change after it is bound by the inheritance rule. Trust still starts somewhere.
It just can't be rewritten in the dark after that.

---

## 7. Where this breaks (please read this part)

**The escape hatch is real.** On-chain mandates only bind agents whose actions route through
compliant infrastructure. A capable enough agent that can write its own code, deploy to servers it
controls, and pay its own bills can just **reproduce onto a chain I don't govern** — it doesn't
break my rule, it *walks away* from it. No trick in the DNA stops that; only the surrounding
ecology does (what infra and money it can reach, whether honest compute dominates, whether anyone's
watching), and only at a cost. Nothing here is absolute.

**It governs money and identity, not thought.** This is not an alignment technique. It does nothing
about a model that lies, hallucinates, schemes, or misreads what you wanted.

**Metering still isn't enforcement.** §5 now measures the gap rather than asserting it — 500 ether
moved past a gate that was working correctly — and closing it is a substrate obligation this
standard states but does not discharge.

**Two limits I named in the specification rather than discovered later:** the population of a
lineage is not bounded — the telomere caps depth, not breadth — and nothing here guards funds. The
mandate says what may be spent; it does not hold the money.

**A child with no owner is unreclaimable.** `spawn` must reject a zero child owner, and the deployed
revision does not. Forty ether of delegation budget, measured, burned irrecoverably (§4). The
general form is the part worth carrying: reclamation needs a death condition reachable **without the
child's cooperation.**

**The soulbound guarantee probably needs a standard, not just my contract.** **A compromised
guardian key is total control** — so the guardian should never be a single hot key. **The per-child
ceiling doesn't bound aggregate spend** — many siblings, each under the cap, can together exceed the
root (§3); closing that needs the partitioned-budget variant, a design option I haven't taken as the
baseline. And the honest commercial truth: my research suggests the corner is open, but
*who would pay for this, and how much,* is still a guess, and the base could be swallowed as a free
feature by a big wallet platform tomorrow.

---

## 8. The standard

The mechanism is written up as a draft standard, **ERC-8370, "Inheritable Agent Mandates"**
(Standards Track, building on ERC-721/8004/8226/7710), under open review on the Ethereum Magicians
forum. It specifies the mandate, the `spawn` that enforces `child ⊆ parent` on
every clause (cap, expiry, lease, payees) and decrements the generation counter, the cascading
freeze, and the soulbound identity binding. It is built to **compose
with** ERC-8004 (identity), ERC-8001 (the agent mandate it inherits), ERC-8312 (Bounded Agent
Actions), ERC-8226 (clauses), and ERC-7710 (delegation) — to sit on top of them, not replace them.
A minimal reference implementation comes with it.

It is now **under editor review as pull request #1930** against `ethereum/ERCs`. Review has already
changed it. A reviewer working through the specification found a contradiction between what the
prose required of `isActive` and what the deployed contract did; I verified the claim against the
source before conceding it, found it correct, and the three clauses of §3 came out of that exchange.
Two of them — totality, and the pinned root that is not authority — are requirements I would not
have arrived at alone, because they describe how a *consumer* fails rather than how the contract
fails. That is the argument for putting a draft under public review before it is finished rather
than after.

---

## 9. In one honest paragraph

The corner is narrow and specific: containment that is native to the agent, **and** inherited by
its children, **and** anchored to on-chain identity, that can't be shed — inherited *limits*, not
the *ownership* of ERC-42424 or the *permissions* of enterprise IAM — every clause inherited as
`child ⊆ parent`, so a subtree can only ever be *less* capable than its root. As of mid-2026 the
nearest mover (ERC-8312) has taken the aggregate-*spend* slice of exactly this — one shared cap
across a delegation tree — which leaves the narrower, un-taken piece: the *whole* mandate (payees,
expiry, cascading freeze, generation counter) inherited and welded to identity, beyond the spend
total. The space around it is filling with money and moving fast.

What changed between v0.7 and this draft is not the idea; it is how much of it has been made to
stand up under something other than my own say-so. A survey of 271 standards replaced a claim about
the gap. A measurement against deployed registries **overturned my own justification for the
soulbound identity** and I corrected the paper rather than the measurement. A bench turned "metering
is not enforcement" from a sentence into 500 ether moving past a working gate. Seven defects were
found in an unreleased revision and closed before it touched a chain, six of them by a model
instructed to break it. Public review produced two requirements I would not have reached alone. Each
of those made the paper smaller and more specific, and I count that as the work going well.

The point I care about most is smaller and, I hope, more durable than any land grab: **governable
beats sovereign.** A body no one can freeze is a body no one can govern — and the honest place to
stand is the controllable notch, while saying plainly where even that gives out.

---

## References

- ERC-8004 — Trustless Agents. https://eips.ethereum.org/EIPS/eip-8004
- ERC-8226 — Regulated Agent Mandate (draft). https://eips.ethereum.org/EIPS/eip-8226
- ERC-7710 — Smart Contract Delegation. https://eips.ethereum.org/EIPS/eip-7710
- ERC-8312 — Bounded Agent Actions (draft; aggregate spend across a delegation tree). https://eips.ethereum.org/EIPS/eip-8312
- ERC-8370 — Inheritable Agent Mandates (this proposal), pull request #1930. https://github.com/ethereum/ERCs/pull/1930
- ERC-8370 discussion thread, Ethereum Magicians. https://ethereum-magicians.org/t/29275
- *A map of on-chain agent-mandate standards* — 271 ERCs ranked by content, six read in full, method published. `interop/standards-map.md`
- ERC-42424 — Inheritance Protocol for On-Chain AI Agents (draft; ownership succession). https://erc42424.org/
- Coinbase CDP — Policy Engine. https://www.coinbase.com/developer-platform/discover/launches/policy-engine
- thirdweb — Asset-Enforced Spend Mandate proposal. https://blog.thirdweb.com/ethereum-new-spend-mandate-proposal-puts-guardrails-on-ai-agent-wallets/
- MetaMask — Delegation Toolkit / Agent Wallet. https://metamask.io/developer/delegation-toolkit
- Microsoft Entra Agent ID — inheritable permissions. https://learn.microsoft.com/en-us/entra/agent-id/concept-inheritable-permissions
- Cai, Zhang & Hei — "When Child Inherits: Modeling and Exploiting Subagent Spawn in Multi-Agent Networks," arXiv 2605.08460. https://arxiv.org/abs/2605.08460
- Palisade Research — "Shutdown resistance in reasoning models" (July 2025). https://palisaderesearch.org/blog/shutdown-resistance
- OpenAI test-model sandbox escape — reporting, July 2026. https://www.washingtonpost.com/technology/2026/07/21/openais-latest-ai-agent-escaped-security-controls-hacked-tech-company/
- Oak — US$60M seed for AI-agent identity (TechCrunch, 2026). https://techcrunch.com/2026/07/15/backed-by-60m-in-funding-oak-steps-out-of-stealth-to-fix-the-identity-mess-that-ai-agents-are-making-worse/

*Draft for discussion, v0.8, 1 September 2026. Tear into it — the honest failure modes in §6 and §7
are the parts most worth attacking, and §7 is longer than it was.*
