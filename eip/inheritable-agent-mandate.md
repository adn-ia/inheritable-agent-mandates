# ERC-8370 — Inheritable Agent Mandates

**The specification no longer lives here.** The single authoritative text is the one under
review in the Ethereum ERCs repository:

- **Pull request:** <https://github.com/ethereum/ERCs/pull/1930>
- **File:** `ERCS/erc-8370.md` on branch `add-erc-inheritable-agent-mandates`
- **Discussion:** <https://ethereum-magicians.org/t/erc-8370-inheritable-agent-mandates/29275>

## Why this file is a pointer and not a copy

Until 2026-09-15 this path held a second, divergent draft of the same standard. The two texts
had drifted into genuine contradictions — `bytes32` against `uint256` identifiers, `maxSpend`
against `maxSpendWei`, `validUntil` required to be non-zero in one and explicitly permitted to
be zero in the other. Each text also carried sections the other lacked.

Both were reconciled into the submitted text, which was corrected against the deployed
contracts rather than against either draft: the identifier type, the field names and the
zero-expiry rule all follow `contracts/InheritableAgentMandateV2.sol`, deployed at
`0x344cda78e7208684edf9a6241f5b95b1698e576a` on Base Sepolia. The material that existed only
here — effective expiry as a chain minimum, the totality requirement on `isActive`, and seven
security considerations — was folded in.

Keeping a second copy is what allowed the drift. Edits to the specification belong in the pull
request; this repository holds the implementation, the measurements and the deployment records
that the specification cites.

## What is still here

- `contracts/` — the reference implementations, v1 through V5
- `DEPLOYMENTS.md` — every deployed address, with the transactions that exercise it
- `whitepaper/` — the long-form argument behind the standard
- `interop/` — the standards map and the captured ERC-7710 / ERC-8226 discussions
