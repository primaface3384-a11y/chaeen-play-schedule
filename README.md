# 채은이 놀이 스케줄러 — 실시간 공유 버전

부부가 각자 폰에서 열어도 실시간으로 같은 기록을 보고 편집할 수 있는 버전이에요.
백엔드는 Supabase(무료), 호스팅은 GitHub Pages(무료)를 사용합니다.

---

## 1. Supabase 프로젝트 만들기 (5분)

1. https://supabase.com 접속 → 무료 회원가입/로그인
2. "New Project" 클릭
   - 이름: `chaeeun-scheduler` (아무 이름이나 OK)
   - 데이터베이스 비밀번호: 아무거나 설정 (기억 안 해도 됨, 나중에 안 씀)
   - Region: `Northeast Asia (Seoul)` 선택하면 속도가 가장 빨라요
3. 프로젝트 생성 완료까지 1~2분 대기

## 2. 테이블 만들기

1. 왼쪽 메뉴에서 **SQL Editor** 클릭
2. "New query" 클릭
3. 이 폴더의 `schema.sql` 파일 내용을 전체 복사해서 붙여넣기
4. 우측 하단 **Run** 클릭
5. "Success. No rows returned" 같은 메시지가 뜨면 완료

확인: 왼쪽 메뉴 **Table Editor** 에서 `play_entries`, `play_types` 두 테이블이 보이고,
`play_types`에 블록놀이/그림그리기 등 8개 기본 항목이 이미 들어있으면 성공이에요.

## 3. 연결 정보(URL, anon key) 확인하기

1. 왼쪽 메뉴 톱니바퀴 아이콘 → **Project Settings** → **API**
2. 아래 두 값을 복사해두세요:
   - **Project URL** (예: `https://xxxxxxxxxxxx.supabase.co`)
   - **anon public** key (긴 문자열)

⚠️ `service_role` key는 절대 사용하지 마세요 — 그건 서버 전용 비밀 키예요.
`anon public` key는 브라우저 코드에 넣어도 되는 공개용 키입니다.

## 4. index.html에 연결 정보 넣기

`index.html` 파일을 열어서 `<script>` 태그 맨 위쪽, 이 부분을 찾으세요:

```js
const SUPABASE_URL = 'YOUR_SUPABASE_URL';
const SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';
```

방금 복사한 값으로 바꿔주세요:

```js
const SUPABASE_URL = 'https://xxxxxxxxxxxx.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJI...(긴 문자열)';
```

Claude Code에서 이 작업을 요청하면 자동으로 해줄 수 있어요. 예:
> "index.html의 SUPABASE_URL을 https://xxxx.supabase.co로, SUPABASE_ANON_KEY를 eyJ...로 바꿔줘"

## 5. GitHub 레포에 올리고 GitHub Pages로 배포

Claude Code에서 아래처럼 요청하면 됩니다:

> "이 폴더를 새 GitHub 레포로 만들고, GitHub Pages로 배포해줘"

수동으로 하실 경우:
```bash
git init
git add .
git commit -m "채은이 놀이 스케줄러 - 실시간 공유 버전"
git branch -M main
git remote add origin https://github.com/<본인계정>/chaeeun-scheduler.git
git push -u origin main
```
그 다음 GitHub 레포 → Settings → Pages → Source를 `main` 브랜치, `/ (root)` 로 설정하면
`https://<본인계정>.github.io/chaeeun-scheduler/` 에서 접속 가능해져요. (반영까지 1~2분 소요)

## 6. 테스트

1. 배포된 링크를 본인 폰에서 열고 놀이 하나 추가
2. 같은 링크를 와이프분 폰에서 열어서 방금 추가한 기록이 보이는지 확인
3. 와이프분이 하나 추가하면, 본인 화면이 몇 초 안에 자동으로 업데이트되는지 확인
   (화면 상단 "실시간 연결됨" 표시가 초록 점이면 정상 연결 상태예요)

---

## 파일 구성

- `index.html` — 실제 웹앱 (이것만 GitHub Pages로 배포하면 됨)
- `schema.sql` — Supabase에 한 번 실행할 테이블 생성 스크립트
- `README.md` — 이 안내 문서

## 참고사항

- **보안**: `anon key`는 공개 저장소에 올라가도 되는 키지만, 이 키를 아는 사람은 누구나
  데이터를 읽고 쓸 수 있어요 (RLS 정책을 "모두 허용"으로 열어뒀기 때문). 가족 전용으로
  조용히 쓰는 용도로는 충분하지만, 레포를 공개로 만드실 경우 이 점 참고해주세요.
  더 강한 보안이 필요하면 나중에 Supabase Auth(로그인)를 추가할 수 있어요.
- **무료 한도**: Supabase 무료 티어는 500MB 저장공간, 넉넉한 API 요청 한도를 제공해서
  이런 개인용 기록 앱에는 충분해요.
- **오프라인**: 인터넷이 끊기면 저장/불러오기가 안 돼요 (상단에 "연결 끊김" 표시). 다시
  연결되면 자동으로 복구됩니다.
