# Phase 2: Backpressure & Streaming

> **Timeline:** 2-3 weeks
> **Goal:** Implement demand-based flow control, enable unbounded crawls
> **Dependencies:** Phase 1 completion

---

## P1 - Implement URLProducer (GenStage)

- [ ] Create `lib/mulberry/crawler/url_producer.ex`
- [ ] Implement GenStage producer behavior
- [ ] Manage URL queue with demand-based dispatch
- [ ] Handle `add_urls/1` for discovered URLs
- [ ] Track pending demand when queue empty

## P1 - Implement RateLimitStage (ProducerConsumer)

- [ ] Create `lib/mulberry/crawler/rate_limit_stage.ex`
- [ ] Subscribe to URLProducer
- [ ] Buffer URLs until rate limit allows
- [ ] Emit URLs to workers on successful token consumption

## P1 - Convert Workers to GenStage Consumers

- [ ] Change from GenServer to GenStage consumer (`worker.ex`)
- [ ] Subscribe to RateLimitStage with demand settings
- [ ] Process URLs and emit results downstream

## P2 - Implement ResultConsumer

- [ ] Create `lib/mulberry/crawler/result_consumer.ex`
- [ ] Subscribe to Workers
- [ ] Support callback-based result streaming
- [ ] Support file-based result streaming
- [ ] Batch results for efficiency

## P2 - Update Supervisor for GenStage

- [ ] Add URLProducer to supervision tree (`supervisor.ex`)
- [ ] Add RateLimitStage to supervision tree
- [ ] Replace DynamicSupervisor with ConsumerSupervisor for workers
- [ ] Add ResultConsumer to supervision tree

## P2 - Implement State Checkpointing

- [ ] Create `lib/mulberry/crawler/checkpoint.ex`
- [ ] Define checkpoint data structure
- [ ] Implement `persist_checkpoint/1` (DETS or external store)
- [ ] Implement `load_checkpoint/1`
- [ ] Add periodic checkpoint timer (30s default)
- [ ] Add checkpoint loading in orchestrator `init/1`
- [ ] Add `handle_info(:checkpoint, state)` handler
- [ ] Store checkpoint reference in state

## P2 - Implement Circuit Breakers

- [ ] Add `{:fuse, "~> 2.5"}` to mix.exs
- [ ] Create `lib/mulberry/crawler/circuit_breaker.ex`
- [ ] Use Fuse library for circuit breaker pattern
- [ ] Wrap retriever calls with circuit breaker
- [ ] Configure per-domain circuit breakers
- [ ] Add blown circuit handling in worker

## P3 - Per-Domain Worker Pools

- [ ] Create `lib/mulberry/crawler/domain_pool.ex`
- [ ] Implement domain-specific worker supervision
- [ ] Configure different pool sizes per domain
- [ ] Isolate failures by domain

---

## Dependencies

```elixir
{:gen_stage, "~> 1.2"}
{:fuse, "~> 2.5"}
```

---

## Progress

| Priority | Total | Done |
|----------|-------|------|
| P1 | 12 | 0 |
| P2 | 17 | 0 |
| P3 | 4 | 0 |
| **Total** | **33** | **0** |
