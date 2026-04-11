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

Paxos is a way to coordinate state between multiple machines and there are different types of Paxos that can run. The basic Paxos is where each node can propose a value, and for the value to be accepted it has to be accepted by the majority of the other nodes, or a quorum. When the proposer proposes a value it locks out other proposals that don't have a higher proposal number. If the proposal proposed is the highest number then you get a promise back, then it goes to the second phase of the two phase commit where the data changes are committed.

You can change the acceptors that you need like using flexible Paxos, but also want one node to intersect when either doing a read or a write so you know that you have the most up to date value somewhere in the data. Also you can have learners which just listen to the changes and don't vote, which is useful for backup and getting other nodes up to speed.

Also with Paxos, FLP is still not possible but Paxos gives up liveness in order to get results in the real world, with a possibility of delays and downtime in the deployment. There are multiple versions of Paxos like fast, epaxos, flexible.

---

## What I Got Wrong

- **I called it a "two phase commit".** Paxos does have two phases (Prepare/Promise and Accept/Accepted), but it is **not** Two-Phase Commit. 2PC is a completely different protocol used for atomic commit across distributed databases: a coordinator asks every participant if they can commit, and only commits if *all* of them agree. 2PC blocks forever if the coordinator dies mid-protocol. Paxos is a consensus protocol that tolerates minority failures via majority quorums and never blocks permanently on single failures. They're easy to confuse because both have "two phases" but they solve different problems and behave very differently under failure.

- **I said "you get a promise back then it goes to the second phase where the data changes are committed."** Roughly right but glossing over the most important part of Phase 1. The Promise isn't just "yes, your proposal number is the highest" - each acceptor also reports any value it has *previously accepted* and under which proposal number. The new proposer is then **obligated** to reuse the highest previously-accepted value if one exists. This is how Paxos preserves consensus when proposers crash: Phase 1 is really a "discover what might already be chosen" phase, not just a locking phase.

- **I said "you want one node to intersect when doing a read or a write."** Right intuition, wrong framing. The "one node in common" is the **quorum intersection** property, and it is literally the safety argument for Paxos - but the overlap is between a new proposer's **Phase 1 quorum** and any previous **Phase 2 quorum**, not between reads and writes. Classic Paxos doesn't really have reads at all; to do a linearizable read you typically run a no-op round through consensus so you know you've seen everything previously committed.

- **I didn't mention Multi-Paxos.** I listed fast, EPaxos and flexible as variants but missed the one everyone actually uses in practice. Basic Paxos agrees on a *single* value and takes two round trips to do it. **Multi-Paxos** elects a stable leader, runs Phase 1 once for a whole range of log slots, and then only needs Phase 2 for each subsequent value. This collapses the common case to a single round trip and is how most production Paxos deployments work.

- **I didn't formally name the three roles.** Paxos has **Proposers**, **Acceptors** and **Learners**. I mentioned proposers and learners but it's worth being explicit: a proposer proposes values, an acceptor votes, and a learner observes the decided value without participating in voting. A single physical node usually plays all three.

- **I said "FLP is still not possible" which is muddled.** The Fischer-Lynch-Paterson impossibility result says no deterministic consensus algorithm can guarantee *both* safety and liveness in a fully asynchronous system where even one node can fail. I had the right idea - Paxos gives up liveness to sidestep this - but the phrasing implies FLP is some limitation Paxos hits, when really it's the theoretical reason Paxos is structured the way it is. Paxos always preserves safety and is live "usually"; duelling proposers can starve each other forever in pathological cases, which is the practical face of FLP.

- **I didn't mention what "giving up liveness" looks like in practice.** Two proposers with rising proposal numbers can livelock each other - each one's Phase 1 invalidates the other's Phase 2. This is the classic "duelling proposers" problem. Multi-Paxos avoids it with a stable leader, not because leaders are needed for correctness, but because having one proposer at a time means there's nobody to duel with.

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
