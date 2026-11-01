-- =============================================================================
-- Unique browser tokens
--
-- browser_token is the ONLY lookup key for get_my_assignment(), so it must
-- identify exactly one participant across ALL sessions.
--
-- Effects:
--   * get_my_assignment() can load the participant directly (no COUNT check).
--   * join_session() raises 23505 on a token collision, which the join-session
--     Edge Function retries with fresh credentials.
--   * Token lookups use this index instead of a sequential scan.
--
-- Ordered before 20261030150000_get_my_assignment.sql, which relies on it.
--
-- NOTE: fails if duplicate tokens already exist. Check first with:
--   select browser_token, count(*)
--     from public.participants
--    group by browser_token
--   having count(*) > 1;
-- =============================================================================

create unique index if not exists ux_participants_browser_token
  on public.participants (browser_token);
