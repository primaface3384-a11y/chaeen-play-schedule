-- 채은이 놀이 스케줄러 — Supabase 테이블 스키마
-- Supabase 프로젝트 대시보드 → SQL Editor 에서 이 전체를 붙여넣고 실행하세요.

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
