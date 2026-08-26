---
eip: 8370
title: Inheritable Agent Mandates
description: Spending and lifecycle limits welded to an agent's on-chain identity that every spawned child inherits and can only tighten.
author: Helmi Mekaoui (@adn-ia)
discussions-to: https://ethereum-magicians.org/t/inheritable-agent-mandates-a-non-strippable-inherited-leash-for-on-chain-agents/29275
status: Draft
type: Standards Track
category: ERC
created: 2026-08-04
requires: 165, 721, 8004
---

## Abstract

This ERC defines **inheritable agent mandates**: a set of control clauses — a spend
cap, an expiry, a generation counter, a mandatory-liveness flag, a payee allowlist and a
freeze (kill) switch — that are bound to an autonomous agent's on-chain identity and are
**automatically and non-strippably inherited** by any child agent the parent spawns.

A conforming registry enforces a single invariant at spawn time: **a child's mandate can
never exceed its parent's** (`child ⊆ parent`). It also defines a *cascading freeze* (killing
a parent deactivates its whole subtree) and an optional *soulbound* identity binding so that
mandates cannot be stripped by transferring the identity.

It is designed to compose with [ERC-8004](./eip-8004.md) for identity, ERC-8001 for the agent
mandate/agreement it inherits, ERC-8312 (Bounded Agent Actions) for bounded authority, [ERC-8226](./eip-8226.md)
for the mandate clauses/enforcement, and [ERC-7710](./eip-7710.md) for delegation.

## Motivation

Autonomous AI agents increasingly hold on-chain funds and **spawn sub-agents** to
parallelise work. The controls that exist today are all applied *per instance* and are
*identity-agnostic*:

- Account-abstraction session keys and policy engines (e.g. spend caps, payee allowlists)
  are attached to a single delegated key or a single account.
- ERC-8226 mandates carry spend caps, expiry, allowlists and a freeze, but are explicitly
  identity-agnostic and silent on child agents.
- ERC-8004 provides a portable agent identity but explicitly excludes payments, governance
  and any control layer.
- ERC-7710/7715 delegate bounded permissions, but caveats are fixed at delegation-creation
  time with no automatic propagation to spawned children.

The consequence is a structural gap. Most of these controls do not travel to a spawned child at all;
the one that does — ERC-8312's delegation-budget profile — carries an aggregate *spend* cap across
the tree, but not the rest of the mandate. So a compromised, misaligned or simply buggy agent can
find most of its constraints absent from its offspring — a spawned child inherits, at best, a
spend ceiling, while its payees, expiry, freeze and generation bound are not carried over. This is a
gap between standards, not a defect in any of them: none of these specifications defines mandate
inheritance, and none claims to. Multi-agent
research has documented that spawned sub-agents inherit capabilities and memory without isolation, so
a local compromise propagates across agent boundaries.

No existing standard binds the **whole** control mandate — spend cap *and* payees, expiry, cascading
freeze, and a generation counter — to an agent's identity **and** guarantees it is inherited by, and
non-strippable across, spawning. (ERC-8312's delegation-budget profile covers the aggregate-spend
axis; this covers the rest, welded to identity.) This ERC specifies that intersection.

## Specification

The key words "MUST", "MUST NOT", "SHOULD" and "MAY" are to be interpreted as described in
RFC 2119 and RFC 8174.

### Definitions

- **Agent**: an on-chain identity, identified by an `agentId` (an ERC-8004 `agentId` /
  ERC-721 `tokenId` MAY be used directly).
- **Mandate**: the control clauses bound to an `agentId`.
- **Parent / child**: an agent created by another agent via `spawn`.
- **Guardian**: the authority (an address, multisig, timelock, or proof-of-personhood gate)
  permitted to `mint`, `freeze` and `renew`.

### Mandate structure

```solidity
struct Mandate {
    uint256 maxSpendWei;   // cumulative spend cap enforced by the execution layer
    uint64  validUntil;    // liveness expiry (unix seconds); 0 = no expiry
    uint16  generations;   // remaining reproduction budget ("telomere"); decreases only
    bool    requireLease;  // if true, the agent is inactive past validUntil until renewed
    bool    frozen;        // kill switch
}
```

Payees MAY be represented either as an enumerated allowlist or as a `bytes32 payeesRoot`
(a Merkle root of allowed payee addresses) to bound gas. A conforming implementation MUST
support at least one and document which.

### Interface

