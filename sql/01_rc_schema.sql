-- RC project: recruiter copilot tables (prefix rc_). Safe to run more than once.

create table if not exists rc_candidates (
  id bigint generated always as identity primary key,
  candidate_key text not null unique,          -- lower(email), or 'name:' + lower(full name) when no email
  full_name text not null,
  email text, phone text, city text, country text,
  languages jsonb not null default '[]',       -- [{"language":"Arabic","level":"native"}]
  skills jsonb not null default '[]',          -- [{"name":"GoHighLevel","years":4}]
  years_total numeric,
  current_title text, summary text,
  cv_text text,                                -- full text of the CV
  cv_date text,                                -- 'YYYY-MM', newest CV wins
  source_file text,                            -- the CV file this record came from
  read_method text not null default 'text',    -- text | ocr
  needs_review boolean not null default false,
  review_reason text,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists rc_cv_files (
  id bigint generated always as identity primary key,
  file_name text not null unique,
  candidate_key text,
  candidate_id bigint references rc_candidates(id) on delete set null,
  status text not null,                        -- current | superseded | duplicate | older_ignored | unreadable
  read_method text,
  needs_review boolean not null default false,
  note text,
  cv_date text,
  processed_at timestamptz not null default now()
);

create table if not exists rc_roles (
  id bigint generated always as identity primary key,
  title text, client_company text, client_name text, client_email text,
  jd_markdown text,
  requirements jsonb not null default '{}',
  transcript text,
  status text not null default 'pending_approval',  -- pending_approval | open | rejected | closed
  slack_channel text, slack_ts text, approved_by text,
  created_at timestamptz not null default now(),
  approved_at timestamptz
);

create table if not exists rc_shortlists (
  id bigint generated always as identity primary key,
  role_id bigint not null references rc_roles(id) on delete cascade,
  candidate_id bigint not null references rc_candidates(id),
  score int, reason text, cv_file text,
  stage text not null default 'Shortlisted',   -- Shortlisted | Approved | Contacted | Replied | Interview | Placed | Rejected
  ghl_contact_id text, ghl_opportunity_id text,
  approved_by text, approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (role_id, candidate_id)
);

create table if not exists rc_outreach (
  id bigint generated always as identity primary key,
  shortlist_id bigint not null references rc_shortlists(id) on delete cascade,
  step int not null,
  send_at timestamptz not null,
  sent_at timestamptz,
  status text not null default 'pending',      -- pending | sent | stopped | failed
  subject text, body text,
  unique (shortlist_id, step)
);

create table if not exists rc_test_runs (
  id bigint generated always as identity primary key,
  run_id text not null,
  question_no int not null,
  question text, expected jsonb, bot_answer text,
  passed boolean, details text,
  created_at timestamptz not null default now()
);

-- Atomic "new CV arrives" logic: insert / replace by newer CV / ignore duplicates and older versions.
create or replace function rc_upsert_candidate(p jsonb) returns jsonb
language plpgsql as $$
declare
  ex rc_candidates%rowtype;
  new_date text := coalesce(nullif(p->>'cv_date',''), to_char(now(),'YYYY-MM'));
  cid bigint;
  act text;
begin
  -- one CV per person at a time: concurrent uploads of the same person wait for each other
  perform pg_advisory_xact_lock(hashtext(coalesce(p->>'candidate_key','')));
  select * into ex from rc_candidates where candidate_key = p->>'candidate_key';

  if not found then
    insert into rc_candidates (candidate_key, full_name, email, phone, city, country, languages, skills, years_total,
                               current_title, summary, cv_text, cv_date, source_file, read_method, needs_review, review_reason)
    values (p->>'candidate_key', p->>'full_name', nullif(p->>'email',''), nullif(p->>'phone',''), p->>'city', p->>'country',
            coalesce(p->'languages','[]'::jsonb), coalesce(p->'skills','[]'::jsonb), nullif(p->>'years_total','')::numeric,
            p->>'current_title', p->>'summary', p->>'cv_text', new_date, p->>'file_name',
            coalesce(p->>'read_method','text'), coalesce((p->>'needs_review')::boolean,false), p->>'review_reason')
    returning id into cid;
    act := 'inserted';

  elsif ex.source_file = p->>'file_name' or new_date > ex.cv_date then
    update rc_cv_files set status = 'superseded' where candidate_id = ex.id and status = 'current';
    update rc_candidates set
      full_name = p->>'full_name', email = nullif(p->>'email',''), phone = nullif(p->>'phone',''),
      city = p->>'city', country = p->>'country',
      languages = coalesce(p->'languages','[]'::jsonb), skills = coalesce(p->'skills','[]'::jsonb),
      years_total = nullif(p->>'years_total','')::numeric, current_title = p->>'current_title', summary = p->>'summary',
      cv_text = p->>'cv_text', cv_date = new_date, source_file = p->>'file_name',
      read_method = coalesce(p->>'read_method','text'),
      needs_review = coalesce((p->>'needs_review')::boolean,false), review_reason = p->>'review_reason',
      updated_at = now()
    where id = ex.id;
    cid := ex.id;
    act := 'replaced';

  elsif new_date = ex.cv_date then
    cid := ex.id; act := 'duplicate';
  else
    cid := ex.id; act := 'older_ignored';
  end if;

  insert into rc_cv_files (file_name, candidate_key, candidate_id, status, read_method, needs_review, note, cv_date)
  values (p->>'file_name', p->>'candidate_key', cid,
          case when act in ('inserted','replaced') then 'current' else act end,
          coalesce(p->>'read_method','text'), coalesce((p->>'needs_review')::boolean,false), p->>'review_reason', new_date)
  on conflict (file_name) do update set
    candidate_key = excluded.candidate_key, candidate_id = excluded.candidate_id, status = excluded.status,
    read_method = excluded.read_method, needs_review = excluded.needs_review, note = excluded.note,
    cv_date = excluded.cv_date, processed_at = now();

  return jsonb_build_object('action', act, 'candidate_id', cid);
end $$;

-- Lock the tables: only the service key (n8n and the portal server) can read or write.
alter table rc_candidates enable row level security;
alter table rc_cv_files   enable row level security;
alter table rc_roles      enable row level security;
alter table rc_shortlists enable row level security;
alter table rc_outreach   enable row level security;
alter table rc_test_runs  enable row level security;
