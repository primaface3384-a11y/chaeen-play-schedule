# chaeen-play-schedule

아이(채은이)의 놀이 기록을 부부가 함께 실시간으로 공유하는 캘린더 웹앱.

## 구성
- `index.html` — 실제 앱 전체 (순수 HTML/CSS/JS + Supabase JS 클라이언트, 빌드 과정 없음)
- `schema.sql` — Supabase(Postgres)에 실행하는 테이블/RLS/Realtime/백업트리거 설정 스크립트
- `diag.html` — Supabase 연결 문제 생겼을 때 쓰는 진단 페이지 (아래 "디버깅 노하우" 참고). 필요할 때까지 유지.
- 배포: GitHub Pages (`main` 브랜치 root)에서 정적 호스팅. 별도 빌드/배포 파이프라인 없음 — `main`에 머지되면 자동 배포됨.

## 🛡️ DB 안전 수칙 (절대 지킬 것)

이 앱의 데이터(`play_entries`, `play_types`)는 가족의 실제 추억 기록이라 **되돌릴 수 없는 손실이 생기면 안 됩니다.** 앞으로 이 코드를 수정할 때(Claude든 사람이든) 반드시 지켜야 할 규칙:

1. **`schema.sql`이나 새 마이그레이션에 `DROP TABLE`, `TRUNCATE`, 조건 없는 `DELETE FROM`을 절대 넣지 않는다.** 스키마를 바꿔야 하면 항상 `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` 같은 **추가형(additive)** 변경만 사용한다. 컬럼을 지워야 할 것 같으면, 지우지 말고 그냥 안 쓰는 채로 둔다.
2. **테이블 삭제(delete)는 이미 자동으로 백업된다.** `play_entries`/`play_types`에서 행이 삭제되면 `before delete` 트리거가 자동으로 `play_entries_deleted`/`play_types_deleted` 테이블에 복사해둔다 (RLS로 anon key 접근은 막혀 있고, Supabase SQL Editor에서만 조회 가능). 실수로 뭔가 지워졌으면:
   ```sql
   select * from play_entries_deleted order by deleted_at desc;
   -- 복구:
   insert into play_entries (id, entry_date, type, minutes, created_at)
     select id, entry_date, type, minutes, created_at from play_entries_deleted where id = '복구할-id';
   ```
   새로운 테이블을 추가한다면, 그 테이블에도 같은 패턴(삭제 전 보관함 테이블 + 트리거)을 만들어줄 것.
