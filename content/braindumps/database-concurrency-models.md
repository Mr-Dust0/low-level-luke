---
title: "Database Concurrency Models"
date: 2026-04-12
tags: ["braindump", "databases", "concurrency"]
summary: "How databases handle multiple clients at once, and what I got wrong along the way"
draft: false
---

*Trying to remember a topic from memory with no notes, then getting AI to correct it. Basically using active recall to help me remember things better and forcing myself to post it so I do it more often.*

---

## My Notes

There are three main modes that a database can use to handle multiple requests at once, which is expected nowadays as the number of cores per computer has gone up and the number of clients using a database has increased.

The first way to handle this is to have a process per connection. This enables better isolation between the processes and means that one process can completely fail but not affect the other processes. This is used in PostgreSQL and is handy since in PostgreSQL you can have extensions that may crash a process and that won't affect the rest of your database. However it's a lot harder to share and coordinate state across processes compared to threads, as threads are in the same process so they can just use the local heap in the process to share data. In the process model you have to have a shared memory section which all processes can access and manage things like locks there, which will increase the time to access this memory and have more overhead per client taking more system resources.

The second is using system-level threads. This has a lot less overhead and the process heap can be used to share state between the threads running, which makes it easy to manage locks and shared resources. However if something crashes here you can take down the whole process, so it will be harder to code this way and you have to be a lot more locked down and not allow as many community-added features so that the database can remain stable.

Then you have lightweight threads, which is when the database manages the threads itself, not the kernel, like Go goroutines. These take less overhead than system threads and it's easy to share data between them. However this doesn't give the kernel a chance to optimise the threads to run in the priority they should, and could lead to performance issues also since it runs on just one real thread and multile lightweight threads behid the scenes then it wond be able to get all teh resources it needs to run all those threads and can't use multiple cpus at once. It is also a lot harder to code using this style.

You can also group the processes or threads into a pool to have less overhead when a new client comes in and just pick a process from that pool instead of creating a new one, and the same for threads, which is why it's a popular technique.

---

## What I Got Wrong

- **I said lightweight threads run "on just one real thread".** This isn't how production implementations work. The whole point of user-space threading is **M:N scheduling** - multiplexing M lightweight threads onto N OS threads, where N is typically one per CPU core. Go's scheduler maps goroutines onto `GOMAXPROCS` OS threads (defaulting to the number of cores). If it really were just one OS thread, you'd never use more than one core and the model would be useless for CPU-bound work. The lightweight threads are cheap to create and switch between, but they still run across multiple real OS threads to utilise the whole machine.

- **I didn't mention the event-driven / async I/O model.** This is arguably the fourth major model and a big omission. Instead of dedicating a thread or process per connection, an event loop uses non-blocking I/O (epoll on Linux, kqueue on BSD) to multiplex thousands of connections on a single thread. Redis is the textbook example - it's single-threaded but handles enormous throughput because most of the time is spent waiting on I/O, not computing. Many modern databases use this approach or hybrid versions of it.

- **I didn't mention hybrid approaches.** Most production databases don't use a single pure model. MySQL uses a thread-per-connection model but has a thread pool plugin. Modern PostgreSQL (from v17 onward) is exploring async I/O and io_uring integration. Systems like ScyllaDB use a thread-per-core model with async I/O within each core's thread. The trend is toward combining models to get the best of each.

- **I said the process model has "more overhead per client taking more system resources" but didn't quantify why this matters.** Each PostgreSQL backend process consumes its own memory for query parsing, planning, caching, and local buffers - typically several megabytes each. With thousands of connections this adds up fast, which is why PostgreSQL deployments almost always put a connection pooler in front. The thread model avoids this because threads share the process address space, so per-connection memory overhead is much lower.

---

## How Database Concurrency Models Actually Work

Modern databases need to serve many clients simultaneously. The choice of concurrency model affects everything from isolation guarantees to memory usage to maximum connection counts. There are four main approaches, plus pooling as a universal optimisation.

### Process Per Connection

Each incoming connection gets its own OS process. PostgreSQL is the canonical example.

