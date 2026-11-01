-- =============================================================================
-- get_my_assignment
--
-- Returns the calling participant's own color and gift color, looked up ONLY by
-- browser token. No other identifier (name, session id, invite code, recovery
-- code, participant id) is accepted.
--
-- Resolution:
--   participants.browser_token
--     -> participants.assigned_color_id -> colors -> color_catalog   (myColor)
--     -> colors.target_color_id         -> colors -> color_catalog   (giftColor)
--
-- Never returned: organizer token, session internals (id, status, invite code),
-- other participants, the color chain, target_color_id or any colors.id values.
-- Error messages never contain the browser token.
--
-- Read-only: no rows are written or locked.
--
-- Requires ux_participants_browser_token (migration 20261030145000), which
-- guarantees a token matches at most one participant, so the participant is
-- loaded directly with a single indexed lookup.
--
-- The parameter is copied into the local variable v_browser_token through a
-- function-qualified reference (get_my_assignment.p_browser_token), and only
-- that variable is used in SQL. No query can confuse it with the column
-- participants.browser_token.
--
-- Custom SQLSTATEs (mapped to HTTP codes by the get-my-assignment Edge Function):
--   GA001 -> participant not found                                     (404)
--   GA002 -> participant is inactive                                   (403)
--   GA003 -> assignment unavailable: no assigned color, missing target,
--            session not ACTIVE/published, or broken chain             (409)
--   GA004 -> invalid input                                             (422)
-- =============================================================================

create or replace function public.get_my_assignment(
  p_browser_token text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_browser_token text := get_my_assignment.p_browser_token;
  v_participant   record;
  v_session     record;
  v_my_color    record;
  v_gift_color  record;
begin
  -- ---------------------------------------------------------------------------
  -- Argument checks
  -- ---------------------------------------------------------------------------
  if v_browser_token is null or btrim(v_browser_token) = '' then
    raise exception 'browserToken is required' using errcode = 'GA004';
  end if;

  if v_browser_token !~ '^BT_[A-Za-z0-9_-]{43}$' then
    raise exception 'browserToken has an invalid format' using errcode = 'GA004';
  end if;

  -- ---------------------------------------------------------------------------
  -- Participant lookup: browser_token is globally unique
  -- (ux_participants_browser_token), so this matches at most one row.
  -- ---------------------------------------------------------------------------
  select p.id, p.session_id, p.participant_name, p.active, p.assigned_color_id
    into v_participant
    from public.participants p
   where p.browser_token = v_browser_token;

  if not found then
    raise exception 'Participant not found' using errcode = 'GA001';
  end if;

  if not v_participant.active then
    raise exception 'Participant is inactive' using errcode = 'GA002';
  end if;

  if v_participant.assigned_color_id is null then
    raise exception 'Participant has no assigned color' using errcode = 'GA003';
  end if;

  -- ---------------------------------------------------------------------------
  -- Session must be published and ACTIVE (checked, never returned)
  -- ---------------------------------------------------------------------------
  select s.status, s.published
    into v_session
    from public.sessions s
   where s.id = v_participant.session_id;

  if not found or v_session.status <> 'ACTIVE' or not v_session.published then
    raise exception 'Assignment is not available for this session' using errcode = 'GA003';
  end if;

  -- ---------------------------------------------------------------------------
  -- My color: assigned_color_id -> colors -> color_catalog
  -- The color must belong to the participant's own session.
  -- ---------------------------------------------------------------------------
  select c.target_color_id, cc.color_name, cc.hex_color
    into v_my_color
    from public.colors c
    join public.color_catalog cc on cc.id = c.color_catalog_id
   where c.id = v_participant.assigned_color_id
     and c.session_id = v_participant.session_id;

  if not found then
    raise exception 'Assigned color is missing' using errcode = 'GA003';
  end if;

  if v_my_color.target_color_id is null then
    raise exception 'Assigned color has no gift target' using errcode = 'GA003';
  end if;

  -- ---------------------------------------------------------------------------
  -- Gift color: target_color_id -> colors -> color_catalog
  -- Same session, and never the participant's own color.
  -- ---------------------------------------------------------------------------
  select cc.color_name, cc.hex_color
    into v_gift_color
    from public.colors t
    join public.color_catalog cc on cc.id = t.color_catalog_id
   where t.id = v_my_color.target_color_id
     and t.session_id = v_participant.session_id
     and t.id <> v_participant.assigned_color_id;

  if not found then
    raise exception 'Gift color is missing or invalid' using errcode = 'GA003';
  end if;

  -- ---------------------------------------------------------------------------
  -- Result (whitelisted fields only)
  -- ---------------------------------------------------------------------------
  return jsonb_build_object(
    'participantId',   v_participant.id,
    'participantName', v_participant.participant_name,
    'myColor', jsonb_build_object(
      'name',     v_my_color.color_name,
      'hexColor', v_my_color.hex_color
    ),
    'giftColor', jsonb_build_object(
      'name',     v_gift_color.color_name,
      'hexColor', v_gift_color.hex_color
    )
  );
end;
$$;

-- Only the service role (ctx.supabaseAdmin) may call this function.
revoke all on function public.get_my_assignment(text)
  from public, anon, authenticated;
grant execute on function public.get_my_assignment(text)
  to service_role;