3. **위험한 SQL을 Supabase SQL Editor에서 실행하기 전에는 항상 앱의 "💾 데이터 백업" 버튼으로 먼저 JSON을 내려받아 둔다.** (또는 SQL Editor에서 `select * from play_entries;` / `select * from play_types;` 결과를 CSV로 export.)
4. **Supabase 무료 플랜 프로젝트는 예고 없이 일시정지(pause)될 수 있다 — 그리고 keepalive 핑으로 확실히 막을 수 없다.** 2026년 8월에 실제로 정지됐는데, 마지막 성공 핑(7/27)에서 **겨우 3일 뒤**였다. 흔히 알려진 "7일 무접속" 기준보다 훨씬 짧으니 핑을 신뢰하지 말 것. 정지되면 프로젝트 서브도메인이 **DNS에서 통째로 사라진다** (`curl` exit code 6 = couldn't resolve host). 데이터는 대시보드에서 Restore하면 그대로 돌아오고, 정지 안내에 적힌 기한(보통 1년 남짓)이 지나면 복구 불가가 된다. → **진짜 안전장치는 `.github/workflows/backup-data.yml`의 자동 암호화 백업이다.** 핑(`keep-supabase-alive.yml`)은 어디까지나 보조 수단.
5. **이 저장소는 공개(public)다 — 데이터를 평문으로 커밋하지 말 것.** 무료 플랜 GitHub Pages가 공개 저장소를 요구해서 어쩔 수 없다. 아이 이름·생년월일·놀이 기록·메모·사진·가족 이메일이 전부 민감 정보이고, 구글 로그인 게이트를 둔 이유 자체가 이걸 감추기 위해서다. 자동 백업은 `BACKUP_PASSPHRASE`로 GPG(AES256) 암호화한 뒤에만 커밋한다. 복호화한 파일을 실수로 커밋하지 않도록 주의 (`_staging/`은 워크플로가 끝나며 지운다).
6. **백업 워크플로는 anon key가 아니라 `SUPABASE_SERVICE_ROLE_KEY`를 쓴다.** RLS의 `is_allowed_user()`가 JWT 이메일을 확인하는데, 워크플로에는 로그인 세션이 없어서 anon key로 REST를 호출하면 **에러 없이 빈 배열(`[]`)** 이 돌아온다 (HTTP 200이라 `curl -sf`도 통과한다 — 예전 keepalive 핑이 "성공"했지만 실제로는 아무것도 못 읽고 있었던 이유). `fetch_backup.py`에는 모든 테이블이 비면 커밋하지 않고 종료하는 가드가 있으니, 키를 잘못 넣어 **멀쩡한 백업을 빈 백업으로 덮어쓰는 사고**는 안 난다.
7. RLS 정책은 이제 구글 로그인 + `allowed_users` 테이블 기반이다 (`is_allowed_user()` 함수로 체크). 새 테이블을 추가할 때 실수로 `using (true)` 같은 완전 개방 정책을 복붙하지 않도록 주의 — 반드시 `is_allowed_user()`를 조건에 넣을 것. `play-photos` Storage 버킷의 select 정책만 예외로 열려있는데, 버킷 자체가 public이라 정책을 걸어도 실질적 의미가 없기 때문 (경로를 모르면 어차피 못 봄).

## 🔐 구글 로그인(OAuth) 설정

이 앱은 Supabase Auth + Google OAuth로 로그인하고, `allowed_users` 테이블에 등록된 이메일만 데이터에 접근할 수 있다 (자세한 SQL은 `schema.sql` 10번 섹션 참고). 이미 설정 완료된 상태지만, Client Secret을 다시 발급하거나 새 환경에서 재설정해야 할 때를 위해 값들을 남겨둔다.

- **Supabase 프로젝트 ref**: `demwtdbnbhkjfztudqjo`
- **Google OAuth의 Authorized redirect URI** (Supabase 콜백 주소, 고정값):
  ```
  https://demwtdbnbhkjfztudqjo.supabase.co/auth/v1/callback
  ```
- **Google OAuth의 Authorized JavaScript origin**:
  ```
  https://primaface3384-a11y.github.io
  ```
- **Google Cloud Console**: [console.cloud.google.com/apis/credentials](https://console.cloud.google.com/apis/credentials) → OAuth 2.0 Client ID는 "Web application" 타입이어야 함. Client ID/Secret은 Supabase 대시보드 → Authentication → Providers → Google 에 등록.
- **접근 허용 이메일 관리**: SQL로 직접 안 건드려도 됨 — 로그인 후 앱 안의 **"👪 접근 관리"** 화면에서 허용된 사용자가 직접 초대/제거 가능 (`allowed_users` 테이블, RLS로 이미 허용된 사용자만 추가/삭제 가능하도록 되어 있음).

### 겪었던 에러: `Unable to exchange external code` (500 error)

구글 로그인 창은 정상적으로 뜨고 로그인도 성공하는데, Supabase로 돌아온 직후 URL에 `?error=server_error&error_code=unexpected_failure&error_description=Unable+to+exchange+external+code...`가 붙으면서 다시 로그인 화면으로 튕기는 증상이 있었다.

- **원인**: 구글 로그인 자체(Google → Supabase 콜백)는 성공했지만, Supabase 서버가 그 인증 코드를 access token으로 교환하는 마지막 단계(Google 토큰 엔드포인트 호출, Client Secret 필요)에서 실패한 것 — 거의 항상 **Supabase 대시보드에 등록된 Client Secret(또는 Client ID)이 복사-붙여넣기 과정에서 손상**됐기 때문 (앞뒤 공백, 줄바꿈이 같이 복사되는 경우가 흔함).
- **해결**: Google Cloud Console → Credentials → 해당 OAuth Client → "ADD SECRET"으로 새 Secret 발급 → **복사 아이콘(📋)으로만 복사** (드래그 선택 금지) → Supabase Providers → Google 설정에서 Client ID/Secret 칸을 **전체 삭제 후 다시 붙여넣기** → Save. 이 방법으로 해결됨.
- 이 프로젝트에서는 이렇게 해결했다: Secret 재발급만으로 해결, OAuth 클라이언트 자체를 새로 만들 필요는 없었음.

## ⚠️ 중요: `supabase`라는 변수명을 쓰지 말 것

`index.html`은 아래 스크립트를 `<head>`에서 불러온다:
```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
```

이 CDN 번들은 `window.supabase`에 클라이언트를 노출시키는 것과 별개로, **전역 스크립트 스코프에 `let`/`const` 수준의 `supabase` 식별자도 선언**한다. 클래식(non-module) `<script>` 태그들은 이런 top-level `let`/`const`/`class` 선언을 페이지 전체가 공유하는 하나의 렉시컬 스코프에 등록하기 때문에, 우리 쪽 인라인 스크립트에서 `let supabase = ...` 같은 걸 다시 선언하면 **`Uncaught SyntaxError: Identifier 'supabase' has already been declared`**가 발생한다.

이건 파싱 단계에서 나는 문법 오류라서 스크립트 전체가 통째로 죽어버린다 — 첫 줄조차 실행되지 않고, 콘솔에도 애매하게만 찍히며, 화면은 그냥 "연결 중..."에 영원히 멈춘 것처럼 보인다 (달력도 안 뜨고, 아무 에러 UI도 안 뜸).

**교훈**: Supabase 클라이언트를 담는 우리 쪽 변수는 반드시 `supabase`가 아닌 다른 이름(현재 코드는 `sb` 사용)을 쓸 것. `window.supabase`(라이브러리 네임스페이스)는 그대로 두고, 우리가 만든 클라이언트 인스턴스만 다른 이름으로.

## 이번에 겪은 디버깅 함정들 (다음에 비슷한 "먹통" 이슈 생기면 참고)

1. **GitHub Pages 캐시가 생각보다 집요하다.** 같은 URL을 반복 요청하면 (쿼리스트링을 새로 붙여도!) Fastly 엣지 캐시가 배포 직후 한동안 옛날 응답을 계속 돌려줄 수 있다. `?v=1` 같은 캐시버스터를 붙였는데도 동일한 증상이 반복되면, 진짜 코드 문제인지 캐시인지 헷갈리기 쉽다. → **가장 확실한 검증 방법은 브라우저 개발자 도구(Console/Network 탭)로 실제 에러 메시지와 실제로 로드된 파일 내용을 직접 보는 것.** 스크린샷으로 증상만 보고 추측하는 것보다 훨씬 빠르다.
2. **로컬 sandbox에서 재현 테스트할 때 CDN이 진짜로 로드되는지 확인할 것.** 이 개발 환경(Claude Code 샌드박스)은 `cdn.jsdelivr.net`, `supabase.co`, `*.github.io` 같은 외부 도메인으로의 아웃바운드 요청이 프록시 정책상 막혀 있다. 그래서 Playwright로 로컬 재현 테스트를 할 때 실제 CDN 스크립트를 못 받아오고, 항상 mock(가짜) 라이브러리를 주입해서 테스트했는데 — mock이 실제 라이브러리의 "전역에 `let supabase` 선언" 같은 미묘한 동작까지 재현하지 않으면 진짜 버그를 못 잡는다. 실제 버그가 여기 해당했다: mock을 쓴 로컬 테스트는 전부 통과했지만 실제 기기에서는 계속 실패했다. → **"모든 걸 개별로는 테스트했는데 왜 통합해서는 안 되지?" 싶으면, mock이 실제 의존성의 미묘한 전역 동작(변수 충돌, 부작용 등)까지 정확히 재현하고 있는지 의심해볼 것.**
3. **화면에 안 보이는 에러는 화면에 로그를 찍어서 확인하라.** 실제 기기의 개발자 콘솔에 접근하기 어려운 상황(모바일, 원격)에서는, 앱 코드에 임시로 타임스탬프 찍힌 온스크린 디버그 로그(`dlog()` 같은 헬퍼로 각 단계마다 로그 남기기)를 추가해서 배포하면 "어디까지 실행됐다가 멈췄는지"를 스크린샷 한 장으로 알 수 있다. 이번 이슈도 이 방법으로 "스크립트 첫 줄도 실행 안 됨 → 문법 오류 의심"까지 좁혔다.
4. **"페이지가 아예 안 열린다"고 하면 프론트가 아니라 백엔드부터 의심할 것.** 2026년 8월 사례: 화면이 완전히 하얗게 떴는데 원인은 Supabase 일시정지였다. 샌드박스에서는 `*.github.io` 아웃바운드가 막혀 있어 실제 페이지를 열어볼 수 없으니, 대신 이 순서로 확인하면 브라우저 없이도 진단된다.
   - `getent hosts <프로젝트ref>.supabase.co` — 안 나오면 프로젝트가 정지/삭제된 것. (대조군으로 `supabase.co`, `github.com`도 같이 찍어서 내 네트워크 문제가 아님을 확인)
   - GitHub Actions의 keepalive 실행 로그 — `curl` exit code 6이면 확정.
   - Pages 배포 워크플로(`dynamic/pages/pages-build-deployment`)의 최신 run이 `success`이고 그 `head_sha`가 `origin/main`과 같으면 **정적 호스팅은 정상**이라는 뜻이니 코드를 건드릴 필요가 없다.
5. **모든 화면이 기본 `display:none`인 구조에서는 초기화가 실패하면 "빈 화면"이 된다.** 예전 부팅 코드는 `sb.auth.onAuthStateChange()` 콜백 안에서만 `showScreen()`을 불렀기 때문에, Supabase에 못 붙으면 아무 화면도 안 켜지고 원인 파악이 불가능했다. 지금은 부팅 시 `probeBackend()`가 별도로 연결을 확인해서 실패하면 `#connErrorScreen`(재시도 버튼 포함)을 띄운다. **새 화면/분기를 추가할 때 "이 경로로 오면 아무것도 안 보이는 상태"가 생기지 않는지 항상 확인할 것.**