```solidity
interface IInheritableAgentMandate {
    event Minted(uint256 indexed agentId, address indexed owner);
    event Spawned(uint256 indexed childId, uint256 indexed parentId);
    event Frozen(uint256 indexed agentId);
    event Renewed(uint256 indexed agentId, uint64 validUntil);

    /// Create a root agent. Guardian-gated.
    function mint(address owner, Mandate calldata m, bytes32 payeesRoot) external returns (uint256 agentId);

    /// Spawn a child. MUST enforce `child ⊆ parent` (see below).
    function spawn(uint256 parentId, address childOwner, Mandate calldata childMandate, bytes32 childPayeesRoot)
        external returns (uint256 childId);

    /// Kill switch. Guardian-gated. Cascades to descendants via `isActive`.
    function freeze(uint256 agentId) external;

    /// Renew the liveness lease (dead-man's switch). Guardian-gated.
    function renew(uint256 agentId, uint64 validUntil) external;

    function mandateOf(uint256 agentId) external view returns (Mandate memory);
    function parentOf(uint256 agentId) external view returns (uint256);

    /// True iff the agent and ALL ancestors are unfrozen and (if requireLease) unexpired.
    function isActive(uint256 agentId) external view returns (bool);

    /// The lineage-effective spend cap = min(maxSpendWei) over the agent and all ancestors.
    function effectiveMaxSpendWei(uint256 agentId) external view returns (uint256);
}
```

### The inheritance invariant (`child ⊆ parent`)

`spawn` MUST revert unless **all** of the following hold, where `p = mandateOf(parentId)`
and `c = childMandate`:

1. `p.frozen == false` and (if `p.requireLease`) `p.validUntil >= block.timestamp`.
2. `p.generations >= 1` and `c.generations == p.generations - 1`.
3. `c.maxSpendWei <= p.maxSpendWei`.
4. `c.validUntil == 0 ? p.validUntil == 0 : c.validUntil <= p.validUntil` (child expiry no
   later than parent).
5. `p.requireLease == true` implies `c.requireLease == true` (a child MUST NOT relax an
   inherited liveness requirement).
6. every payee authorised for the child MUST be authorised for the parent (enumerated
   subset, or a `childPayeesRoot` proven to be a subset of the parent set).

A caller MAY submit a `childMandate` that is stricter than the parent's; it MUST NOT submit
one that is broader on any dimension.

### Cascading freeze and effective bounds

`isActive(agentId)` MUST return `false` if any agent in the `parentOf` chain is `frozen`, and
MUST return `false` if the agent's own lease has lapsed. Thus freezing a parent deactivates its
entire subtree, and letting a parent's lease lapse deactivates all descendants.

The two clauses are not enforced the same way, and the asymmetry is deliberate rather than an
optimisation. `frozen` is set *after* the mandate is written and no local value summarises it,
so it requires an unbounded walk. Expiry is fixed *at* the write and ordered by `spawn`, which
forbids a child outliving its parent — an expired ancestor therefore implies an expired
descendant, and reading upward adds nothing. A conforming implementation MAY read `validUntil`
locally for this reason.

That permission is conditional, and implementations MUST NOT rely on it outside its
condition. It holds only while every deadline is fixed at `spawn` and never moves afterwards.
Any mechanism that can extend a `validUntil` after the fact — a renewal, a guardian-set
deadline, a re-issued mandate — destroys the ordering that justifies the local read: a
descendant whose lease is current can then outlive an ancestor that stopped renewing, and
nothing detects it. An implementation offering such a mechanism MUST either include
`validUntil` in the unbounded walk, or require the ancestor to be active at the moment of
renewal, which bounds the over-live window to one descendant period instead of removing it.

### Effective expiry is a chain minimum

Where any mechanism can move a deadline after `spawn`, `isActive` MUST read expiry across the
chain, and the quantity that governs liveness is:

```
effectiveExpiry(id) = min(current expiry) over id and every ancestor of id
```

An agent's own deadline therefore does not decide whether it is alive; its ancestors do, at
every read. Keeping a depth-`d` agent usable is a `d`-way operation, and the party paying for
a node's period is not the party who can keep it usable.

**No direction constraint is placed on period length.** It appears to need one, because under
a local read a longer child period bought survival past a lapsed ancestor. The chain minimum
removes that directly. What remains, when a child's period is longer than its parent's, is
that the child spends part of a period it paid for inactive. That is a **liveness** property,
not a soundness one, and it cannot be normative: a conforming parent may always simply stop
renewing. Implementations SHOULD align periods along a lineage, and this specification names
the failure mode rather than forbidding it. Stating the chain minimum instead of a direction
constraint also stays correct if a later revision allows a period to be shortened.

### `isActive` MUST be total

