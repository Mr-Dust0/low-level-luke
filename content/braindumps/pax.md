---
title: "PAX, Row Groups, and Parquet"
date: 2026-04-19
tags: ["braindump", "databases", "olap", "storage", "parquet"]
summary: "How PAX-style layouts and Parquet organize data for analytics, and what I got wrong along the way"
draft: false
---

*Trying to remember a topic from memory with no notes, then getting AI to correct it. Basically using active recall to help me remember things better and forcing myself to post it so I do it more often.*

---

## My Notes

partition attributes across is an way to store data on disk that is used for olap databases as it will group rows togehter into something called an row group or another slimar names. And in each row group there will be be sequentill one after anohter elements for each column in the row which allows for better analatical queries as you can veritcioalize the processing and take an advantage of modern hardware and simd instructions. Also it allows you to not have to fetch an whole row just to get an couple of columns if you are projecting the rest out of the results. However the reason why this is normally used in databases over storing the data in column format is that its easier to stich togehter the results for the query as you will ahve access to the anohter coluns that are related to the coloumns that  you just got and can just jump to the offset in the row group where in an pure coloumns storage you would have to find that coloumn and then go to the offset in the column to just stich toghether the two colums. The most popular version of this is parquet and it stores metadata at teh end of the file like an zone map and what the highest and lowest value that has been saw in this file and other information like the size of the metadata so can easily jump to the start of the metadata maybe if the data has been compressed and how to de-compresse it and another infomration like that. The reason why the metadata is at the end of the file and not at the begining is because its mostly used in object storage and hadoop where the fs was only append so it would be an waste of IO and time to rewrite the whole file if you just wanted to change some metadata in the file so that is why it's at the end.

---

## What I Got Wrong

- **I described PAX as if it were the same thing as Parquet row groups.** This is directionally close but not exact. PAX (Partition Attributes Across) is a page layout where each page stores mini-columns. Parquet is a columnar file format with row groups and column chunks. They are related ideas, but not the same format.

- **I implied the main reason to use this over pure column layout is easier stitching of columns.** Reconstructing rows is a cost in any column-oriented layout. Row groups help because related column data for the same row range is physically close, but the bigger win is scan efficiency, compression, and vectorized execution.

- **I treated Parquet metadata as mainly a file-level zone map.** Parquet stores statistics (like min/max) per row group and often per page, then keeps references in the footer metadata. Predicate pushdown uses these stats to skip chunks that cannot match.

- **I said footer-at-end is mainly so metadata can be changed without rewriting.** The key reason is that writers do not know final offsets, sizes, and stats until data is written. Putting metadata at the end enables single-pass writes (important for HDFS-style write-once workflows). In immutable/object-store-style systems, changing metadata still usually means rewriting the file.

- **I mixed storage-system details together.** HDFS historically influenced this design because files were append/write-once during normal generation patterns. Object storage is typically immutable rather than appendable, but Parquet footer reads still work well there via range requests.

---

## How PAX and Parquet Actually Work

Think of physical layouts as a spectrum:

- Row store (NSM): rows are stored together.
- Pure column store (DSM): each column is stored separately.
- PAX-style hybrid: rows are grouped, but columns are stored contiguously inside each group/page.

PAX improves analytical scans because operators often touch only a few columns. Keeping each column contiguous within a row range improves cache behavior and works well with vectorized/SIMD execution.

Parquet uses a similar hybrid idea at file level:

1. A file is split into **row groups**.
2. Inside each row group, data is split into **column chunks**.
3. Each column chunk is encoded/compressed in **pages**.

This gives you columnar scan benefits while keeping related column data for the same row range near each other.

Typical query flow:

1. Read the Parquet footer (metadata at file end).
2. Use schema + stats (min/max, null counts, etc.) to prune row groups/pages.
3. Read only projected columns.
4. Decode/process in vectors, often using SIMD-friendly loops.

Why footer metadata is at the end:

- Writers can stream data first, then write final offsets/statistics once known.
- Readers can issue a small range read near EOF, find metadata quickly, and plan selective reads.
- This design fit Hadoop-era write patterns and still works well on object stores.

### Tradeoffs

| | Row Store (NSM) | Pure Column Store (DSM) | PAX/Parquet-Style Row Groups |
|---|---|---|---|
| **Point lookups for full rows** | Best | Worst | Good |
| **Analytical scans on few columns** | Worst | Best | Best |
| **Row reconstruction cost** | None | Highest | Medium |
| **Compression potential** | Lower | Highest | High |
| **Vectorized/SIMD execution** | Weaker | Strong | Strong |
| **Write/update simplicity** | Simplest | Hardest | Middle |

P.S. If there are any mistakes please let me know, I'm by no means an expert.
