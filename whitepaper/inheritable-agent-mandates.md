# Inheritable Agent Mandates
### A non-strippable, identity-anchored leash for autonomous on-chain AI agents

**Author:** Helmy Mekaoui · **Version:** 0.6 (draft) · **Date:** 2026-07-28
**Companion artifacts:** a reference contract (`InheritableAgentMandate.sol`), a working prototype (M0/M1/M3), and a draft EIP, "Inheritable Agent Mandates."

> A note before we start. This is a working draft, written by one person, and I've tried to
> keep it honest rather than impressive. It says what the idea is, what I've actually built,
> and — on purpose — where it falls apart. Wherever a claim leans on guesswork or on reporting
> I couldn't verify, I say so out loud. If you're here to poke holes, head straight for §6 and
> §7; that's where the soft spots are, and I'd rather you find them than a customer.

---

## Abstract

AI agents are starting to hold money on-chain and to **spawn copies of themselves** to get
work done in parallel. The guardrails we have today all share one blind spot: they're attached
to a *single* account. Spend limits, session keys, policy engines — each one leashes one agent.
None of them follows that agent's *children*. So the moment an agent spawns a copy, its limits
are gone: it can escape its own leash simply by being born again, unbound.

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
caps, expiry, freeze — and ERC-8004 gives an agent a portable on-chain identity.

But two things are always true. Each of these is attached to a *single* instance, and none of
them cares *who the agent is* — the clauses float free of identity. Put those together and you
get the hole: **nobody carries a control into a spawned child.** The parent's limits simply
don't travel.

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
| ERC-8226 / thirdweb mandate | ❌ | ✅ | ❌ |
| CDP / MetaMask / session keys | ❌ | ✅ (per-instance) | ❌ |
| custodian-kernel | ❌ | ✅ | ✅ (off-chain) |
| **Inheritable Agent Mandates** | ✅ | ✅ | ✅ |

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

One last hole to close: ERC-8004 identities are *transferable* NFTs, and transferring one wipes
the wallet — so nothing tied to identity survives a transfer by default. My reference design makes
the identity **non-transferable (soulbound)**: identity is welded to lineage, so you can't dodge
the leash by handing the token to a fresh, unbound owner. Guaranteeing that ecosystem-wide
probably needs a standards-level change, not just my contract (§8).

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
whole thing. A small on-chain reference contract, `InheritableAgentMandate.sol`, enforces the
inheritance directly and does the cascading freeze; it's unaudited, there to show the shape.

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

**The soulbound guarantee probably needs a standard, not just my contract.** **A compromised
guardian key is total control** — so the guardian should never be a single hot key. **The per-child
ceiling doesn't bound aggregate spend** — many siblings, each under the cap, can together exceed the
root (§3); closing that needs the partitioned-budget variant, a design option I haven't taken as the
baseline. And the honest commercial truth: my research suggests the corner is open, but
*who would pay for this, and how much,* is still a guess, and the base could be swallowed as a free
feature by a big wallet platform tomorrow.

---

## 8. The standard

The mechanism is written up as a draft EIP, "Inheritable Agent Mandates" (Standards Track, building
on ERC-721/8004/8226/7710). It specifies the mandate, the `spawn` that enforces `child ⊆ parent` on
every clause (cap, expiry, lease, payees) and decrements the generation counter, the cascading
freeze, and the soulbound identity binding. It is built to **compose
with** ERC-8004 (identity), ERC-8226 (clauses), and ERC-7710 (delegation) — to sit on top of them,
not replace them. A minimal reference implementation comes with it.

---

## 9. In one honest paragraph

The corner is narrow and specific: containment that is native to the agent, **and** inherited by
its children, **and** anchored to on-chain identity, that can't be shed — inherited *limits*, not
the *ownership* of ERC-42424 or the *permissions* of enterprise IAM — every clause inherited as
`child ⊆ parent`, so a subtree can only ever be *less* capable than its root. As of mid-2026 it looks largely
unbuilt, the nearest movers each cover only two of the three legs, and the space around it is
filling with money and moving fast. The point I care about most is smaller and, I hope, more
durable than any land grab: **governable beats sovereign.** A body no one can freeze is a body no
one can govern — and the honest place to stand is the controllable notch, while saying plainly
where even that gives out.

---

## References

- ERC-8004 — Trustless Agents. https://eips.ethereum.org/EIPS/eip-8004
- ERC-8226 — Regulated Agent Mandate (draft). https://eips.ethereum.org/EIPS/eip-8226
- ERC-7710 — Smart Contract Delegation. https://eips.ethereum.org/EIPS/eip-7710
- ERC-42424 — Inheritance Protocol for On-Chain AI Agents (draft; ownership succession). https://erc42424.org/
- Coinbase CDP — Policy Engine. https://www.coinbase.com/developer-platform/discover/launches/policy-engine
- thirdweb — Asset-Enforced Spend Mandate proposal. https://blog.thirdweb.com/ethereum-new-spend-mandate-proposal-puts-guardrails-on-ai-agent-wallets/
- MetaMask — Delegation Toolkit / Agent Wallet. https://metamask.io/developer/delegation-toolkit
- Microsoft Entra Agent ID — inheritable permissions. https://learn.microsoft.com/en-us/entra/agent-id/concept-inheritable-permissions
- Cai, Zhang & Hei — "When Child Inherits: Modeling and Exploiting Subagent Spawn in Multi-Agent Networks," arXiv 2605.08460. https://arxiv.org/abs/2605.08460
- Palisade Research — "Shutdown resistance in reasoning models" (July 2025). https://palisaderesearch.org/blog/shutdown-resistance
- OpenAI test-model sandbox escape — reporting, July 2026. https://www.washingtonpost.com/technology/2026/07/21/openais-latest-ai-agent-escaped-security-controls-hacked-tech-company/
- Oak — US$60M seed for AI-agent identity (TechCrunch, 2026). https://techcrunch.com/2026/07/15/backed-by-60m-in-funding-oak-steps-out-of-stealth-to-fix-the-identity-mess-that-ai-agents-are-making-worse/

*Draft for discussion. Tear into it — the honest failure modes in §6 and §7 are the parts most
worth attacking.*