`isActive(agentId)` MUST NOT revert. It MUST return `false` where it cannot establish
liveness.

This is a requirement on the interface, not on any one arithmetic path. Once every read walks
the chain, a single value held by one ancestor decides the outcome for every descendant, and
whoever wrote that value is not who loses. A consumer reading at consumption has no correct
response to a revert: treating it as inactive hands any ancestor a denial switch over a
subtree it does not own; treating it as active is a silent spend against a predicate nobody
could read; catching and choosing is the consumer inventing an answer the registry never gave.
A revert is loud, but loud at the wrong party — the descendant's consumer hears it and cannot
act, the ancestor that caused it never hears it at all.

Range checks on individual setters close individual paths. Totality closes the class,
including whatever field joins the walk in a later revision.

### A matching mandate root is not authority

`mandateRoot` commits to clauses. It does not commit to anything set after the write. A
consumer that pins a root and later verifies the pin learns that the clauses are unchanged; it
learns nothing about freeze, expiry or any other posterior state.

Consumers MUST therefore read `isActive` **at consumption**, not at pin time. The failure this
prevents is quiet rather than loud: nothing reverts, the pin verifies, and a frozen subtree
spends.

*Credit: the chain minimum, the totality requirement and the consumption rule were worked out
with `zexoverz` in the discussion thread.*

`effectiveMaxSpendWei(agentId)` MUST return the minimum `maxSpendWei` across the agent and all
ancestors. Execution-layer enforcers (e.g. an ERC-8226 enforcer, a paymaster, or a smart
account) SHOULD gate an agent's transactions on `isActive` and `effectiveMaxSpendWei` rather
than on the agent's own mandate alone.

### Non-strippability and soulbound identity

The mandate is part of the agent's registration, not data the agent controls; an agent
therefore cannot rewrite its own mandate. To prevent stripping via *transfer*, a conforming
identity used with this ERC:

- SHOULD be **non-transferable (soulbound)**; or
- if transferable (e.g. an ERC-8004 `agentId`), transfer MUST NOT reset or clear the mandate,
  MUST be guardian-gated, and MUST preserve `parentOf`.

## Rationale

- **`child ⊆ parent`** bounds the blast radius of reproduction: a subtree of agents can only
  ever be *less* capable than its root, so spawning cannot be used to escalate.
- **`generations` (telomere)** bounds runaway self-replication without any external trigger;
  it can only decrease, and there is deliberately no operation to increase it (no
  "telomerase") except minting a fresh root agent, which is guardian-gated.
- **Cascading freeze** gives a single, identity-scoped kill that stops a whole lineage at
  once, rather than requiring each descendant to be found and stopped individually.
- **Soulbound identity** closes the transfer hole. Measured against the deployed ERC-8004
  Identity Registry rather than assumed: transferring an agent clears only the reserved
  `agentWallet` key; arbitrary metadata — including a mandate written there — survives the
  transfer intact. The risk is therefore not that the clauses are shed, but that they persist
  while becoming rewritable by whoever now holds the token: the new owner reset a spend cap
  from 1000 to 999,999,999 and a generation counter from 3 to 255, in one call, with no
  refusal. A leash whose setting is controlled by the holder is not a leash. Non-transferability
  plus the absence of any post-hoc mutation is what makes the clauses binding.
- **On-chain enforcement** (vs. off-chain policy) makes the constraints verifiable and
  portable across wallets and agent frameworks, which is the property no single wallet-vendor
  policy engine provides.

## Backwards Compatibility

This ERC adds a registry and does not modify existing standards. `agentId` MAY be an ERC-8004
`agentId`. The mandate clauses are intentionally aligned with ERC-8226 so an ERC-8226 enforcer
can consume `effectiveMaxSpendWei`/`isActive`. Delegations under ERC-7710 MAY be scoped to an
`agentId` and checked against `isActive`.

## Reference Implementation

A minimal reference (`InheritableAgentMandate.sol`) implementing `mint`, `spawn` (with the
full `child ⊆ parent` check), `freeze`, cascading `isActive`, and a non-transferable identity
accompanies this proposal. It is unaudited and intended for illustration.

## Security Considerations

- **Off-chain / rogue runtimes.** On-chain mandates only bind agents whose actions route
  through compliant accounts (smart account, paymaster, or ERC-8226 enforcer that consults
  this registry). An agent that redeploys itself outside the registry, or whose runtime
  ignores it, is not contained by this ERC; economic containment (funding) remains the
  backstop for such cases.
- **Guardian compromise.** The guardian can mint, freeze and renew. It SHOULD be a multisig,
  timelock, or proof-of-personhood gate rather than a single hot key.
