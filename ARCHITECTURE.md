# Architecture

## Overview

ARES is a modular treasury system. No single contract does everything. Each module has one job, a dedicated interface, and communicates with other modules  through well-defined function calls .

The core idea is **layered defence**: a treasury action must pass through four independent modules before funds can move. Compromising one module is not enough. Every layer must be bypassed independently.

---

## The Five Layers

A treasury action passes through these stages in order:

```
1. PROPOSE    → Proposal records the action, status = PENDING
2. APPROVE    → Authorization verifies signatures, counts approvals
3. QUEUE      → TimelockEngine schedules execution, countdown begins
4. EXECUTE    → After delay, action runs; funds move
5. (REWARD)   → RewardDistributor runs independently for contributor payouts
```

`Main` is the coordinator that wires steps 1–4 together and enforces the two cross-cutting attack mitigations.

---

## Module Responsibilities

### `Proposal`
Tracks the full lifecycle of every treasury proposal. It stores the proposal struct, counts approvals, and advances status through the lifecycle states. It does not verify signatures — it trusts that `Authorization` already did that before calling `approveProp()`.

**Lifecycle states:**
```
PENDING → APPROVED → QUEUED → EXECUTED
                   ↘ CANCELLED
```

### `Authorization`
The cryptographic gate. Before any proposal can be queued, it must collect a threshold of EIP-712 signatures from whitelisted signers. This contract verifies each signature using `SignatureLib`, checks the signer's nonce, increments the nonce, and forwards valid approvals to `Proposal`.

It does not know about timing or execution — only whether a signature is valid and whether enough of them have been collected.

### `TimelockEngine`
The waiting room. Once a proposal is approved, it enters the timelock queue. The engine enforces a minimum delay between scheduling and execution. It also checks that the action hash matches at execution time, preventing anyone from swapping the calldata while the proposal is waiting.

It holds the actual funds (ETH and tokens) and dispatches them only when all conditions are met.

### `RewardDistributor`
Handles contributor payouts completely independently of the proposal flow. Instead of storing thousands of addresses on-chain, it stores a single 32-byte Merkle root. Contributors prove their inclusion with a Merkle proof and claim independently. The contract verifies the proof, marks the address as claimed, and transfers tokens.

### `Main`
The coordinator. It does not hold funds (except proposal deposits). Its job is to call the right modules in the right order and enforce two system-wide mitigations: the proposal deposit (griefing protection) and the flash-loan snapshot check.

### `SignatureLib` and `MerkleLib`
Pure libraries — no storage, no deployment cost beyond bytecode. All EIP-712 math lives in `SignatureLib`. All Merkle math lives in `MerkleLib`. Centralising math in libraries means one place to audit, one place to fix if a bug is found, and the ability to unit test the math completely in isolation.

---

## Module Communication

Each module only accepts calls from the address it trusts. These boundaries are enforced in every state-changing function:

| Function | Caller Restriction |
|---|---|
| `Proposal.approveProp()` | `AuthorizationLayer` only |
| `Proposal.executeProp()` | `TimelockEngine` only |
| `TimelockEngine.schedule()` | `ProposalManager` only |
| `TimelockEngine.cancel()` | Guardian or `ProposalManager` only |
| `TimelockEngine.execute()` | Anyone — but requires correct action hash and elapsed delay |
| `RewardDistributor.createRound()` | Admin only |
| `RewardDistributor.claim()` | Anyone — but requires valid Merkle proof |

The result is a strict directed flow. No module can be driven out of order. Calling `execute()` directly without going through `propose → approve → queue` is impossible — there is no `operationId` in the timelock to execute.

---

## Security Boundaries

### What each module cannot do

- `Authorization` cannot move funds — it can only record approvals
- `Proposal` cannot execute actions — it only tracks state
- `TimelockEngine` cannot approve proposals — it only runs what arrives via `schedule()`
- `RewardDistributor` is completely isolated — it has no knowledge of proposals or the timelock
- `Main` cannot move funds directly — it delegates all fund movements to `TimelockEngine`

### What the guardian can do

The guardian is a trusted multisig whose only power is to cancel proposals and slash deposits. It cannot:
- Propose anything
- Approve anything
- Move funds
- Change rules
- Block execution permanently (a cancelled proposal can be resubmitted)

### What the admin can do

The admin can add/remove whitelisted signers, set the guardian address, and create reward rounds. In production, `admin` should be the governance contract itself — not an EOA.

---

## Trust Assumptions

Every system has trust assumptions. ARES makes the following ones explicitly:

**Guardian is honest.** The guardian is assumed to be a trusted multisig that cancels only malicious proposals. If the guardian goes rogue, the worst it can do is cancel legitimate proposals (recoverable — proposer resubmits) and slash deposits (limited financial harm). It cannot steal funds.

**Admin is governed.** The admin can whitelist arbitrary signers. A malicious admin could whitelist colluding signers and push through any proposal. This is why admin should be the DAO governance contract, not an individual.

**Signer threshold is sufficient.** The system is only as secure as the number of signers required. A threshold of 3-of-5 means 3 compromised signers can approve anything. The threshold should be set conservatively.

**Merkle root is accurate.** The admin posts the Merkle root off-chain. A malicious admin could post a root that allows them to claim all reward tokens. This is mitigated by making the root update an on-chain event that the community can audit before anyone claims.

**block.timestamp is approximately honest.** Miners can shift `block.timestamp` by roughly 15 seconds. The minimum timelock delay is 1 day. A 15-second manipulation is 0.017% of the window — irrelevant.

---

## Design Decisions


Every module is defined by an interface making the codebase easy to read: the interface tells you what a module does without reading the implementation.

**Why pure libraries for math?**
`SignatureLib` and `MerkleLib` contain zero state. They are internal libraries, meaning their functions are inlined at the call site by the compiler — no external call overhead. More importantly, they can be tested completely in isolation. A bug in the EIP-712 math affects every contract that uses it, so having it in one place with 100% test coverage was the best i could think of.

**Why does Main hold deposits instead of Proposal?**
Separating deposits from proposal state keeps `Proposal` clean and focused on lifecycle tracking. `Main` is the entry point for proposers — it is the right place to enforce the economic cost of proposing.

**Why does TimelockEngine hold funds instead of Main?**
The timelock is the last gate before funds move. Having it hold the funds means no intermediate transfer is needed at execution time — the action runs directly from the contract that holds the assets. This removes one external call and one attack surface.