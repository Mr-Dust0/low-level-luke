---
title: "Linearizability"
date: 2026-04-09
tags: ["braindump", "databases", "distributed-systems", "consistency"]
summary: "What linearizability means in distributed systems, and what I got wrong along the way"
draft: false
---

*Trying to remember a topic from memory with no notes, then getting AI to correct it. Basically using active recall to help me remember things better and forcing myself to post it so I do it more often.*

---

## My Notes

Linaziabity is an contrait on databases where all operations appear to take place at an single point of time so the data so can only be saw after that point of time and no data that was older than piece older than that piece of data can't be read also the data needs to be oredered in realtime and not some and not the invdiauls database time order like is done in serializability. This is pretty easy to do with one db is one version of the data so will get the most recent reads and wirtes as there's only one copy  but as you get distributed databases it gets harder since you have to make sure that the data is replicated to all the majority of the other databases or the correct term an quorum of them need to appect the read or write.

---

## What I Got Wrong

- **I said "operations appear to take place at a single point of time" which is right, but I missed the key detail.** That single point must fall between the operation's invocation and its response. This is what makes linearizability testable - you can check whether there exists a valid ordering where every operation's "effective time" sits within the window of its actual wall-clock duration.

- **I said serializability uses "individual database time order."** That's not quite right. Serializability doesn't use any time order at all - it just requires that the result is equivalent to *some* serial ordering of transactions. That order can be completely different from real time. The key difference is scope too: linearizability is about single operations on single objects, serializability is about transactions across multiple objects. I had the right instinct that they're different, but the characterisation of serializability was off.

- **I said "replicated to the majority of the other databases or the correct term a quorum."** Getting the quorum concept is right, but replicating data to a quorum alone isn't enough for linearizability. Dynamo-style quorum reads/writes (R + W > N) can still produce non-linearizable results due to race conditions. You need consensus protocols (Raft, Paxos) that agree on an *ordering* of operations, not just that a majority has seen the data.

- **I didn't mention the CAP theorem.** Linearizability is specifically the "C" in CAP. The CAP theorem says a distributed system can't simultaneously guarantee Consistency (linearizability), Availability, and Partition tolerance. Since partitions are unavoidable, the real choice is CP (linearizable but may become unavailable during partitions) vs AP (always available but may return stale data).

- **I didn't mention how linearizability is actually achieved.** The standard approaches are consensus protocols (Paxos, Raft, ZAB) that get a quorum to agree on an ordering of operations, or leader-based replication where all reads and writes go through a single leader that serialises them.

- **I didn't mention the cost.** Linearizability requires coordination between nodes on every operation, which adds latency and reduces throughput. This is why many systems choose weaker models (eventual consistency, causal consistency) when the application can tolerate them.

---

## How Linearizability Actually Works

Linearizability is a consistency guarantee for distributed systems. It means the system behaves as if there's only a single copy of the data and every operation happens atomically at one point in time, even though the data may be replicated across many nodes.

### The Core Property

An operation (read or write) takes some real time - it starts with an invocation and ends with a response. Linearizability requires that:

1. Every operation appears to take effect **at a single instant** somewhere between its invocation and response.
2. This ordering **respects real time**. If operation A finishes before operation B starts, then A must appear before B.

This means once a write completes and a subsequent read starts, that read must see the write (or something newer). No going back in time.

### Why It's Easy on a Single Node

On a single database, linearizability is essentially free. There's one copy of the data, and the database serialises access to it (via locks or a single-threaded execution model). Operations are naturally ordered.

### Why It's Hard in Distributed Systems

When data is replicated across multiple nodes, each node has its own copy. The challenge is making all these copies appear as one. Without coordination, different nodes can disagree about the current state:

- A write reaches node A but hasn't reached node B yet.
- A client reads from node B and gets stale data.
- Another client reads from node A and gets the new data.
- From the outside, it looks like time went backwards.

### How It's Achieved

#### Consensus Protocols

The standard approach is to use a consensus protocol like **Raft**, **Paxos**, or **ZAB** (used by ZooKeeper). These protocols ensure that a **quorum** (majority) of nodes agrees on the order of operations before they're committed.

Key point: you only need a majority, not all nodes. In a 5-node cluster, 3 agreeing is enough. This means the system can tolerate some nodes being down.

#### Leader-Based Approaches

A simpler approach: all reads and writes go through a single **leader** node. The leader orders all operations, so linearizability is straightforward. The tradeoff is that the leader is a bottleneck and a single point of failure (though leader election via consensus can handle failover).

#### Quorum Reads and Writes

Systems like Dynamo-style databases use quorum reads and writes (e.g., read from R nodes, write to W nodes, where R + W > N). However, **quorum reads/writes alone are not sufficient for linearizability** in all cases. Additional coordination (like read-repair or consensus) is needed to close the gaps.

### CAP Theorem

The CAP theorem states that a distributed system can provide at most two of three guarantees:

- **Consistency** (linearizability specifically)
- **Availability** (every request gets a response)
- **Partition tolerance** (the system keeps working despite network splits)

Since network partitions are unavoidable in practice, the real choice is between **CP** (linearizable but may become unavailable during partitions) and **AP** (always available but may return stale data during partitions).

### Linearizability vs Serializability

| | Linearizability | Serializability |
|---|---|---|
| **Scope** | Single operations on single objects | Transactions across multiple objects |
| **Ordering** | Must respect real-time order | Any serial order is acceptable |
| **Guarantee** | Recency - reads see the latest write | Isolation - transactions don't interfere |
| **Where it matters** | Distributed replication | Database transaction processing |

**Strict serializability** (also called "one-copy serializability") provides both: transactions that are serializable and whose order matches real time. Systems like Spanner and CockroachDB aim for this.

### Tradeoffs

| | Linearizable Systems | Eventually Consistent Systems |
|---|---|---|
| **Correctness** | Strong - behaves as single copy | Weak - stale reads possible |
| **Latency** | Higher (coordination overhead) | Lower (no waiting for agreement) |
| **Availability** | Reduced during partitions (CP) | Maintained during partitions (AP) |
| **Throughput** | Lower (consensus bottleneck) | Higher (no coordination) |
| **Use cases** | Leader election, distributed locks, financial systems | Caching, social feeds, DNS |

Linearizability is the strongest single-object consistency model but it comes at a cost. Many systems choose weaker models (causal consistency, eventual consistency) when the application can tolerate them, and only use linearizability where correctness demands it.

P.S. If there are any mistakes please let me know, I'm by no means an expert.
