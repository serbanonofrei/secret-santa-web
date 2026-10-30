-- =============================================================================
-- join_session
--
-- Adds a participant to an ACTIVE session in ONE transaction:
--   1. Locks the session row (looked up by invite code).
--   2. Checks: session exists, is ACTIVE + published, is not full, and the
--      participant name is not already taken in this session.
--   3. Randomly picks one unassigned color, locks it, and marks it assigned.
--   4. Inserts the participant (active = true, is_organizer = false).
--   5. Returns the participant id, the participant's color, and the gift color
--      (the target_color_id of their color in the Secret Santa chain).
--
-- Concurrency:
--   * The session row is locked FOR NO KEY UPDATE, so joins to the SAME session
--     run one at a time. That makes the "not full" and "duplicate name" checks
--     race-free (two people named "Maria" cannot both pass the check).
--     NO KEY UPDATE (rather than UPDATE) does not block foreign-key checks from
--     other tables that reference the session.
--   * The chosen color row is also locked FOR UPDATE SKIP LOCKED, so even
--     without the session lock two joins could never receive the same color.
--
-- Participant name rules:
--   * Stored name (display): NFC-normalized, internal whitespace collapsed to a
--     single space, trimmed. Length 1-100 characters.
--   * Comparison key: public.normalize_participant_name(): NFKC-normalized,
--     whitespace collapsed, trimmed, lower-cased. "Maria", " maria ", "MARIA"
--     all produce the key "maria".
--   * Names must be unique within a session (all participants, including
--     inactive ones and the organizer). The same name may be used in other
--     sessions.
--
-- Custom SQLSTATEs (mapped to HTTP codes by the join-session Edge Function):
--   SJ001 -> session not found for invite code          (404)
--   SJ002 -> session is not ACTIVE / not published       (409)
--   SJ003 -> session is full (no unassigned color left)  (409)
--   SJ004 -> participant name already used in session    (409)
--   SJ005 -> invalid arguments                           (422)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Name comparison key. IMMUTABLE, so it can also back a unique expression index
-- later if wanted:
--   create unique index on public.participants
--     (session_id, public.normalize_participant_name(participant_name));
-- -----------------------------------------------------------------------------
create or replace function public.normalize_participant_name(p_name text)
returns text
language sql
immutable
strict
parallel safe
set search_path = ''
as $$
  -- NFKC first so compatibility characters (e.g. non-breaking space, full-width
  -- letters) become their plain equivalents before whitespace handling.
  select lower(btrim(regexp_replace(normalize(p_name, NFKC), '\s+', ' ', 'g')));
$$;