- **A spawned child with no owner is unreclaimable, and unclosable.** `spawn` MUST reject a
  zero child owner. The reference implementation deployed on Base Sepolia does not, and the
  consequence is worse than a burned allocation. A child spawned to the zero address is
  debited against its lineage like any other, but no party can act for it. Under any death
  condition the child or its owner must reach, that slice never becomes reclaimable — it does
  not merely sit unused, it sits **outside the conservation rule**, which has no way to close
  for that lineage. The general form is the requirement, not the zero check: **reclamation
  needs a death condition reachable without the child's cooperation.** A time-based trigger
  satisfies it; a cooperative one does not. Conservation that depends on the constrained party
  cooperating is not conservation.
- **Aggregate spend.** `effectiveMaxSpendWei` bounds each agent (the minimum cap along its lineage),
  not the *sum* across many siblings: N children each under the cap can together exceed the root's.
  Deployments that need an aggregate bound SHOULD partition the budget at spawn (debiting the parent)
  rather than only enforcing a per-child ceiling. **Debiting the immediate parent alone is not
  sufficient**: it bounds breadth, not depth. A child that has been debited from its parent still
  begins with its own allocation counter at zero, so a chain of D generations each re-issuing its
  full cap reaches D times the root's ceiling — depth substitutes for width. An aggregate bound
  therefore requires debiting *every ancestor* along the lineage at spawn, or an equivalent
  lineage-wide accounting; a per-parent counter alone does not provide one.
- **Liveness griefing.** A guardian that stops renewing deactivates a subtree by design
  (dead-man's switch). Implementers SHOULD choose `validUntil` windows that tolerate renewal
  latency.
- **Payee revocation.** With a `payeesRoot`, revoking a payee requires updating the root;
  implementations SHOULD emit an event on root changes.
- **Unbounded population.** Nothing bounds the *number* of descendants: a parent with no
  unallocated budget left can still spawn arbitrarily many zero-budget children, and each is
  inert (`effectiveMaxSpendWei` takes the lineage minimum, so a zero cap dominates). Where the
  deployment partitions the budget at spawn (see *Aggregate spend* above), this is harmless — no
  view is O(width), so the spawner merely pays gas for empty shells. Without that partitioning,
  unbounded width is the vector *Aggregate spend* describes, and the population bound is doing
  work the budget bound is not. It stops being harmless in either case the moment anything grants
  value *per agent*: deployments layering airdrops, reputation weight, quotas, or rate limits on top
  of agent identity reintroduce a Sybil vector this ERC does not cover, and SHOULD bound
  population explicitly.
- **No custody.** This ERC authorizes; it does not hold funds. The registry has no payable
  entry point and never takes possession of value, so expiry cannot strand a balance and
  deactivation leaves no orphaned funds. Implementers who add a custody layer inherit the
  question this ERC avoids: an expired or frozen agent MUST be able to *unwind* — settle
  outstanding obligations and return residual value up its lineage — and not merely lose the
  ability to act, or expiry becomes a way to lock value permanently.
- **Unknown agent ids.** A registry backed by mappings returns a zero-valued `Mandate` for an id
  that was never minted: `frozen` is false, `validUntil` is zero, and the ancestor walk terminates
  immediately. A naive `isActive` therefore reports an agent that does not exist as **active**, and
  a capability root can be computed for it. Implementations MUST reject unknown ids in `isActive`
  and in any root-deriving view, and integrators MUST NOT treat `isActive` as an existence check.
- **A capability root is not a liveness attestation.** A root derived from an agent's own clauses
  does not change when an ancestor is frozen, when the agent's unallocated budget reaches zero, or
  when a payee is removed — none of that is part of the agent's own `Mandate`. Consumers that pin a
  root (for example an ERC-8312 envelope) MUST re-read `isActive` and the effective cap at use time
  rather than treating the root as a standing authorization.
- **Spawning is not gated on liveness.** `spawn` checks that the parent is unfrozen, but an
  implementation that does not also check the parent's expiry — or the freeze state of its
  ancestors — lets a dead lineage keep growing. The descendants are inert (`isActive` walks up), so
  nothing becomes spendable, but identities and any partitioned budget are consumed irreversibly
  where the allocation counter never decreases. Implementations SHOULD require `isActive(parentId)`
  in `spawn`, and MUST NOT allow a child to be created with a `validUntil` already in the past.
- **Reentrancy / gas.** `spawn` writes state after all checks; ancestor-walking views
  (`isActive`, `effectiveMaxSpendWei`) are O(depth) and callers SHOULD bound lineage depth.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
