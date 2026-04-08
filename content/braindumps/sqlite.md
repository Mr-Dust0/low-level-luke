---
title: "SQLite Query Execution"
date: 2026-04-08
tags: ["braindump", "databases", "sqlite"]
summary: "How SQLite processes a query from SQL text to results, and what I got wrong along the way"
draft: false
---

*Trying to remember a topic from memory with no notes, then getting AI to correct it. Basically using active recall to help me remember things better and forcing myself to post it so I do it more often.*

---

## My Notes

So what I understand SQLite works like using the Unix philosophy where most things are layers that do just one thing well and then pipe their output to the next layer like the pipe architecture. The first layer is the tokenizer that will take the query and split it into tokens that it can use for the query - these tokens will be the keywords in the query like SELECT and what table to use. Then it's passed to the query optimization layer that will take the query and calculate the costs of different execution paths based on what it knows about the data, this is from using the ANALYZE command so the more you use the ANALYZE command the better your queries will be. After that it's compiled to bytecode to run on the VDBE. In the VDBE the bytecode will be executed but since it's not a tree the execution of the query cannot change as it learns more information about the data that actually lies in the database like most tree-based query execution databases work, which is why it's important to run ANALYZE if you have a slow query. Also SQLite will only have one result in memory at one time and will keep iterating over the rows to get all the results so the memory footprint of a query will be one row at a time until the end of execution which is Halt in the bytecode. Also the bytecode uses 6 registers to control what the bytecode does like normal assembly. You also have a storage layer that abstracts where the data is actually stored, I believe it's using VFS and using its own logic to get the data but I'm not sure about the rest.

---

## What I Got Wrong

- **I called it the "JVDC."** The virtual machine is called the **VDBE** - the Virtual Database Engine. Not JVDC.

- **I said it follows the "Unix philosophy" of piping output between layers.** It's more accurately described as a pipeline architecture with distinct compiler phases. The Unix philosophy is about composing separate programs via stdin/stdout. SQLite's stages are internal compiler phases within a single process, not separate programs. The analogy isn't terrible, but it's not quite right.

- **I skipped the parser entirely.** Between the tokenizer and the query optimizer there's a parser. The tokenizer produces tokens, but the parser is what turns those tokens into a parse tree (AST) that represents the structure of the SQL statement. SQLite uses a Lemon parser generator for this.

- **I said the bytecode uses "6 registers."** The VDBE is a register-based virtual machine, but it doesn't have a fixed set of 6 registers. Each program allocates as many registers as it needs - they're numbered slots (like r0, r1, r2...) and the count depends on the complexity of the query. It's not like x86 with a fixed register file.

- **I said "one result in memory at a time" as though it's always the case.** This is true for simple queries that stream results via a cursor, but operations like ORDER BY, GROUP BY, or subqueries may need to materialise intermediate results in temporary tables or sorters, which can use significantly more memory (or spill to disk).

- **I said the query plan "cannot change as it learns more" because it's bytecode not a tree.** The real reason is that SQLite compiles the query plan ahead of time and commits to it. Some databases use adaptive query execution where the plan can change mid-execution, but SQLite doesn't - the bytecode is fixed once compiled. The tree vs bytecode distinction isn't really the reason; plenty of tree-based executors also use fixed plans.

- **I was vague about the storage layer.** The VFS (Virtual File System) is just the OS abstraction layer for file I/O. Above VFS, SQLite uses a B-tree based storage engine. Each table and index is a separate B-tree. The pager sits between the B-tree layer and VFS, managing pages, caching, and transactions.

---

## How SQLite Query Execution Actually Works

SQLite processes a query through a series of well-defined stages, each transforming the query into a lower-level representation until it can be executed.

### The Pipeline

```
SQL Text → Tokenizer → Parser → Code Generator (with Optimizer) → VDBE → B-Tree → Pager → VFS → Disk
```

Each stage has a clear responsibility and passes its output to the next.

### Tokenizer

