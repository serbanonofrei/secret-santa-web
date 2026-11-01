CREATE UNIQUE INDEX IF NOT EXISTS ux_participant_name_per_session
ON public.participants (
    session_id,
    public.normalize_participant_name(participant_name)
);
