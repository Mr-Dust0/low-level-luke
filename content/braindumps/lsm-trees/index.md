---
title: "Log-Structured Merge Trees"
date: 2026-04-07
tags: ["braindump", "databases", "data-structures", "storage"]
summary: "How LSM trees trade read performance for fast writes, and what I got wrong along the way"
draft: false
---

## My Notes

In an LSM tree writes go to memory first to a data structure named memtable where the data is sorted. Data will also be written to a write ahead log so if the machine crashes while there is data in the memory that has not been flushed the data is not lost as we can just replay the entries in the write ahead log.

When the data gets to a certain size or time has passed data is flushed to the disk where two memtables will exist at once in memory, one that is immutable that is getting written to the disk and another one that is the new one where new writes will go to. But if the data was being read before the flush they will use the old memtable in memory not the new one.

The file format that the LSM uses on disk is an SSTable (sorted string table) and they have a sparse index which allows data to be searched and have a bloom filter so can tell for sure if there is no data and be pretty sure if there is some data on the file depending on how good the hash function is. Also SSTables are immutable.

When the data is written to disk there are multiple levels of data that exist where a level is just a multiple of flushed data from the memory and every level above is normally 10x the size and the entries in the level are normally merged together with a level from above and then that data is also in the level above.

Also when reading the data will read the new data first until a match is found for that key and when that is found since its the new data its the most recent.

---

## What I Got Wrong

- **I said readers use the old memtable not the new one during a flush.** Readers actually check both - the new active memtable and the frozen one being flushed. A key could have been written to the new memtable after the freeze, so you need to check it too.

- **I didn't mention deletes at all.** You can't remove a key from an SSTable because SSTables are immutable. Instead you write a tombstone - a special marker that says "this key has been deleted." During compaction the tombstone and any older versions of that key get cleaned up.

- **My description of levels is muddled.** Only L0 contains freshly flushed data from memory. Higher levels (L1, L2, ...) are formed through compaction, not direct flushing. Compaction merges data from a lower level up into the next one. Also SSTables in L0 can have overlapping key ranges, but within each level above L0 key ranges don't overlap.

- **I said the bloom filter accuracy depends on "how good the hash function is."** The false positive rate of a bloom filter depends on the number of hash functions used and the size of the bit array, not just the quality of a single hash function.

- **I said "the data is sorted" but didn't say how.** The memtable is a sorted data structure (usually a skip list or red-black tree), so data is sorted on insert - not as a separate step. When flushed, it's already in order. Compaction just merge-sorts already-sorted SSTables together.

- **I didn't mention what happens to the WAL after a flush.** Once the SSTable is safely written to disk, the corresponding WAL segment can be discarded since the data is now durable on disk.

---

## How LSM Trees Actually Work

An LSM tree (Log-Structured Merge Tree) is a data structure designed to make writes very fast at the cost of slower reads. It's used in databases like LevelDB, RocksDB, Cassandra, and HBase.

### Writing

When a write comes in, two things happen:

1. The write is appended to a **Write-Ahead Log (WAL)** on disk. This is a sequential append so it's fast, and it exists purely for crash recovery.
2. The write is inserted into the **memtable**, an in-memory sorted data structure (typically a skip list or red-black tree).

Because both operations are either sequential I/O (the WAL append) or purely in-memory (the memtable insert), writes are very fast. There's no random disk I/O involved.

### Flushing to Disk

When the memtable reaches a configured size threshold, it needs to be flushed to disk:

1. The current memtable is **frozen** - it becomes immutable and stops accepting new writes.
2. A **new empty memtable** is created, and all incoming writes go there.
3. The frozen memtable is written to disk as an **SSTable** (Sorted String Table) in the background. Since the memtable is already sorted, the SSTable comes out sorted too.
4. Once the SSTable is safely on disk, the corresponding WAL segment can be discarded.

Readers can still read from both the frozen memtable and the new one during this process. There's no downtime.

### SSTables

An SSTable is an immutable, sorted file on disk. Each one contains:

- **Data blocks**: the actual key-value pairs, sorted by key.
- **An index block**: a sparse index mapping keys to the data block offsets where they can be found.
- **A bloom filter**: a probabilistic data structure that can tell you if a key is *definitely not* in this SSTable (and with some false positive rate, if it *might* be).

Because SSTables are sorted, you can do binary search within them. Because they're immutable, they're simple to reason about and cache.

### Levels and Compaction

SSTables are organised into levels:

- **L0**: where freshly flushed SSTables land. SSTables in L0 can have overlapping key ranges since each one is just a snapshot of whatever was in the memtable at flush time.
- **L1, L2, L3, ...**: each subsequent level is typically around 10x the size of the one above. Within each level (except L0), key ranges don't overlap.

**Compaction** is the process of merging SSTables from one level into the next. When a level gets too full, some of its SSTables are selected and merge-sorted with the overlapping SSTables in the level below. This:

- Removes duplicate keys (keeping only the newest version).
- Removes tombstoned keys.
- Reduces the number of SSTables that need to be checked during reads.
- Reclaims disk space.

The downside is **write amplification**: the same data might be rewritten multiple times as it gets compacted through the levels. There's also **space amplification** since multiple versions of the same key can exist across levels until compaction cleans them up.

### Reading

To read a key, you check from newest data to oldest:

1. Check the **active memtable**.
2. Check the **frozen memtable** (if one exists during a flush).
3. Check SSTables on disk, starting from the newest level (L0) and working down.

At each SSTable, the bloom filter is checked first. If it says the key is definitely not there, that SSTable is skipped entirely. For a point lookup, you stop as soon as you find the key. This means reads might be slow in the worst case (key doesn't exist, so you check everything), but bloom filters make this rare in practice.

For a **range query**, you need to check all levels since the range could span data across multiple SSTables. The sorted nature of SSTables makes this a merge operation across the levels.

### Deletes and Tombstones

You can't delete a key by removing it from an SSTable because SSTables are immutable. Instead, you write a **tombstone** - a special marker that says "this key has been deleted." The tombstone goes into the memtable just like a normal write.

When a read encounters a tombstone, it knows the key has been deleted and returns "not found" even if older SSTables still contain the key. During compaction, tombstones and the old versions they shadow are both cleaned up.

### Tradeoffs

| | LSM Tree | B-Tree |
|---|---|---|
| **Writes** | Fast (sequential memory + WAL append) | Slower (random I/O to update pages in place) |
| **Point reads** | Slower (may check multiple levels) | Fast (single tree traversal) |
| **Range reads** | Requires merging across levels | Single sorted traversal |
| **Space** | Amplified (multiple versions until compaction) | Compact (in-place updates) |
| **Write amplification** | High (data rewritten during compaction) | Lower |

LSM trees are a good fit when your workload is write-heavy and you can tolerate some read overhead. This is why they're popular in time-series databases, logging systems, and write-heavy OLTP workloads.

P.S. If there are any mistakes please let me know, I'm by no means an expert.
