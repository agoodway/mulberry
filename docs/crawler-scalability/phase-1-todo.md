# Phase 1: Critical Fixes & Single-Node Optimization

> **Timeline:** 1-2 weeks
> **Goal:** Fix correctness bugs, eliminate major bottlenecks, enable safe refactoring
> **Dependencies:** None

---

## P0 - Fix URL Loss on Worker Death

- [ ] Modify `handle_info({:DOWN, ...})` to re-queue URL before spawning new worker (`orchestrator.ex:269-280`)
- [ ] Add test: worker crash should result in URL retry
- [ ] Add test: verify no URLs lost during high worker churn

## P0 - Fix URL Loss on Rate Limit

- [ ] Change `spawn_worker/1` to use peek + conditional pop pattern (`orchestrator.ex:399-441`)
- [ ] Add test: rate-limited URLs should remain in queue
- [ ] Add test: verify queue integrity under rate limiting pressure

## P1 - Add Core Module Tests

- [ ] Create `test/mulberry/crawler/orchestrator_test.exs`
- [ ] Test URL queue management
- [ ] Test worker lifecycle (spawn, complete, crash)
- [ ] Test result collection
- [ ] Test crawl completion detection
- [ ] Create `test/mulberry/crawler/worker_test.exs`
- [ ] Test successful crawl flow
- [ ] Test error handling paths
- [ ] Test callback invocation

## P1 - Replace RateLimiter GenServer with ETS

- [ ] Create ETS table with `write_concurrency: true` (`rate_limiter.ex`)
- [ ] Implement atomic token consumption via ETS operations
- [ ] Keep GenServer only for initialization and cleanup
- [ ] Add periodic cleanup of stale domain buckets
- [ ] Update tests for new implementation
- [ ] Benchmark: verify 100x throughput improvement

## P1 - Move visited_urls to ETS

- [ ] Create ETS table in `init/1` (`orchestrator.ex:33, 293-299`)
- [ ] Replace `MapSet.member?` with `:ets.member`
- [ ] Replace `MapSet.put` with `:ets.insert_new`
- [ ] Update State struct (remove `visited_urls` field)
- [ ] Add cleanup on crawl completion

## P1 - Remove visited_urls from Worker Context

- [ ] Remove `visited_urls` from context map (`orchestrator.ex:421-428`)
- [ ] Update `crawler_impl.should_crawl?` contract if needed
- [ ] Provide ETS table name for implementations that need lookup

## P2 - Add Queue Length Counter

- [ ] Add `queue_length` field to State struct (`orchestrator.ex:32, 386-387`)
- [ ] Increment on queue add, decrement on queue pop
- [ ] Replace `:queue.len` calls with counter lookup

## P2 - Fix Robots Cache Memory Leak

- [ ] Add `:timer.send_interval` in `init/1` for cleanup (`robots_txt.ex:303`)
- [ ] Implement `handle_info(:cleanup_expired, state)`
- [ ] Delete entries where `now - fetched_at > ttl`

## P2 - Add ETS write_concurrency to Robots Cache

- [ ] Add `write_concurrency: true` to ETS options (`robots_txt.ex:145-151`)

---

## Dependencies

```elixir
# No new dependencies required
```

---

## Progress

| Priority | Total | Done |
|----------|-------|------|
| P0 | 6 | 0 |
| P1 | 23 | 0 |
| P2 | 8 | 0 |
| **Total** | **37** | **0** |
