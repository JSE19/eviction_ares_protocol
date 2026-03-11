# Security Analysis

## Attack Surface Map

| Attack | Module | Defence |
|---|---|---|
| Reentrancy | TimelockEngine, RewardDistributor | CEI pattern |
| Signature replay | Authorization | Per-signer nonces |
| Cross-chain replay | Authorization | Chain ID in domain separator |
| Signature malleability | SignatureLib | `s` lower-half check + `v` validation |
| Double claim | RewardDistributor | Permanent claimed bitmap |
| Timelock bypass | TimelockEngine | `executionTime` enforced on-chain |
| Transaction replacement | TimelockEngine | `actionHash` verified at execution |
| Flash-loan attack | Main | Snapshot block check |
| Governance griefing | Main | Proposal deposit slashing |
| Treasury drain | TimelockEngine | Per-window ETH spending cap |
| Unauthorized execution | All modules | Access control + lifecycle enforcement |

---

## 1. Reentrancy

State is updated **before** every external call (CEI pattern). A reentrant call hits `OperationAlreadyDone` or `AlreadyClaimed` immediately.

```solidity
op.status = OperationStatus.DONE; // state first
_executeAction(action);            // external call second
```

---

## 2. Signature Replay

Every signature includes the signer's current nonce. After it is accepted, the nonce increments — the old signature is permanently invalid. Nonces are per-signer so approving multiple proposals never causes a bottleneck.

---

## 3. Cross-Chain and Cross-Contract Replay

The EIP-712 domain separator includes `block.chainid` and `address(this)`. A signature from a testnet or a different contract produces a different digest — `ecrecover` returns the wrong address and the whitelist check fails.

---

## 4. Signature Malleability

`SignatureLib.recover()` rejects any signature where `v ∉ {27, 28}` or `s > HALF_ORDER`. The malleable mirror signature always falls in the upper half of the curve — it is structurally unreachable.

---

## 5. Double Claim

`_claimed[roundId][address]` is set to `true` before the token transfer. A second `claim()` call reverts with `AlreadyClaimed` instantly. The bitmap survives root updates — a prior claim in a round cannot be undone by changing the root.

---

## 6. Timelock Bypass

`executionTime` is stored in the operation struct at schedule time and checked on every `execute()` call. `minDelay` is an `immutable` — it cannot be changed after deployment. Miner timestamp manipulation (~15 seconds) is negligible against a 1-day minimum delay.

---

## 7. Transaction Replacement

The action's `keccak256` hash is stored at queue time. `execute()` recomputes the hash from the supplied action and compares:

```solidity
if (_hashAction(action) != op.actionHash) revert ActionHashMismatch(operationId);
```

Any change to `target`, `amount`, or `data` changes the hash and reverts.

---

## 8. Flash-Loan Governance Attack

`Proposal` records `block.number - 1` as the snapshot block. `Main.queue()` rejects any proposal where `snapshotBlock >= block.number`. Flash loans borrow and repay in the same block — by the next block the borrowed voting power is gone.

---

## 9. Governance Griefing

Proposing requires a deposit. A guardian-cancelled proposal loses the deposit to `address(0xdead)`. Self-cancelled or executed proposals get a full refund. Spam proposals cost real ETH.

---

## 10. Large Treasury Drain

ETH transfers are tracked against `MAX_ETH_PER_WINDOW` per `SPENDING_WINDOW`. Even a fully approved proposal cannot drain more than the cap in one day. The timelock delay gives the guardian additional time to intervene.

> **Residual risk:** The cap covers native ETH only. ERC-20 drains are not rate-limited. Add `tokenSpendingLimits[token]` for production deployments.

---

## 11. Unauthorized Execution

A valid `operationId` can only exist if: a whitelisted signer produced a valid EIP-712 signature → `AuthorizationLayer` counted it → threshold was met → `ProposalManager` advanced status → `TimelockEngine.schedule()` was called. Fabricating an `operationId` returns `OperationNotFound`.

---

