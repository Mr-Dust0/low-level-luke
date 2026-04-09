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

Linaziabity is an contrait on databases where all operations are atomtic so the data so can only be saw in correct state and no stale data can be saw. So the order of the writes needs to be correct and all reads most get the correct data can't get any stale reads. This is pretty easy to do with one db but as you get distributed databases it gets harder since you have to make sure that the data is replicated to all the other databaes before appecting the write or read and that the data is most up to date. You have PAC (partions, availablity, consitenty ) and you can also have 2 an bit like cap

---

## What I Got Wrong

- **I described linearizability as "all operations are atomic so data can only be seen in a correct state."** That's closer to a description of general consistency or atomicity. Linearizability is specifically about each operation appearing to take effect instantaneously at some single point between its invocation and its response. The critical part is the real-time ordering guarantee: if operation A completes before operation B starts, then A must appear before B. This is what makes it stronger than other consistency models.

- **I didn't distinguish linearizability from serializability.** These are different guarantees. Linearizability is about individual operations on individual objects respecting real-time order. Serializability is about transactions appearing to execute in some serial order (but that order doesn't have to match real time). "Strict serializability" combines both.

- **I said "PAC (partitions, availability, consistency)."** It's the CAP theorem, not PAC. And linearizability is specifically the "C" in CAP - it's the formal consistency model that CAP refers to.

- **I said you need to "replicate to all the other databases before accepting."** This describes synchronous replication to every node, which is one approach but not the only one. Consensus protocols like Raft and Paxos only need a majority (quorum) of nodes to agree, not all of them. A node can be down and the system still makes progress.

- **I said "pretty easy to do with one db."** This is true but worth being precise about why: on a single node there's one copy of the data and a single thread of execution (or locks), so operations are naturally ordered. The entire challenge of linearizability comes from replication - multiple copies of data that need to appear as one.

- **I didn't mention how linearizability is actually achieved in distributed systems.** The standard approach is consensus protocols (Paxos, Raft, ZAB) that get a quorum of nodes to agree on an ordering of operations. Leader-based replication can also work if reads go through the leader.

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
