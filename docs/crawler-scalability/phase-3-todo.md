# Phase 3: Distributed Architecture

> **Timeline:** 4-6 weeks
> **Goal:** Multi-node support, web-scale crawling
> **Dependencies:** Phase 2 completion

---

## P2 - Evaluate Queue Options

- [ ] Evaluate Oban for job queue
- [ ] Evaluate Broadway for data pipeline
- [ ] Evaluate custom GenStage + external queue
- [ ] Document decision and rationale

## P2 - Implement Distributed Queue

- [ ] Replace in-memory queue with chosen solution
- [ ] Implement URL enqueue with deduplication
- [ ] Implement URL dequeue with rate limiting
- [ ] Add retry logic with exponential backoff

## P2 - Distributed URL Deduplication

- [ ] Create `lib/mulberry/crawler/distributed_dedup.ex`
- [ ] Implement Bloom filter for fast probabilistic check
- [ ] Add Redis/Mnesia backend for authoritative check
- [ ] Configure false positive rate vs memory tradeoff

## P2 - Distributed Rate Limiting

- [ ] Add `{:hammer, "~> 6.1"}` to mix.exs
- [ ] Add `{:hammer_backend_redis, "~> 6.1"}` to mix.exs
- [ ] Evaluate Hammer library with Redis backend
- [ ] Implement distributed token bucket
- [ ] Ensure rate limits enforced globally across nodes

## P3 - Multi-Node Worker Distribution

- [ ] Configure pg (process groups) for worker coordination
- [ ] Implement work stealing between nodes
- [ ] Add node health monitoring

## P3 - Distributed Result Aggregation

- [ ] Implement result collection across nodes
- [ ] Add result deduplication
- [ ] Support distributed callbacks

## P3 - Monitoring & Observability

- [ ] Add Telemetry events for key operations
- [ ] Create Telemetry.Metrics dashboard config
- [ ] Add distributed tracing support
- [ ] Document operational runbook

---

## Dependencies

```elixir
{:oban, "~> 2.17"}  # OR {:broadway, "~> 1.0"}
{:hammer, "~> 6.1"}
{:hammer_backend_redis, "~> 6.1"}
{:redix, "~> 1.2"}
```

---

## Progress

| Priority | Total | Done |
|----------|-------|------|
| P2 | 17 | 0 |
| P3 | 10 | 0 |
| **Total** | **22** | **0** |
