# ARES Treasury Execution System

A secure treasury execution system for protocol governance. ARES allows a DAO to propose, approve, delay, and execute treasury transactions safely — with cryptographic authorization, time-delayed execution, and Merkle-based contributor rewards.

---

## The Problem It Solves

A DAO treasury needs to pay contributors, upgrade contracts, and move funds. 

- A single compromised signer can drain everything
- Governance attacks can happen faster than token holders can react
- Storing thousands of contributor addresses on-chain costs a lot in gas

ARES solves all three with four independent modules that a treasury action must pass through before any funds move.

---

## How It Works

```
Proposer submits action
        ↓
Whitelisted signers cryptographically approve (EIP-712)
        ↓
Approved proposal enters the timelock queue
        ↓
After the delay, anyone can trigger execution
        ↓
Funds move
```

Contributors claim token rewards independently using a Merkle proof — no on-chain list, no gas-expensive loops.

---

## Project Structure

```
src/
├── interfaces/
│   ├── IProposal.sol       # Proposal lifecycle interface
│   ├── ITimeLock.sol        # Time-delay queue interface
│   ├── IAuthorization.sol    # Signature verification interface
│   └── IRewardDistributor.sol     # Merkle claim interface
│
├── libraries/
│   ├── SignatureLib.sol            # All EIP-712 math — one place to audit
│   └── MerkleLib.sol              # All Merkle proof math — one place to audit
│
├── modules/
│   ├── Proposal.sol        # Tracks proposal lifecycle
│   ├── Authorization.sol     # Verifies signatures, counts approvals
│   ├── TimelockEngine.sol         # Enforces delay before execution
│   └── RewardDistributor.sol      # Merkle-based contributor payouts
│
└── core/
    └── Main.sol           # Wires all modules, enforces attack mitigations
```

---

## Modules at a Glance

| Module | What It Does |
|---|---|
| `Proposal` | Tracks every proposal from PENDING → APPROVED → QUEUED → EXECUTED |
| `Authorization` | Verifies EIP-712 signatures and counts approvals from a whitelisted signer set |
| `TimelockEngine` | Holds queued operations and enforces a minimum delay before execution |
| `RewardDistributor` | Distributes tokens to contributors via Merkle proofs — O(log n) gas per claim |
| `Main` | Coordinates all modules. Enforces deposit requirement and flash-loan protection |
| `SignatureLib` | Pure library — EIP-712 domain separator, struct hashing, ecrecover, malleability checks |
| `MerkleLib` | Pure library — leaf hashing, proof verification, sorted pair combination |

---

## Key Security Properties

- **No single point of failure** — funds require valid signatures + timelock delay + correct action hash
- **Reentrancy safe** — all state updated before external calls (CEI pattern throughout)
- **Replay proof** — per-signer nonces, chain ID, and contract address in every signature
- **Flash-loan resistant** — voting power snapshotted at block.number - 1
- **Griefing resistant** — proposal deposit slashed on guardian cancellation
- **Double-claim proof** — permanent per-round claimed bitmap in RewardDistributor

---

## Getting Started

### Install dependencies

```bash
forge install OpenZeppelin/openzeppelin-contracts
```

### Add remapping

In `foundry.toml`:
```toml
remappings = ["@openzeppelin/=lib/openzeppelin-contracts/"]
```

### Build

```bash
forge build
```

### Test

```bash
forge test -vvv
```

---

## Documentation

- [ARCHITECTURE.md](./ARCHITECTURE.md) — system design, module separation, trust assumptions
- [SECURITY.md](./SECURITY.md) — attack surfaces, mitigations, residual risks
- [SPEC.md](./SPEC.md) — formal protocol lifecycle specification

---

## Deployment Order

Deploy in this order — each contract needs the address of the one before it:

```
1. Proposal   (needs: threshold, placeholder addresses)
2. TimelockEngine    (needs: ProposalManager address)
3. Authorization (needs: ProposalManager address, initial signers)
4. RewardDistributor (standalone)
5. Main      (needs: all four module addresses, guardian)
```

After deploying TreasuryCore, update ProposalManager and TimelockEngine with the real module addresses.