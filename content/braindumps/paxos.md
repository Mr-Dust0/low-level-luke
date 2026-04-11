---
title: "Paxos"
date: 2026-04-11
tags: ["braindump", "distributed-systems", "consensus"]
summary: "How Paxos coordinates state across machines, and what I got wrong along the way"
draft: false
---

*Trying to remember a topic from memory with no notes, then getting AI to correct it. Basically using active recall to help me remember things better and forcing myself to post it so I do it more often.*

---

## My Notes

Paxos is an way to cordinate state between multiple machines and there are different types of paxos that can run the basic paxos gets an leader to be elected through concenus and there are multiple algrothims that can be used here to pick an leader. Once an leader is elected the leader has to boardcast the state changes to all the approvers which approve of the transactions and once an the set amount of appectors appect the change the change is hten commited and the leaders sends an commit to all teh appectors. You can change teh appectors that you need like using flexible paxos but also want one node to interspect when either doing an read or an write so you know that you have the moost up to date value somewhere in the code. Also you can have listeners which just listen to the changes and don't vote which is useful for backup and getting other nodes up to speed. That are mulitple versions of paxos like fast, epaxos, flexible and somemore that i missing

---

## What I Got Wrong

- **I said "basic Paxos gets a leader elected through consensus."** This mixes things up. Basic Paxos (also called Single-Decree Paxos) doesn't actually require a leader at all - it's a protocol for a group of nodes to agree on a single value. Any node can propose. The thing people usually call "Paxos with a leader" is **Multi-Paxos**, which is an optimisation where a stable proposer is elected so that subsequent values can skip the first phase of the protocol. Leader election in Multi-Paxos is actually done *using* Paxos itself, not with a separate algorithm.

- **I said "the leader broadcasts state changes to approvers which approve the transactions."** The proper terms are **Proposers**, **Acceptors**, and **Learners**. And the protocol is two phases, not a single broadcast. In Phase 1 the proposer sends a Prepare with a proposal number and acceptors respond with a Promise. Only in Phase 2 does it send the actual value in an Accept message. The point of Phase 1 isn't to get approval for a value - it's to lock out older proposers and discover any previously accepted value that must be preserved.

- **I said "a set amount of acceptors accept the change and it's committed."** Roughly right, but the specific amount matters: it's a **majority quorum**. The deep reason is **quorum intersection** - any two majorities must share at least one acceptor. That single overlapping acceptor is what prevents two different values from being chosen, because it'll remember what was accepted before and force the new proposer to re-propose that value.

- **I said "you want one node to intersect when doing a read or a write."** This was the right intuition articulated badly. The "one node in common" property is literally the safety argument for Paxos - but it's about overlap between the **Phase 1 quorum** and any previous **Phase 2 quorum**, not between read and write operations. Classic Paxos doesn't even have a built-in read operation; you typically run a no-op through consensus to get a linearizable read.

- **I said "you can change the acceptors you need like using flexible Paxos."** This is close. **Flexible Paxos** is a real result (Howard, Malkhi, Spiegelman, 2016) but the key insight is more specific: the Phase 1 quorum (Q1) and Phase 2 quorum (Q2) don't both need to be majorities. They just need to intersect (|Q1| + |Q2| > N). So you can shrink Q2 (making the common case faster) at the cost of a bigger Q1 (making leader election slower). It's a tradeoff, not just "pick your acceptors."

- **I said "listeners just listen to the changes and don't vote."** The term is **Learners**. Everything else is right - they observe the decided values but don't participate in the Prepare/Accept voting. They're how state propagates to replicas that don't need to be in the decision path, and they're cheap to add because they don't affect quorum sizes.

- **I didn't mention what Paxos actually guarantees.** Paxos guarantees **safety** (at most one value is ever chosen, and once chosen nothing can un-choose it) but does **not** guarantee **liveness**. Two proposers with rising proposal numbers can livelock each other forever in a classic "duelling proposers" scenario. This is why Multi-Paxos uses a stable leader - not for correctness, but to avoid the livelock.

- **I didn't mention FLP impossibility.** The Fischer-Lynch-Paterson result says deterministic consensus is impossible in a fully asynchronous system with even one faulty node. Paxos works around this by sacrificing liveness during bad conditions (partitions, duelling proposers) while always preserving safety. This is the real theoretical context for why Paxos is structured the way it is.

- **I mentioned variants but didn't explain them.** Worth naming properly:
  - **Multi-Paxos**: amortises Phase 1 by keeping a stable leader.
  - **Fast Paxos**: clients send directly to acceptors, saving a round trip, but the fast-path quorum is larger (roughly 3N/4).
  - **EPaxos (Egalitarian Paxos)**: no leader at all; commutative commands commit in one round trip, conflicting ones take two.
  - **Flexible Paxos**: decouples Phase 1 and Phase 2 quorum sizes.
  - **Cheap Paxos**: uses auxiliary acceptors only when primary ones fail.

---

## How Paxos Actually Works

Paxos is a family of consensus protocols invented by Leslie Lamport. It lets a group of unreliable nodes agree on a single value, and it's the theoretical foundation for most modern replicated state machines (Chubby, Spanner, and many others use Paxos or descendants of it).

### The Three Roles

Every node in Paxos plays one or more of these roles:

- **Proposer**: proposes values to be agreed on.
- **Acceptor**: votes on proposed values. A majority of acceptors forms a quorum.
- **Learner**: learns the chosen value once consensus is reached. Doesn't vote.