**How it works**: when a client connects, the postmaster (PostgreSQL's main process) forks a new backend process. That process handles the entire lifecycle of that connection - parsing queries, planning, executing, returning results. All backend processes share access to a shared memory region that holds the buffer pool, WAL buffers, lock tables, and other global state.

**Why it's good**: process isolation is excellent. If an extension or a bad query causes a crash, only that one connection dies. The OS enforces memory protection between processes, so corruption in one backend can't silently corrupt another. This is why PostgreSQL can afford to have a rich extension ecosystem - extensions run in-process but a crash is contained.

**Why it's costly**: each process has its own virtual address space, its own copies of parsed query plans, its own local buffer cache. Memory usage scales linearly with connection count. Context switching between processes is more expensive than between threads because the OS may need to flush TLB entries. Coordinating between processes requires explicit shared memory and inter-process communication (shared memory segments, semaphores).

### Thread Per Connection

Each incoming connection gets its own OS thread within a single database process. MySQL's default model works this way.

**How it works**: the database runs as a single process with a thread for each connection. All threads share the process heap, so global data structures like buffer pools and lock managers live in ordinary memory accessible to every thread.

**Why it's good**: sharing state between threads is cheap - it's just memory reads and writes protected by mutexes. Per-connection overhead is lower than the process model because threads share the address space. Context switching between threads in the same process is faster than between processes.

**Why it's risky**: a crash in any thread can bring down the entire process and every connection with it. Memory corruption in one thread (buffer overflows, use-after-free) silently affects all others. This means the database engine needs to be more defensive - less room for community extensions to run arbitrary code in-process. Thread safety bugs (data races, deadlocks) are notoriously hard to debug.

### User-Space / Lightweight Threads

The database implements its own thread scheduler rather than relying on OS threads. Go's goroutines are a well-known example of this pattern (though in a language runtime, not a database per se).

**How it works**: the database creates a small number of OS threads (often one per CPU core) and multiplexes many lightweight "tasks" or "fibers" across them. This is M:N scheduling - M user-space threads on N OS threads. The database's scheduler decides which task runs on which OS thread and when to switch.

**Why it's good**: creating a lightweight thread is extremely cheap (often just allocating a small stack, a few kilobytes vs the megabytes an OS thread might reserve). Context switching happens in user space without a system call. You can have millions of concurrent tasks where you'd run out of resources with OS threads.

**Why it's tricky**: the database scheduler doesn't have the OS's view of system-wide priorities, CPU topology, or power management. If a lightweight thread blocks on a system call (disk I/O, network), it blocks its underlying OS thread too unless the scheduler is designed to handle this (usually via async I/O or a dedicated I/O thread pool). Building a correct, efficient user-space scheduler is a significant engineering effort.

### Event-Driven / Async I/O

Instead of a thread or process per connection, a single thread uses non-blocking I/O to handle many connections.

**How it works**: the database registers interest in I/O events (data arriving on a socket, disk read completing) with the OS via epoll (Linux) or kqueue (BSD). A tight event loop waits for events and dispatches handlers. No connection has a dedicated thread - work is done in short, non-blocking chunks.

**Why it's good**: incredibly efficient for I/O-bound workloads. A single thread can handle tens of thousands of concurrent connections because most connections are idle most of the time. Redis serves millions of operations per second this way. Memory overhead per connection is minimal.

**Why it's limited**: CPU-bound work blocks the event loop and stalls every connection. Long-running queries are problematic. The programming model (callbacks, state machines) is harder to reason about than sequential per-connection code. Most real implementations add worker threads for CPU-heavy operations, making it a hybrid approach.

### Connection Pooling

Not a concurrency model itself, but an essential optimisation layered on top of any model. Instead of creating and destroying a process or thread for each client connection, you maintain a pool of pre-created workers and assign incoming connections to available ones.

**External pooling**: tools like PgBouncer sit between clients and PostgreSQL, multiplexing hundreds of client connections onto a smaller number of backend processes.

**Internal pooling**: the database itself maintains a thread pool. MySQL's thread pool plugin does this - instead of a thread per connection, a fixed number of threads service all connections.

Pooling reduces the overhead of process/thread creation, limits resource consumption under load, and smooths out bursts of connections.

### Tradeoffs

| | Process per connection | Thread per connection | User-space threads | Event-driven |
|---|---|---|---|---|
| **Isolation** | Excellent | Poor | Poor | Poor |
| **Memory per connection** | High | Medium | Low | Very low |
| **Max connections** | Hundreds-low thousands | Thousands | Millions | Millions |
| **State sharing** | Shared memory (explicit) | Heap (direct) | Heap (direct) | Heap (direct) |
| **Crash impact** | Single connection | Entire database | Entire database | Entire database |
| **Extension safety** | Good | Risky | Risky | Risky |
| **Example** | PostgreSQL | MySQL | ScyllaDB (seastar) | Redis |

In practice, most modern databases use hybrid approaches. The pure models are useful for understanding the tradeoffs, but production systems mix and match: thread pools with async I/O, process-per-connection with external connection pooling, user-space scheduling with io_uring for async disk access.

P.S. If there are any mistakes please let me know, I'm by no means an expert.
