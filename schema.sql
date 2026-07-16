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

-- ============================================================
-- 7) 놀이 종류별 고유 색상 + 놀이 기록 메모 (추가 컬럼만, 기존 데이터는 안전)
-- ============================================================
alter table play_types add column if not exists color text;
alter table play_entries add column if not exists memo text;

-- 기본 8개 놀이 종류는 색이 비어있으면 원래 팔레트 순서대로 배정.
-- (그 외 커스텀으로 추가된 놀이 종류 중 색이 비어있는 게 있으면, 앱이 처음 불러올 때
-- 자동으로 겹치지 않는 색을 배정해서 다시 저장해줍니다 — 별도 SQL 조치 필요 없음.)
update play_types set color = case name
  when '블록놀이' then '#FF8A70'
  when '그림그리기' then '#FFC94A'
  when '책읽기' then '#4FB0E8'
  when '소꿉놀이' then '#6BC79E'
  when '야외놀이' then '#B18FE0'
  when '노래율동' then '#F786B0'
  when '퍼즐' then '#F2A65A'
  when '물놀이' then '#7FC8C4'
  else color
end
where color is null;

-- 보관함 테이블에도 같은 컬럼 추가 (삭제된 놀이의 색/메모도 그대로 보관)
alter table play_types_deleted add column if not exists color text;
alter table play_entries_deleted add column if not exists memo text;

-- security definer: 보관함 테이블은 anon 키로 직접 select/insert가 막혀 있는데(RLS,
-- 정책 없음), 트리거 함수가 일반 권한(호출자 권한)으로 실행되면 자기 자신도 그 테이블에
-- 못 쓰는 모순이 생겨서 delete 자체가 실패합니다. security definer로 만들어서
-- "함수를 만든 소유자(관리자) 권한"으로 실행되게 하여 이 문제를 해결합니다.
create or replace function archive_deleted_play_entry()
returns trigger as $$
begin
  insert into play_entries_deleted (id, entry_date, type, minutes, memo, created_at)
  values (old.id, old.entry_date, old.type, old.minutes, old.memo, old.created_at);
  return old;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function archive_deleted_play_type()
returns trigger as $$
begin
  insert into play_types_deleted (id, name, sort_order, color, created_at)
  values (old.id, old.name, old.sort_order, old.color, old.created_at);
  return old;
end;
$$ language plpgsql security definer set search_path = public;

-- unique index를 걸기 전에, 이미 같은 색으로 저장된 놀이 종류가 있으면
-- (앱의 예전 버그로 생겼을 수 있음) 하나만 남기고 나머지는 색을 비워둡니다.
-- 비워진 색은 앱을 다음에 열 때 자동으로 안 겹치는 새 색으로 채워집니다.
with ranked as (
  select id, color, row_number() over (partition by color order by created_at asc) as rn
  from play_types
  where color is not null
)
update play_types
set color = null
where id in (select id from ranked where rn > 1);

-- 놀이 종류 색상은 이제 DB 차원에서 절대 겹치지 않도록 unique index로 강제합니다.
create unique index if not exists play_types_color_key on play_types (color) where color is not null;

-- ============================================================
-- 9) 놀이 기록에 사진 첨부 (추가 컬럼 + Storage 버킷)
-- ============================================================
alter table play_entries add column if not exists photo_path text;
alter table play_entries_deleted add column if not exists photo_path text;

-- 놀이 기록이 삭제돼도(또는 사진이 다른 걸로 교체돼도) Storage의 사진 파일 자체는
-- 지우지 않습니다 — play_entries_deleted에 photo_path가 그대로 보관되니, 행을
-- 복구하면 사진도 다시 연결됩니다. (다른 안전장치들과 같은 "지우지 않는다" 원칙.)
create or replace function archive_deleted_play_entry()
returns trigger as $$
begin
  insert into play_entries_deleted (id, entry_date, type, minutes, memo, photo_path, created_at)
  values (old.id, old.entry_date, old.type, old.minutes, old.memo, old.photo_path, old.created_at);
  return old;
end;
$$ language plpgsql security definer set search_path = public;

-- 사진을 저장할 공개 Storage 버킷. 가족만 아는 anon key로 쓰는 개인용 도구라
-- 다른 테이블들과 똑같이 anon key로 업로드/조회/삭제를 모두 허용합니다.
insert into storage.buckets (id, name, public)
values ('play-photos', 'play-photos', true)
on conflict (id) do nothing;

drop policy if exists "anyone can upload play photos" on storage.objects;
create policy "anyone can upload play photos" on storage.objects
  for insert with check (bucket_id = 'play-photos');

drop policy if exists "anyone can view play photos" on storage.objects;
create policy "anyone can view play photos" on storage.objects
  for select using (bucket_id = 'play-photos');

drop policy if exists "anyone can delete play photos" on storage.objects;
create policy "anyone can delete play photos" on storage.objects
  for delete using (bucket_id = 'play-photos');
