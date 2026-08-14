# A map of on-chain agent-mandate standards

*271 ERCs read, six in full. What each one actually does, and the one thing none of them do.*

Last updated 2026-08-14.

> **Correction, 14 August.** The ERC-8226 row originally described its enforcement as taking
> place in a regulated token's pre-transfer hook. That is one of three venues its
> specification defines, not the definition — corrected below, after @thamerdridi pointed it
> out on the discussion thread. Thread activity figures are still as collected on 13 August.

---

If you are trying to work out how to bound what an autonomous agent may do on-chain, you
will find a dozen ERCs that sound like they answer the question. Most of them answer a
different one. Working out which is which took a week, so here is the map, with the method
attached so you can check it rather than trust it.

This is not a critique of anyone's work. Several of the standards below deliberately
exclude what I was looking for, and say so. A map is more useful than an opinion.

## Method

Titles are misleading in this space — "agent", "delegation" and "permission" appear in
proposals that have nothing to do with each other. So the corpus was ranked by content.

- Every ERC in `ethereum/ERCs` was listed: **611 files**.
- Those numbered **≥ 7000** were kept: **271**.
- Their **full text** was downloaded (~5.1 MB) and scored against 11 concept patterns:
  delegation, attenuation, sub-agent, inheritance, cap, revocation, expiry, identity,
  AI-agent, caveat, session.
- The top of that ranking was then **read end to end** — specification and discussion
  thread, not abstracts. **Five threads retrieved, 73 posts.**

The ranking is a filter, not a verdict. ERC-7303 scored third and is a **false positive** —
it is token-based role access control and has nothing to do with agents. Every candidate
below was confirmed by reading, and in one case by compiling.

**Scope limit, stated up front.** The corpus is the **merged** `ethereum/ERCs` tree. Open
pull requests and forum-only drafts are outside it — ERC-8165 (PR #1549, open since
February) is one such case, and it sits on the intent/solver layer rather than this one.

## The map

| ERC | What it actually does | Status | Thread |
|---|---|---|---|
| **8226** Regulated Agent Mandate | A principal grants a scoped, capped, time-bounded mandate to one agent. Per-transaction and cumulative caps, freeze, compliance provider. **Enforcement is venue-agnostic**: a regulated token's pre-transfer hook, an EIP-7702 delegated account, or a dedicated executor — all read the same mandate. | Draft | **live** — 12 posts, last 2026-08-12 |
| **8196** AI Agent Authenticated Wallet | Executes only with cryptographic proof that the action complies with an owner-defined policy. Hash-chained audit trail, entropy commit-reveal against host manipulation. Layer 2 of a stack with ERC-8126. | **Final** | 14 posts, last 2026-07-20 |
| **8199** Sandboxed Smart Wallet | Containment by isolation: the agent's wallet is fully detached from the owner's, the relationship one-directional. | Draft | dormant — 2 posts, 93 views |
| **8273** Attestation-Gated Agentic Actions | Per-operation attestation, authorized in EIP-1153 transient storage and cleared at the end of the transaction. | Draft | — |
| **7715** Request Permissions from Wallets | The request side: a JSON-RPC method for a dapp to ask a wallet for permissions. Requires 4337 and 7710. | Draft | 10 posts, last 2026-04-29 |
| **7710** Smart Contract Delegation | A single function, `redeemDelegations`, for redeeming a delegation against a Delegation Manager. | Draft | dormant — 35 posts, 6.2k views, last 2025-04-30 |

Three things that are easy to get wrong from the abstracts:

**8273 is not a session system.** Its own text: *"There is no expiration mechanism, and
there are no long-lived or session-based attestations."* Authorization exists for one
transaction. If you need state that outlives a call, this is the wrong axis, not a weaker
version of the right one.

**7710 does not specify caveats.** The ERC is one function. Caveat enforcement, delegation
chains and revocation appear only as features of the *MetaMask Delegation Framework*, its
reference implementation. The standard also declares acquisition out of scope: *"The
process by which a delegate obtains a delegation is intentionally left out of scope."* Its
Security Considerations section currently ends with `Needs discussion. <!-- TODO -->`.

**8196 is Final.** Whatever you think of it, it is not going to change.

## The empty square

None of the 271 standardizes **attenuated re-delegation**: a child agent that comes into
existence already bounded by its parent, on every clause, with the bound non-strippable.

The closest candidate is ERC-8226, and it is worth being precise about why it is not that.
Its mandate is keyed by `(agent, principal)`; only the principal can grant. An agent holding
a valid mandate cannot create anything. Searching its reference implementation for the
vocabulary of lineage —

```
grep -rniE "child|parent|sub-?agent|inherit|lineage|spawn|attenuat" contracts/ test/
```

— returns only `@inheritdoc`, a Solidity documentation tag. The concept is absent from the
code, not merely from the prose.

**That is not a defect.** One of its authors stated the position directly on my own thread,
and was right to: a spawned child inherits nothing under RAMS, *including the authority to
act*, so reproduction cannot be used to escape a mandate. Inheritance is out of scope by
design. The honest way to phrase the gap is "ERC-8226 does not define mandate inheritance",
not "ERC-8226 can be bypassed."

The same care applies to the others. 8199 refuses granular sharing on principle, arguing
that session-key-style approaches *"inherently bring in permission evasion issues"*. 8273 is
transaction-scoped by construction. 7715 is a request protocol, not an enforcement layer.
None of these is an oversight; they are four different answers to four different questions.

The square is empty because nobody has claimed it, not because everybody missed it.

## Reproduce it

```bash
# the corpus
gh api repos/ethereum/ERCs/contents/ERCS --paginate | jq -r '.[].name'

# any spec, full text
curl -sL https://raw.githubusercontent.com/ethereum/ERCs/master/ERCS/erc-8226.md

# any discussion thread, every post, raw
curl -s "https://ethereum-magicians.org/t/28208.json?include_raw=true&print=true"
```

ERC-8226's reference implementation compiles and its own test suite passes — 72 tests, 0
failures — with OpenZeppelin resolved from `master` (the `v5.1.0` tag does not exist) and
`forge-std` supplied locally. Worth doing: reading a specification and running it are not
the same activity, and the second one is cheap.

## Disclosure

I work on [ERC-8370](https://ethereum-magicians.org/t/erc-8370-inheritable-agent-mandates/29275),
which is an attempt at the empty square. That is why I read all of this, and you should
weigh the map accordingly — though every claim above is checkable with the three commands
in the previous section, which is rather the point.

Corrections welcome, especially from the authors of anything listed here. If I have
mischaracterized your standard's scope, say so and I will fix it.
