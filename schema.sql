-- Daybreak database schema (PostgreSQL)

create table users (
  id uuid primary key default gen_random_uuid(),
  email text unique not null,
  name text not null default '',
  password_hash text not null,
  created_at timestamptz not null default now()
);

create table sessions (
  token text primary key,
  user_id uuid not null references users(id) on delete cascade,
  expires_at timestamptz not null
);
create index sessions_user on sessions(user_id);

create table tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  day date not null,
  bucket text not null check (bucket in ('urgent','progress','extra')),
  title text not null,
  note text not null default '',
  done boolean not null default false,
  scheduled_start smallint,
  scheduled_minutes smallint,
  position integer not null default 0,
  created_at timestamptz not null default now()
);
create index tasks_user_day on tasks(user_id, day);
create index tasks_earlier on tasks(user_id, done, day);

create table events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  day date not null,
  bucket text not null check (bucket in ('urgent','progress','extra')),
  title text not null,
  note text not null default '',
  start_min smallint not null,
  duration_min smallint not null default 60,
  created_at timestamptz not null default now()
);
create index events_user_day on events(user_id, day);
