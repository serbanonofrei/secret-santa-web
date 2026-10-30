-- =============================================================================
-- publish_session
--
-- Publishes a DRAFT session in ONE transaction:
--   1. Verifies the organizer token belongs to the session.
--   2. Builds a shuffled circular chain of the session's colors:
--        c1 -> c2 -> c3 -> ... -> cN -> c1
--      Every color gets exactly one target and is the target of exactly one
--      other color. Nobody targets themselves (N >= 2), and the chain is a
--      single cycle with no closed sub-loops.
--   3. Writes public.colors.target_color_id for every color in the session.
--   4. Sets the session to status = 'ACTIVE', published = true, draft = false.
--   5. Returns session information. The chain itself is NOT returned, because
--      it is the secret.
--
-- Shuffling: ORDER BY gen_random_uuid() uses pg_strong_random (a CSPRNG), unlike
-- random(), so the chain cannot be predicted from earlier outputs.
--
-- Concurrency: the session row is locked FOR UPDATE, so two concurrent publish
-- calls are serialized; the second sees status = 'ACTIVE' and fails with SP003.
--
-- Custom SQLSTATEs (mapped to HTTP codes by the publish-session Edge Function):
--   SP001 -> session not found                         (404)
--   SP002 -> organizer token does not match session    (403)
--   SP003 -> session is not in DRAFT state             (409)
--   SP004 -> session has fewer than 2 colors           (422)
--   SP005 -> invalid arguments                         (422)
-- =============================================================================

create or replace function public.publish_session(
  p_session_id      uuid,
  p_organizer_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session      public.sessions%rowtype;
  v_color_count  integer;
  v_updated      integer;
begin
  -- ---------------------------------------------------------------------------
  -- Argument checks
  -- ---------------------------------------------------------------------------
  if p_session_id is null then
    raise exception 'sessionId is required' using errcode = 'SP005';
  end if;

  if p_organizer_token is null or btrim(p_organizer_token) = '' then
    raise exception 'organizerToken is required' using errcode = 'SP005';
  end if;

  -- ---------------------------------------------------------------------------
  -- Lock the session row (serializes concurrent publish attempts)
  -- ---------------------------------------------------------------------------
  select *
    into v_session
    from public.sessions s
   where s.id = p_session_id
     for update;

  if not found then
    raise exception 'Session % not found', p_session_id using errcode = 'SP001';
  end if;

  -- ---------------------------------------------------------------------------
  -- Authorize: the organizer token must belong to this session
  -- ---------------------------------------------------------------------------
  if not exists (
    select 1
      from public.organizers o
     where o.session_id = p_session_id
       and o.organizer_token = p_organizer_token
  ) then
    raise exception 'Organizer token is not valid for this session' using errcode = 'SP002';
  end if;

  -- ---------------------------------------------------------------------------
  -- State check: only DRAFT, unpublished sessions can be published
  -- ---------------------------------------------------------------------------
  if v_session.status <> 'DRAFT' or v_session.published then
    raise exception 'Session is not in DRAFT state (status=%, published=%)',
      v_session.status, v_session.published
      using errcode = 'SP003';
  end if;

  -- ---------------------------------------------------------------------------
  -- Lock the session's colors and count them
  -- ---------------------------------------------------------------------------
  perform 1
     from public.colors c
    where c.session_id = p_session_id
      for update;

  select count(*)
    into v_color_count
    from public.colors c
   where c.session_id = p_session_id;

  if v_color_count < 2 then
    raise exception 'Session needs at least 2 colors to publish, found %', v_color_count
      using errcode = 'SP004';
  end if;

  -- ---------------------------------------------------------------------------
  -- Shuffled circular chain: position i targets position (i mod N) + 1
  -- ---------------------------------------------------------------------------
  with shuffled as (
    select c.id,
           row_number() over (order by gen_random_uuid()) as pos
      from public.colors c
     where c.session_id = p_session_id
  ),
  chain as (
    select giver.id    as color_id,
           receiver.id as target_id
      from shuffled giver
      join shuffled receiver
        on receiver.pos = (giver.pos % v_color_count) + 1
  )
  update public.colors c
     set target_color_id = chain.target_id
    from chain
   where c.id = chain.color_id;

  get diagnostics v_updated = row_count;

  if v_updated <> v_color_count then
    -- Should be impossible; abort so we never publish a broken chain.
    raise exception 'Chain generation updated % of % colors', v_updated, v_color_count;
  end if;

  -- ---------------------------------------------------------------------------
  -- Activate the session
  -- ---------------------------------------------------------------------------
  update public.sessions s
     set status    = 'ACTIVE',
         published = true,
         draft     = false
   where s.id = p_session_id
  returning * into v_session;

  -- ---------------------------------------------------------------------------
  -- Result (no target_color_id values: the chain stays secret)
  -- ---------------------------------------------------------------------------
  return jsonb_build_object(
    'sessionId',       v_session.id,
    'sessionName',     v_session.session_name,
    'inviteCode',      v_session.invite_code,
    'maxParticipants', v_session.max_participants,
    'status',          v_session.status,
    'published',       v_session.published,
    'draft',           v_session.draft,
    'colorCount',      v_color_count
  );
end;
$$;

-- Only the service role (ctx.supabaseAdmin) may call this function.
revoke all on function public.publish_session(uuid, text)
  from public, anon, authenticated;
grant execute on function public.publish_session(uuid, text)
  to service_role;