create or replace function public.join_session(
  p_invite_code      text,
  p_participant_id   uuid,
  p_participant_name text,
  p_browser_token    text,
  p_recovery_code    text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session        record;
  v_color          record;
  v_display_name   text;
  v_name_key       text;
  v_taken_slots    integer;
  v_participant_id uuid;
  v_my_color       jsonb;
  v_gift_color     jsonb;
begin
  -- ---------------------------------------------------------------------------
  -- Argument checks
  -- ---------------------------------------------------------------------------
  if p_invite_code is null
     or p_invite_code !~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$' then
    raise exception 'inviteCode must be 6 characters from the invite code alphabet'
      using errcode = 'SJ005';
  end if;

  if p_participant_id is null then
    raise exception 'participant id is required' using errcode = 'SJ005';
  end if;

  if p_browser_token is null or btrim(p_browser_token) = '' then
    raise exception 'browser token is required' using errcode = 'SJ005';
  end if;

  if p_recovery_code is null or btrim(p_recovery_code) = '' then
    raise exception 'recovery code is required' using errcode = 'SJ005';
  end if;

  if p_participant_name is null then
    raise exception 'participantName is required' using errcode = 'SJ005';
  end if;

  v_display_name := btrim(regexp_replace(normalize(p_participant_name, NFC), '\s+', ' ', 'g'));

  if char_length(v_display_name) not between 1 and 100 then
    raise exception 'participantName must be between 1 and 100 characters'
      using errcode = 'SJ005';
  end if;

  v_name_key := public.normalize_participant_name(v_display_name);

  -- ---------------------------------------------------------------------------
  -- Lock the session (serializes joins to this session)
  -- ---------------------------------------------------------------------------
  select s.id, s.status, s.published, s.max_participants
    into v_session
    from public.sessions s
   where s.invite_code = p_invite_code
     for no key update;

  if not found then
    raise exception 'No session found for invite code %', p_invite_code
      using errcode = 'SJ001';
  end if;

  if v_session.status <> 'ACTIVE' or not v_session.published then
    raise exception 'Session is not open for joining (status=%, published=%)',
      v_session.status, v_session.published
      using errcode = 'SJ002';
  end if;

  -- ---------------------------------------------------------------------------
  -- Capacity check
  -- ---------------------------------------------------------------------------
  select count(*)
    into v_taken_slots
    from public.participants p
   where p.session_id = v_session.id
     and p.is_organizer = false;

  if v_taken_slots >= v_session.max_participants then
    raise exception 'Session is full (% of % participants)', v_taken_slots, v_session.max_participants
      using errcode = 'SJ003';
  end if;

  -- ---------------------------------------------------------------------------
  -- Duplicate name check (case-insensitive, trimmed, normalized)
  -- ---------------------------------------------------------------------------
  if exists (
    select 1
      from public.participants p
     where p.session_id = v_session.id
       and public.normalize_participant_name(p.participant_name) = v_name_key
  ) then
    raise exception 'Participant name "%" is already taken in this session', v_display_name
      using errcode = 'SJ004';
  end if;

  -- ---------------------------------------------------------------------------
  -- Pick and lock one random unassigned color
  -- ---------------------------------------------------------------------------
  select c.id, c.color_catalog_id, c.target_color_id
    into v_color
    from public.colors c
   where c.session_id = v_session.id
     and c.assigned = false
   order by gen_random_uuid()
   limit 1
     for update skip locked;

  if not found then
    raise exception 'Session is full (no unassigned colors left)'
      using errcode = 'SJ003';
  end if;

  if v_color.target_color_id is null then
    -- A published session must have a complete chain; abort rather than hand
    -- out a color without a gift target.
    raise exception 'Color % in session % has no target color', v_color.id, v_session.id;
  end if;

  update public.colors c
     set assigned = true
   where c.id = v_color.id;

  -- ---------------------------------------------------------------------------
  -- Insert participant
  -- ---------------------------------------------------------------------------
  insert into public.participants (
    id, session_id, assigned_color_id, participant_name,
    browser_token, recovery_code, active, is_organizer
  )
  values (
    p_participant_id, v_session.id, v_color.id, v_display_name,
    p_browser_token, p_recovery_code, true, false
  )
  returning id into v_participant_id;

  -- ---------------------------------------------------------------------------
  -- Result
  -- ---------------------------------------------------------------------------
  select jsonb_build_object('name', cc.color_name, 'hexColor', cc.hex_color)
    into v_my_color
    from public.color_catalog cc
   where cc.id = v_color.color_catalog_id;

  select jsonb_build_object('name', cc.color_name, 'hexColor', cc.hex_color)
    into v_gift_color
    from public.colors t
    join public.color_catalog cc on cc.id = t.color_catalog_id
   where t.id = v_color.target_color_id;

  if v_my_color is null or v_gift_color is null then
    raise exception 'Color catalog entry missing for session %', v_session.id;
  end if;

  return jsonb_build_object(
    'participantId', v_participant_id,
    'myColor',       v_my_color,
    'giftColor',     v_gift_color
  );
end;
$$;

-- Only the service role (ctx.supabaseAdmin) may call join_session.
revoke all on function public.join_session(text, uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.join_session(text, uuid, text, text, text)
  to service_role;
