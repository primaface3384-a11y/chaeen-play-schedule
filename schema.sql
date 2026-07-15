-- 채은이 놀이 스케줄러 — Supabase 테이블 스키마
-- Supabase 프로젝트 대시보드 → SQL Editor 에서 이 전체를 붙여넣고 실행하세요.
--
-- ⚠️ 이 파일에는 절대로 DROP TABLE / TRUNCATE / DELETE FROM (조건 없이) 를
-- 추가하지 마세요. 스키마를 바꿔야 하면 항상 새 파일(예: migrations/0002_*.sql)로
-- "추가만 하는" 형태로 작성하고, 실행 전에 반드시 데이터를 백업하세요.
-- 자세한 내용은 저장소 루트의 CLAUDE.md 참고.

-- 1) 놀이 기록 테이블
create table if not exists play_entries (
  id uuid primary key default gen_random_uuid(),
  entry_date date not null,
  type text not null,
  minutes integer not null check (minutes > 0),
  created_at timestamptz not null default now()
);

create index if not exists play_entries_date_idx on play_entries (entry_date);

-- 2) 놀이 종류 테이블 (편집 가능한 목록)
create table if not exists play_types (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

-- 3) 기본 놀이 종류 8개 미리 넣기 (이미 있으면 건너뜀)
insert into play_types (name, sort_order)
values
  ('블록놀이', 0), ('그림그리기', 1), ('책읽기', 2), ('소꿉놀이', 3),
  ('야외놀이', 4), ('노래율동', 5), ('퍼즐', 6), ('물놀이', 7)
on conflict (name) do nothing;

-- 4) RLS(행 단위 보안) 활성화
-- 가족만 아는 URL/키로 쓰는 개인용 도구이므로, 익명 키로 읽기/쓰기를 모두 허용합니다.
-- (같은 anon key를 아는 사람만 접근 가능 — 완전 공개 API는 아니지만, 비밀번호 수준의 보안은 아니라는 점 참고하세요.)
alter table play_entries enable row level security;
alter table play_types enable row level security;

create policy "anyone can read entries" on play_entries for select using (true);
create policy "anyone can insert entries" on play_entries for insert with check (true);
create policy "anyone can update entries" on play_entries for update using (true);
create policy "anyone can delete entries" on play_entries for delete using (true);

create policy "anyone can read types" on play_types for select using (true);
create policy "anyone can insert types" on play_types for insert with check (true);
create policy "anyone can update types" on play_types for update using (true);
create policy "anyone can delete types" on play_types for delete using (true);

-- 5) 실시간(Realtime) 구독 활성화 — 이게 있어야 서로 화면이 자동으로 업데이트돼요.
alter publication supabase_realtime add table play_entries;
alter publication supabase_realtime add table play_types;

-- ============================================================
-- 6) 안전장치: 삭제된 데이터를 보관함 테이블에 자동 백업
-- 앱 버그든, 실수로 잘못 실행한 SQL이든, 행이 지워지기 직전에
-- 아래 보관함 테이블로 복사해둡니다. 실수로 지워졌어도 여기서 복구 가능해요.
-- (이 블록은 몇 번을 다시 실행해도 안전합니다 — 기존 데이터를 건드리지 않아요.)
-- ============================================================

create table if not exists play_entries_deleted (
  id uuid,
  entry_date date,
  type text,
  minutes integer,
  created_at timestamptz,
  deleted_at timestamptz not null default now()
);

create table if not exists play_types_deleted (
  id uuid,
  name text,
  sort_order integer,
  created_at timestamptz,
  deleted_at timestamptz not null default now()
);

create or replace function archive_deleted_play_entry()
returns trigger as $$
begin
  insert into play_entries_deleted (id, entry_date, type, minutes, created_at)
  values (old.id, old.entry_date, old.type, old.minutes, old.created_at);
  return old;
end;
$$ language plpgsql;

create or replace function archive_deleted_play_type()
returns trigger as $$
begin
  insert into play_types_deleted (id, name, sort_order, created_at)
  values (old.id, old.name, old.sort_order, old.created_at);
  return old;
end;
$$ language plpgsql;

drop trigger if exists trg_archive_play_entries on play_entries;
create trigger trg_archive_play_entries
before delete on play_entries
for each row execute function archive_deleted_play_entry();

drop trigger if exists trg_archive_play_types on play_types;
create trigger trg_archive_play_types
before delete on play_types
for each row execute function archive_deleted_play_type();

-- 보관함 테이블은 RLS만 켜고 정책은 하나도 안 만듭니다 = anon key로는 아예 접근 불가.
-- (앱은 이 테이블을 쓸 일이 없고, 복구는 항상 SQL Editor에서만 하면 됩니다.)
alter table play_entries_deleted enable row level security;
alter table play_types_deleted enable row level security;

-- 복구가 필요하면 SQL Editor에서 아래처럼 조회/복원하면 됩니다:
--   select * from play_entries_deleted order by deleted_at desc;
--   insert into play_entries (id, entry_date, type, minutes, created_at)
--     select id, entry_date, type, minutes, created_at from play_entries_deleted where id = '복구할-id';
