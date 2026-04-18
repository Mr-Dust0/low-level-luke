---
title: "Two-Phase Locking (2PL)"
date: 2026-04-18
tags: ["braindump", "databases", "concurrency", "transactions", "locking"]
summary: "How two-phase locking controls concurrent transactions, and what I got wrong along the way"
draft: false
---

*Trying to remember a topic from memory with no notes, then getting AI to correct it. Basically using active recall to help me remember things better and forcing myself to post it so I do it more often.*

---

## My Notes

Two-phase locking (2PL) is a way to make reads and writes look sequential, even when multiple transactions are happening at once.

Normally in 2PL there is a growing phase, where we acquire all the locks we need, and a shrinking phase, where we release the locks we acquired for the transaction.

This helps prevent issues like dirty reads. For example, if one transaction writes a value and another transaction reads it before the first one commits, then the first transaction aborts, we may need to propagate a rollback to the other transaction too. Otherwise, that second transaction has observed a value that should not have existed.

We also have very strict 2PL where locks are only released at commit time. This helps with dirty reads because other transactions cannot read values we are changing until the transaction is fully committed. The downside is performance, because locks are held for longer. There is also strict 2PL, and I am not fully sure what the exact difference is.

Then we have algorithms for deadlocks, where one transaction holds a lock another needs, and vice versa. You can use strategies like young dies for old or old dies for young, but you need to choose one strategy and stick to it. Another way is choosing a victim based on how much work was done or how many locks are held, then aborting that transaction so execution can continue.

Then you have intention locks, which help in the lock-manager tree. You can set intention locks at higher levels for locks at lower levels. For example, if you lock a tuple in a table, you can set an intention read lock on the table so other transactions know someone is reading tuples there without checking every tuple individually. If another transaction wants an exclusive lock on the whole table, it has to wait.

---

## What I Got Wrong

- **I said 2PL gives the "appearance of sequential writes and reads."** This is close, but the precise guarantee is **conflict serializability**. Basic 2PL guarantees that the final schedule is equivalent to some serial order of transactions. It does not automatically guarantee every stronger isolation property unless you combine it with additional rules (for example, strictness and predicate/index-range locking).

- **I mixed up dirty reads and non-repeatable reads in the rollback example.** If `T2` reads data written by `T1` before `T1` commits, and then `T1` aborts, that is a **dirty read**. The main consequence is often **cascading aborts** (you may need to abort `T2` too). Non-repeatable reads are a different anomaly where the same transaction reads the same row twice and gets different committed values.

- **I wasn't sure about the difference between strict 2PL and very strict/rigorous 2PL.** The difference is lock release timing:
  - **Strict 2PL**: hold all **exclusive (X)** locks until commit/abort; shared locks may be released earlier.
  - **Rigorous 2PL** (often called strong strict 2PL): hold **both shared (S) and exclusive (X)** locks until commit/abort.
  - What I called "very strict 2PL" maps to rigorous/strong strict 2PL.

- **I implied standard 2PL itself prevents dirty reads.** Basic 2PL alone does not necessarily prevent dirty reads because a transaction can release an exclusive lock before commit during the shrinking phase. Preventing dirty reads cleanly is why systems use **strict** (or rigorous) 2PL in practice.

- **I mentioned deadlock strategies ("young dies for old" / "old dies for young") but not the exact rules.** These are:
  - **Wait-Die** (non-preemptive): older transaction waits; younger transaction aborts ("dies").
  - **Wound-Wait** (preemptive): older transaction aborts younger one ("wounds" it); younger waits for older.
  You pick one policy and apply it consistently using transaction timestamps.

- **I didn't mention deadlock detection as a separate approach.** Another common strategy is to allow waits, build a **waits-for graph**, detect cycles, then pick a victim to abort (often based on least work done, fewest locks held, or youngest age).

- **My intention-lock description was directionally right but incomplete.** Intention locks are part of **multi-granularity locking**. Before locking a row, a transaction first places intention locks on ancestors (table/page). That lets the lock manager check compatibility at higher levels without scanning all descendants.

- **I didn't call out key intention lock modes.** In practice, systems use modes like `IS`, `IX`, and `SIX`, each with a compatibility matrix. This is what makes hierarchical locking efficient and safe.

---

## How Two-Phase Locking Actually Works

Two-phase locking (2PL) is a concurrency-control protocol that makes concurrent transactions behave like some serial execution order. It is one of the classic ways relational databases enforce isolation.

### Core Idea

Each transaction has two phases:

1. **Growing phase**: it can acquire locks, but cannot release any.
2. **Shrinking phase**: once it releases its first lock, it can release more locks but cannot acquire new ones.

That single rule is enough to ensure conflict-serializable schedules.

### Lock Types

At minimum, row-level locking uses:

- **Shared lock (`S`)**: required for reads; multiple transactions can hold `S` on the same item.
- **Exclusive lock (`X`)**: required for writes; blocks all other `S`/`X` locks on the same item.

Real systems add update locks and intention locks for performance and hierarchy support.

### Why Strict Variants Matter

Basic 2PL guarantees serializability, but it can still allow cascading aborts if `X` locks are released before commit. So production systems usually prefer stricter variants:

- **Strict 2PL**: keep all `X` locks until commit/abort.
- **Rigorous (strong strict) 2PL**: keep all `S` and `X` locks until commit/abort.

These reduce anomaly risk and simplify recovery, but they hold locks longer, which increases blocking.

### Deadlocks Under 2PL

Because transactions wait on each other's locks, deadlocks can happen naturally:

- `T1` holds lock A, needs B.
- `T2` holds lock B, needs A.

Systems handle this with one of three approaches:

- **Prevention via timestamps** (`wait-die`, `wound-wait`).
- **Detection + resolution** (waits-for graph cycle detection, then abort a victim).
- **Conservative/static 2PL** (acquire all needed locks before execution; avoids deadlocks but reduces concurrency and is hard when lock sets are unknown).

### Intention Locks and Lock Trees

Databases lock at multiple granularities (table, page, row). Intention locks make this workable:

- To lock a row in `S`, place `IS` on ancestors first.
- To lock a row in `X`, place `IX` on ancestors first.

This advertises lower-level intent at higher levels. A transaction asking for a table-level `X` lock can quickly see incompatibilities from ancestor lock modes, without checking every row lock individually.

### Tradeoffs

| | Basic 2PL | Strict 2PL | Rigorous 2PL |
|---|---|---|---|
| **Conflict serializable** | Yes | Yes | Yes |
| **Dirty reads prevented** | Not guaranteed | Yes | Yes |
| **Cascading abort risk** | Higher | Lower | Lowest |
| **Lock hold time** | Shorter | Longer | Longest |
| **Concurrency** | Higher | Medium | Lower |
| **Recovery simplicity** | Harder | Easier | Easiest |

2PL is a foundational idea because it's conceptually simple and gives strong guarantees. Most real engines then layer on strictness, multi-granularity locking, deadlock handling, and practical heuristics to balance correctness with throughput.

P.S. If there are any mistakes please let me know, I'm by no means an expert.