A single physical node typically plays all three roles.

### Basic Paxos (Single-Decree)

Basic Paxos agrees on **one** value. The protocol has two phases:

#### Phase 1: Prepare / Promise

1. A proposer picks a proposal number `n` (higher than any it has used before) and sends `Prepare(n)` to a majority of acceptors.
2. Each acceptor that receives `Prepare(n)`:
   - If `n` is higher than any proposal number it has promised, it responds with a `Promise(n)` saying "I won't accept any proposal numbered less than `n`."
   - If it has already accepted a value in a previous proposal, it includes that value and its proposal number in the promise.
3. If the proposer gets promises from a majority, it moves to Phase 2.

#### Phase 2: Accept / Accepted

1. The proposer picks a value to propose. **If any acceptor reported a previously accepted value**, the proposer must use the value from the highest-numbered such report. Otherwise, it's free to choose its own value.
2. It sends `Accept(n, v)` to the acceptors.
3. Each acceptor accepts the proposal unless it has already promised a higher proposal number in the meantime.
4. When a majority accepts, the value is **chosen**. Learners are then notified.

### Why It Works: Quorum Intersection

The safety of Paxos hinges on one fact: **any two majorities of a set share at least one member**.

Imagine a proposer tries to propose a new value. Its Phase 1 must hit a majority. Any previously chosen value was accepted by a different majority. Those two majorities must overlap in at least one acceptor - and that acceptor will report the old accepted value in its Promise. The rule that the new proposer must reuse the highest previously-accepted value then forces consensus to be preserved.

This is why you can't get two different values chosen, even if proposers crash, messages are lost, or multiple proposers run simultaneously.

### Safety vs Liveness

Paxos guarantees **safety**: once a value is chosen, it stays chosen and no other value can be chosen.

Paxos does **not** guarantee **liveness**. Two proposers that keep incrementing proposal numbers can starve each other forever - each one's Phase 1 invalidates the other's Phase 2. This is the "duelling proposers" problem.

The **FLP impossibility** result proves no deterministic consensus algorithm can guarantee both safety and liveness in a fully asynchronous system where even one node can fail. Paxos takes the pragmatic approach of always being safe and being live "usually" - in practice, with a stable leader and reasonable timeouts, it makes progress.

### Multi-Paxos

Basic Paxos is expensive: two round trips per value. Real systems need to agree on a sequence of values (a replicated log), and running Basic Paxos repeatedly is wasteful.

**Multi-Paxos** fixes this with a distinguished proposer (the "leader"):

1. Elect a leader once using Paxos itself.
2. The leader runs Phase 1 **once**, for a whole range of log slots.
3. For each subsequent value, it only needs to run Phase 2.

This collapses each agreement to a single round trip in the common case. It's how most real Paxos deployments work.

If the leader fails, someone else runs Phase 1 with a higher proposal number and becomes the new leader. The safety property means no committed values are ever lost during the transition.

### Flexible Paxos

A beautiful observation: the quorum intersection property only requires that Phase 1's quorum and Phase 2's quorum intersect. They don't both need to be majorities.

Formally, if Q1 is the Phase 1 quorum size and Q2 is the Phase 2 quorum size, you just need:

```
|Q1| + |Q2| > N
```

With N=5 acceptors, you could pick |Q1|=4 and |Q2|=2. Phase 2 (the hot path) is now faster at the cost of slower leader election. This is great for workloads where leaders are stable and writes happen constantly.

### Fast Paxos

Fast Paxos shaves one round trip in the common case by letting clients send values directly to acceptors. The catch: the quorum for Fast Paxos is larger - roughly 3N/4 instead of N/2 + 1 - and collisions require falling back to Classic Paxos.

### EPaxos (Egalitarian Paxos)

EPaxos removes the leader entirely. Every replica can propose commands. Commands that don't conflict (i.e. commute) can commit in one round trip; conflicting ones need two. This is great for geo-replication because clients can talk to their nearest replica instead of a single global leader.

### Paxos vs Raft

Raft is usually described as "Paxos but understandable." It's essentially Multi-Paxos with stronger structural constraints:

- Raft enforces a strong leader that's the only source of log entries.
- Raft requires leaders to have the most up-to-date log, simplifying log repair.
- Raft separates leader election, log replication, and safety into clearly named sub-problems.

Functionally Raft and Multi-Paxos solve the same problem with similar guarantees. Raft's main contribution is pedagogical clarity, which matters a lot when you're trying to implement this stuff correctly.

### Tradeoffs

| | Basic Paxos | Multi-Paxos | Fast Paxos | EPaxos | Flexible Paxos |
|---|---|---|---|---|---|
| **Leader** | None | Stable | Stable | None | Stable |
| **Round trips (common)** | 2 | 1 | 1 (direct) | 1 (non-conflicting) | 1 |
| **Quorum size** | Majority | Majority | ~3N/4 | Majority | Configurable |
| **Livelock risk** | Yes | Rare | Yes on collisions | Rare | Rare |
| **Complexity** | Low | Medium | High | Very high | Low |
| **Best for** | Teaching | Replicated logs | Low-conflict writes | Geo-distribution | Tunable workloads |

Paxos is one of those algorithms where the basic idea is elegant but every practical deployment uses a variant. The core insight - that quorum intersection plus a two-phase protocol gives you agreement under arbitrary failures - is what the whole field builds on.

P.S. If there are any mistakes please let me know, I'm by no means an expert.