The tokenizer (or lexer) takes raw SQL text and breaks it into a stream of tokens. Each token represents a meaningful unit: keywords (`SELECT`, `FROM`, `WHERE`), identifiers (table and column names), literals (numbers, strings), and operators (`=`, `<`, `+`).

The tokenizer doesn't understand the structure of the query - it just splits text into pieces.

### Parser

The parser takes the token stream and builds a parse tree (AST) that represents the grammatical structure of the SQL statement. SQLite uses the Lemon parser generator, which produces an LALR(1) parser.

This is where syntax errors are caught. If your SQL is grammatically wrong, the parser rejects it.

### Code Generator and Query Optimizer

This is where the interesting work happens. The code generator takes the parse tree and produces bytecode for the VDBE. The query optimizer is integrated into the code generator rather than being a separate pass.

The optimizer decides:

- **Which index to use** for each table scan. It estimates costs based on the schema and, if available, statistics gathered by `ANALYZE`.
- **Join order** when multiple tables are involved.
- **Whether to use a covering index** (where the index contains all the columns needed, avoiding a lookup into the main table).

The `ANALYZE` command gathers statistics about the distribution of data in tables and indices, storing them in the `sqlite_stat1` (and optionally `sqlite_stat4`) tables. Without these statistics, the optimizer makes rough guesses. With them, it can make much better decisions about which execution path will be cheapest.

Running `EXPLAIN` on a query shows you the bytecode the code generator produced. Running `EXPLAIN QUERY PLAN` gives you a higher-level summary of the chosen strategy.

### VDBE (Virtual Database Engine)

The VDBE is a register-based virtual machine that executes the bytecode. Each bytecode instruction is an opcode with up to 5 operands (P1-P5), and the program operates on a set of numbered registers (as many as the query needs).

Key characteristics:

- **Register-based, not stack-based.** Each register can hold a value of any SQLite type (NULL, integer, float, text, blob).
- **The plan is fixed.** Once the bytecode is compiled, the execution path doesn't change. There's no adaptive re-planning mid-query.
- **Cursor-based iteration.** For simple queries, the VDBE steps through rows one at a time using cursors. Each call to `sqlite3_step()` advances to the next result row, so only one row of output needs to be in memory at a time.
- **`Halt` ends execution.** The program runs until it hits a Halt instruction.

However, some operations require more memory. `ORDER BY` without an index needs a sorter. `GROUP BY` needs to accumulate groups. Subqueries may materialise into temporary tables. In these cases the one-row-at-a-time model doesn't fully apply.

### B-Tree Storage Engine

Below the VDBE, all data is stored in B-trees:

- **Table B-trees** store row data, keyed by rowid (or the primary key for WITHOUT ROWID tables).
- **Index B-trees** store index entries, mapping indexed column values to rowids.

Each B-tree is a separate logical structure within the database file. When the VDBE opens a cursor on a table or index, it's navigating one of these B-trees.

### Pager

The pager manages the database file as a collection of fixed-size pages (default 4096 bytes). It handles:

- **Page caching** so frequently accessed pages stay in memory.
- **Transaction management** using either a rollback journal or WAL (Write-Ahead Logging).
- **Crash recovery** by ensuring changes are atomic and durable.

### VFS (Virtual File System)

The VFS is the bottom layer - an abstraction over the operating system's file I/O. It handles opening, reading, writing, and locking the database file. Different VFS implementations can be swapped in to store the database on different backends (memory, custom file systems, etc.).

### Tradeoffs

| | SQLite | Client-Server Databases |
|---|---|---|
| **Concurrency** | Single writer, multiple readers (with WAL) | Many concurrent writers |
| **Query planning** | Static (fixed at compile time) | Some support adaptive execution |
| **Deployment** | Zero config, single file | Separate server process |
| **Memory** | Low footprint, streams results | Can use large memory pools |
| **Scale** | Single machine, moderate data sizes | Distributed, large datasets |

SQLite is designed for simplicity and reliability in embedded and single-application use cases. Its architecture trades sophisticated runtime optimisation for a small, predictable, and well-tested implementation.

P.S. If there are any mistakes please let me know, I'm by no means an expert.
