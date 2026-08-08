# Connection pooling

Pooling is not one thing. What you should do differs by engine, and a toolkit
that shipped a uniform "pooler" for all of them would be selling you three
quarters of a lie.

## The short version

| Engine | What to use | Required? | Shipped |
|---|---|---|---|
| PostgreSQL | pgBouncer | **Yes, in production** | Yes — `PROFILES=pg,pooler` |
| MySQL / MariaDB | ProxySQL | Optional | Declared, not yet wired |
| MongoDB | The driver | Never use a proxy | n/a |
| Cassandra | The driver | Never use a proxy | n/a |
| FerretDB | The driver | Never use a proxy | n/a |

## PostgreSQL: pooling is survival

PostgreSQL forks **one operating system process per connection**, and each costs
roughly 10 MB before it does any work. The arithmetic is unforgiving:

| Direct connections | RAM spent before a single query |
|---|---|
| 100 | ~1 GB |
| 300 | ~3 GB |
| 500 | ~5 GB |

That is memory gone to *existing*, not to serving. Past a few hundred
connections the machine also spends real time context-switching between
processes that are mostly idle.

So pgBouncer is **mandatory** under the prod profile, and `check-env` refuses to
start a prod stack without it. Your application opens a thousand connections to
pgBouncer; pgBouncer keeps twenty-five to PostgreSQL.

```bash
make up PROFILES=pg,pooler
```

Then connect to **6432** instead of 5432 — that is the only application change.

```
DBTK_PGBOUNCER_POOL_MODE=transaction
DBTK_PGBOUNCER_DEFAULT_POOL_SIZE=25
DBTK_PGBOUNCER_MAX_CLIENT_CONN=1000
```

### The pooler holds no application passwords

A pooler has to authenticate clients, and the obvious way — give it a list of
users and passwords — makes it a second place every credential lives. This one
does not do that. It has a login role of its own, and resolves everyone else's
verifier on demand:

```sql
SELECT username, password FROM pgbouncer.get_auth($1)
```

`pgbouncer.get_auth` is a `SECURITY DEFINER` function that returns exactly one
row for the name it is given and **excludes superusers**, so compromising the
pooler yields one credential rather than all of them. Its `search_path` is
pinned to `pg_catalog`, because a `SECURITY DEFINER` function that resolves
unqualified names through the caller's path is a privilege-escalation bug.

The function is created by a convergence stage that runs on **every** start, not
only at first init, so you can enable the pooler on a volume created months ago
without destroying data to get it.

Check 33 asserts all of this behaviourally: that a user authenticates through
the pooler, that the pooler's userlist does not contain that user's password,
that eight clients collapse onto a pool of two, and that a wrong password is
still refused.

**Transaction pooling has rules.** A server connection is returned to the pool
at the end of every transaction, so anything that lives on a *session* breaks:

- session-level `SET` (use `SET LOCAL`, inside the transaction)
- `LISTEN` / `NOTIFY`
- advisory locks held across transactions
- prepared statements outside a transaction
- cursors declared `WITHOUT HOLD`

This matters for the RLS kit: `SET LOCAL app.tenant_id` is correct precisely
because it is discarded at commit, so a pooled connection cannot carry one
tenant's identity into the next request. See [the RLS kit](../rls/README.md).

If you need session state, use `session` pool mode and accept a much lower
multiplexing ratio.

## MySQL and MariaDB: pooling helps, but is not survival

The MySQL family uses **one thread per connection**, not a process. A thread is
far cheaper, so a few hundred connections is unremarkable and pooling is a
scaling aid rather than a rescue.

ProxySQL is offered because it brings more than pooling — query routing,
read/write splitting, query rules — and those are the reasons to adopt it. If
all you want is fewer connections, raise `max_connections` first and measure.

**It is declared in the descriptors but not yet wired**, and the reason is worth
stating rather than hiding. ProxySQL has no equivalent of pgBouncer's
`auth_query`: it needs each application user's password (or its hash) in its own
configuration. Shipping that by default would take the property the PostgreSQL
pooler goes to some trouble to preserve — that a compromised pooler yields one
credential, not all of them — and quietly give it up on the engine where pooling
is not even necessary. So it waits for a design that does not, and until then
the descriptor names the image and the generator emits nothing.

That is also why the generator gates on a `compose-pooler.yml` existing rather
than on `POOLING=external`. Declaring an image is not the same as having
configured it, and a pooler that starts but cannot authenticate is worse than no
pooler, because it looks present.

## MongoDB, Cassandra, FerretDB: the driver already does it

**Do not put a connection proxy in front of these.** Their drivers pool
natively, and a proxy actively breaks things:

**MongoDB** drivers implement pooling as a specified part of the driver
(Connection Monitoring and Pooling). The driver also monitors topology, selects
servers by latency and read preference, and retries writes on failover. A proxy
in the middle hides the topology, so all of that stops working.

**Cassandra** drivers hold connections to each node under a load-balancing
policy and multiplex thousands of concurrent requests per connection. The
driver routes each query to a replica that owns the data — token awareness —
which is where much of Cassandra's performance comes from. A proxy defeats it
by making every request appear to come from one place.

For these engines the fix is **one line of application code**, not
infrastructure:

```js
// Correct: one client for the process lifetime. The driver pools behind it.
const client = new MongoClient(uri);

// Wrong: a new client per request. This defeats the pool entirely and is the
// single most common cause of "MongoDB is slow".
async function handler() {
    const client = new MongoClient(uri);   // don't
}
```

The same rule applies to Cassandra's `Session` and FerretDB, which is reached by
MongoDB drivers.

## How this is enforced

Every engine's descriptor declares `DBTK_ENGINE_POOLING=external` or `=driver`,
and check 31 requires a `driver` declaration to state *why*. An engine cannot
quietly acquire a pooler nobody thought about, and it cannot quietly go without
one either.

---

[← Docs index](../README.md#documentation)
