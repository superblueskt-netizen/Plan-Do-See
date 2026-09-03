# 인증 구현 설명서 — 플랜두씨 다이어리 2 (T07)

> 이 문서의 모든 기록에서 비밀번호·토큰·비밀키는 가려서 적었습니다.
> 심사용으로 쓸 수 있는 진짜 계정의 비밀번호는 이 문서 어디에도 없습니다.

---

## ① 무엇으로 붙였나

**Supabase Auth (GoTrue)** 를 썼습니다. 이메일 + 비밀번호 방식입니다.

| 항목 | 값 |
|---|---|
| 방식 | 인증 서비스(BaaS) 사용 — 직접 구현 아님 |
| 서비스 | Supabase Auth (GoTrue) |
| 클라이언트 라이브러리 | `@supabase/supabase-js` v2 (CDN: `https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js`) |
| 비밀번호 보관 | bcrypt (cost 10) — GoTrue가 처리, 앱 코드는 비밀번호를 보관하지 않음 |
| 사람 알아보는 방법 | JWT 액세스 토큰 (+ 서버 세션 확인) |
| 접근 제어 | PostgreSQL Row Level Security (RLS) |

---

## ② 왜 그걸 골랐나

**고른 이유**: 6번 과제에서 이미 Supabase(Postgres + PostgREST)를 데이터베이스로 쓰고 있었습니다.
Supabase Auth를 쓰면 로그인한 사람의 id가 `auth.uid()` 로 데이터베이스 안에서 바로 쓸 수 있어서,
"남의 자료를 막는 일"을 화면이나 앱 코드가 아니라 **데이터베이스 정책(RLS)** 에서 처리할 수 있습니다.
화면에서 안 보이게 하는 것은 막은 것이 아니기 때문에, 서버가 주인을 확인하게 만드는 쪽을 골랐습니다.
비밀번호를 직접 다루지 않아도 되는 점도 컸습니다.

**함께 검토했지만 고르지 않은 방법**

| 검토한 방법 | 고르지 않은 이유 |
|---|---|
| 직접 구현 (bcrypt + 직접 만든 JWT) | 비밀번호 저장·토큰 서명·만료 처리를 전부 직접 짜야 합니다. 보안에서 제일 틀리기 쉬운 부분을 초보가 처음부터 만드는 셈이라 위험이 이득보다 큽니다. 게다가 이 앱은 서버가 없는 정적 파일 하나라서 비밀키를 둘 곳 자체가 없습니다. |
| Firebase Authentication | 인증은 Firebase, 자료는 Supabase Postgres로 갈라집니다. 그러면 `auth.uid()` 를 RLS에서 쓸 수 없어서 접근 제어를 앱 코드로 다시 짜야 하고, 업체가 둘로 늘어납니다. |
| Auth.js (NextAuth) | Node 서버나 Next.js를 전제로 만들어진 도구입니다. 이 과제물은 빌드도 서버도 없는 HTML 파일 한 개라서 맞지 않습니다. |

---

## ③ 어디를 어떻게 고쳤나

### 흐름별로 소스의 어디를 지나는가

| 흐름 | 소스 위치 | 실제 호출 |
|---|---|---|
| **가입** | `index.html` → `doSignUp(email, password)` | `sb.auth.signUp()` → `POST /auth/v1/signup` |
| **로그인** | `index.html` → `doSignIn(email, password)` | `sb.auth.signInWithPassword()` → `POST /auth/v1/token?grant_type=password` |
| **로그아웃** | `index.html` → `doSignOut()` | `sb.auth.signOut()` → `POST /auth/v1/logout` |
| **자료 조회** | `index.html` → `init()` → `bootAfterLogin()` → `refreshPlans()` / `refreshTodos()` / `computeReview()` | `GET /rest/v1/plans`, `/rest/v1/todos` … (supabase-js가 `Authorization: Bearer …` 를 자동으로 붙임) |

### 고친 내용

**1) 화면을 로그인 뒤로 밀어 넣음** — `index.html`

- `render()` 첫 줄에 `if (!state.session) { renderAuth(); return; }` 를 넣어, 세션이 없으면 계획·할 일·돌아보기·내보내기 화면 자체가 그려지지 않습니다.
- `init()` 은 `sb.auth.getSession()` 으로 세션을 먼저 확인하고, **세션이 없으면 자료를 한 건도 요청하지 않고** 로그인 화면만 그립니다.
- `sb.auth.onAuthStateChange(...)` 로 다른 탭에서 로그아웃하거나 토큰이 끊기면 즉시 로그인 화면으로 되돌립니다.
- 첫 화면 배너 문구를 "로그인한 사람만 자기 기록을 볼 수 있습니다"로 바꿨습니다.

**2) 모든 표에 주인 표시를 붙임** — `migration-t07-auth.sql` [1]

`plans` · `plan_revisions` · `todos` · `execution_records` · `review_feedback` 다섯 표에
`user_id uuid references auth.users(id) on delete cascade default auth.uid()` 를 넣었습니다.
기본값이 `auth.uid()` 라서 앱 코드가 주인을 직접 적어 보내지 않아도 서버가 채웁니다.
(앱이 보낸 `user_id` 를 믿지 않는다는 뜻이기도 합니다 — ④의 확인 5 참고)

**3) 공개 정책을 걷어내고 본인 것만 보이게 함** — `migration-t07-auth.sql` [4] [6]

6번 과제의 `anon_all_*` 정책(`using (true)`)을 전부 지우고, 다음 정책으로 바꿨습니다.

```sql
create policy owner_all_todos on todos for all to authenticated
  using      (auth.uid() = user_id and public.session_is_live())
  with check (auth.uid() = user_id and public.session_is_live());
```

`anon` 롤에는 아무 정책도 남기지 않았습니다. **로그인하지 않으면 어떤 행도 보이지 않습니다.**

**4) 로그아웃을 진짜로 끊음** — `migration-t07-auth.sql` [6]

Supabase 액세스 토큰(JWT)은 서명과 만료만 검사됩니다. 그래서 로그아웃해도 **만료 전까지는 그 토큰이 계속 통했습니다** (직접 확인했습니다 — ④ 확인 3의 "고치기 전" 항목).
토큰 안에는 `session_id` 가 들어 있고, 로그아웃하면 `auth.sessions` 에서 그 행이 지워집니다.
그래서 정책에 "그 세션이 아직 살아 있는가"를 함께 확인하도록 넣었습니다.

```sql
create or replace function public.session_is_live() returns boolean
language sql stable security definer set search_path = auth, public as $$
  select exists (
    select 1 from auth.sessions s
    where s.id = nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'session_id','')::uuid
  );
$$;
```

**5) 거절을 404로 돌려줌** — `migration-t07-auth.sql` [7]

RLS만 쓰면 남의 자료를 건드릴 때 `200 + 빈 배열` 이 돌아옵니다. 막히긴 하지만 "거절당했다"가 드러나지 않습니다.
`security invoker` 함수(함수 안에서도 RLS가 그대로 적용됨) 안에서 대상이 안 보이면 404를 던지게 했습니다.
**"없는 자료"와 "남의 자료"가 똑같이 404** 라서, 남의 자료가 존재하는지 여부조차 알 수 없습니다.

- `get_todo(p_id)` — 한 건 읽기
- `update_todo_owned(p_id, p_patch)` — 한 건 수정
- `delete_todo_owned(p_id)` — 한 건 삭제
- `api_not_found()` — `raise sqlstate 'PGRST'` 로 HTTP 404를 만들어 내는 공통 함수

**6) 계정 삭제** — `migration-t07-auth.sql` [8], `index.html` → `deleteMyAccount()`

`delete_my_account()` 가 `auth.users` 에서 내 행을 지우고, `on delete cascade` 로 내 계획·할 일·실행 기록·회고·규칙 변경이 함께 지워집니다.

---

## ④ 안 열리는 것을 확인한 기록

> 토큰은 `eyJhbGciOiJF…(생략)` 처럼 앞부분만 남겼습니다. 비밀번호 원문은 적지 않았습니다.
> 계정 A = 내 계정(브롱스커피 자료 보유), 계정 B = 격리 확인용 다른 계정.

### 확인 1 — 로그인하지 않고 자료를 직접 요청하면

| | 요청 | 응답 |
|---|---|---|
| 성공 (로그인함) | `GET /rest/v1/todos?select=id,title`<br>`Authorization: Bearer eyJhbGciOiJF…(생략)` | `200` · 2건 (`B 계정 할 일 1`, `B 계정 할 일 2`) |
| **거절 (로그인 안 함)** | `POST /rest/v1/rpc/get_todo`<br>`{"p_id":"cb563a40-…"}` · Authorization 헤더 없음 | `404` `{"code":"404","message":"Not Found","details":"해당 자료가 없거나 내 자료가 아닙니다"}` |
| **거절 (로그인 안 함)** | `GET /rest/v1/todos?select=*` · Authorization 헤더 없음 | `200` · `[]` — 한 건도 안 내려옴 |

화면에서도 로그인 전에는 계획·할 일 화면이 아예 그려지지 않고 로그인 화면만 나옵니다.

### 확인 2 — 비밀번호가 저장된 모습

같은 비밀번호로 계정 두 개를 만들어 저장된 값을 꺼내 봤습니다.

```sql
select email, left(encrypted_password,7) as algo_prefix, length(encrypted_password) as hash_len,
       left(encrypted_password,29) || '...(생략)' as stored_value_masked
from auth.users where email in ('hash.test1@example.com','hash.test2@example.com');
```

| email | algo_prefix | hash_len | stored_value_masked |
|---|---|---|---|
| hash.test1@example.com | `$2a$10$` | 60 | `$2a$10$hy5f5F…(생략)` |
| hash.test2@example.com | `$2a$10$` | 60 | `$2a$10$7uYEA…(생략)` |

- `$2a$` = **bcrypt**, `10` = 비용 인자. 입력한 글자는 어디에도 보이지 않습니다.
- **두 계정의 비밀번호 원문은 완전히 같은데 저장된 값은 서로 다릅니다** (계정마다 소금값이 다름).

```
rows_storing_plaintext = 0     (원문 그대로 저장된 행 없음)
distinct_hashes        = 2     (같은 비밀번호 계정 2개 → 저장값 2가지)
accounts_with_same_password = 2
```

- 가입 응답 본문에 password 필드 자체가 없습니다:
  `["id","aud","role","email","email_confirmed_at","phone","last_sign_in_at","app_metadata","user_metadata","identities","created_at","updated_at","is_anonymous"]`
- 로그인 응답에도 비밀번호는 들어 있지 않습니다 (`access_token`, `refresh_token`, `expires_in`, `user`).

### 확인 3 — 로그아웃 뒤 같은 값으로 다시 요청하면

**같은 주소 · 같은 방식 · 같은 토큰. 달라진 것은 로그아웃 여부뿐입니다.**

| 순서 | 요청 | 응답 |
|---|---|---|
| ① 로그아웃 전 | `POST /rest/v1/rpc/get_todo` · `{"p_id":"be5d6754-…"}` · `Bearer eyJhbGciOiJF…(생략)` | `200` · `{"id":"be5d6754-…","title":"B 계정 할 일 1", …}` |
| ② 로그아웃 | `POST /auth/v1/logout?scope=global` · 같은 토큰 | `204` |
| **③ 로그아웃 뒤, 같은 요청** | `POST /rest/v1/rpc/get_todo` · `{"p_id":"be5d6754-…"}` · **같은** `Bearer eyJhbGciOiJF…(생략)` | **`404`** `{"code":"404","message":"Not Found"}` |

- refresh 토큰 재사용: `POST /auth/v1/token?grant_type=refresh_token` → `400` `{"error_code":"validation_failed","msg":"Refresh token is not valid"}`
- **고치기 전 상태도 적어 둡니다**: `session_is_live()` 를 정책에 넣기 전에는 ③이 `200` 으로 자료가 그대로 내려왔습니다. Supabase 토큰이 무상태이기 때문입니다. 이걸 확인해서 ③-4)의 세션 확인을 넣었습니다.
- 토큰 만료: `expires_in = 3600` (**1시간**). 토큰의 `exp - iat = 3600초`.
- 토큰은 `Authorization` 헤더로만 오갑니다. **주소창(URL)에 실리지 않습니다.**

### 확인 4 — 남의 자료를 읽기·수정·삭제 (양방향)

거절 앞뒤로 반대편 자료 건수를 세었습니다: **A 6건 → 6건, B 2건 → 2건 (변화 없음, 새로 생긴 행 없음)**

| 방향 | 요청 | 응답 |
|---|---|---|
| B → A 읽기 | `POST /rest/v1/rpc/get_todo` `{"p_id":"cb563a40-…"}` · B의 토큰 | `404` Not Found |
| B → A 수정 | `POST /rest/v1/rpc/update_todo_owned` `{"p_id":"cb563a40-…","p_patch":{"title":"B가 몰래 바꾼 제목"}}` · B의 토큰 | `404` Not Found |
| B → A 삭제 | `POST /rest/v1/rpc/delete_todo_owned` `{"p_id":"cb563a40-…"}` · B의 토큰 | `404` Not Found |
| A → B 읽기 | `POST /rest/v1/rpc/get_todo` `{"p_id":"be5d6754-…"}` · A의 토큰 | `404` Not Found |
| A → B 수정 | `POST /rest/v1/rpc/update_todo_owned` `{"p_id":"be5d6754-…","p_patch":{"title":"A가 몰래 바꾼 제목"}}` · A의 토큰 | `404` Not Found |
| A → B 삭제 | `POST /rest/v1/rpc/delete_todo_owned` `{"p_id":"be5d6754-…"}` · A의 토큰 | `404` Not Found |
| **대조군: A가 자기 것 읽기** | `POST /rest/v1/rpc/get_todo` `{"p_id":"cb563a40-…"}` · **A의 토큰** | `200` · `{"title":"별빛 스티커 시안 3개 뽑기", …}` |

같은 요청인데 토큰의 주인만 다릅니다. 주인이면 200, 남이면 404입니다.
"없는 자료"와 "남의 자료"가 똑같이 404라서 자료의 존재 여부도 드러나지 않습니다.

**이 거절을 만드는 소스 위치**
- `migration-t07-auth.sql` [6] — `owner_all_*` RLS 정책 (`auth.uid() = user_id and public.session_is_live()`)
- `migration-t07-auth.sql` [7] — `get_todo` / `update_todo_owned` / `delete_todo_owned` + `api_not_found()`

### 확인 5 — 주소·헤더·본문에 남의 계정을 적어 보내면

B의 토큰으로 로그인한 채, A의 user_id(`668092f9-…`)를 여기저기 적어 보냈습니다.

| 어디에 적었나 | 요청 | 응답 |
|---|---|---|
| **주소(쿼리)** | `GET /rest/v1/todos?select=id,title,user_id&user_id=eq.668092f9-…` · B의 토큰 | `200` · `[]` — A의 자료는 한 건도 안 나옴 |
| **요청 헤더** | `GET /rest/v1/todos?select=id,title,user_id`<br>`x-user-id: 668092f9-…`, `x-supabase-user-id: 668092f9-…` · B의 토큰 | `200` · **B 자기 자료 2건만** (`B 계정 할 일 1`, `B 계정 할 일 2`) |
| **요청 본문** | `POST /rest/v1/todos` `{"plan_id":"3c483eb1-…","title":"본문에 A의 user_id를 적어본 행","user_id":"668092f9-…"}` · B의 토큰 | **`403`** `{"code":"42501","message":"new row violates row-level security policy for table \"todos\""}` |

**목록 응답에 남의 자료가 섞이는지**: `GET /rest/v1/todos?select=id,title,user_id` (B의 토큰)
→ `200` · 2건, **전부 B 소유(`4af21550-…`), 다른 계정 행 0건**.
한 건 조회와 목록 조회가 같은 RLS 정책을 지나기 때문에 목록에도 섞이지 않습니다.

---

## ⑤ AI와 나

**AI에게 맡긴 일**
데이터베이스 마이그레이션 SQL 작성(소유자 컬럼·RLS 정책·404를 돌려주는 함수·계정 삭제 함수),
`index.html` 에 로그인/가입/로그아웃 화면과 세션 게이트를 붙이는 구현,
그리고 위 ④의 확인 요청들을 실제로 보내서 응답을 받아 적는 일.

**내가 직접 판단한 일**
인증을 직접 구현하지 않고 이미 쓰던 Supabase Auth로 가는 것,
그리고 5일 기록의 관찰 지표를 "하루 실제 작업 시간(분)"으로,
3일차 전 규칙 변경을 "하루 할 일 3개 → 1개 + 90분 몰아쓰기"로 정한 것.

**AI 말을 따르지 않은 일**
처음 확인했을 때 남의 자료 요청이 `200 + 빈 배열`로 돌아왔고, "RLS가 막고 있으니 이대로 충분하다"는 설명을 들었습니다.
하지만 그건 *막힌 장면*이 아니라 *아무 일도 없었던 장면*이라, 과제가 요구하는 근거가 되지 않는다고 보고
404를 돌려주는 함수를 따로 만들어 달라고 했습니다.
같은 이유로, 로그아웃 뒤에도 토큰이 통하는 것을 확인하고 나서 "만료가 1시간이라 괜찮다"는 쪽 대신
세션 확인(`session_is_live()`)을 정책에 넣는 쪽을 택했습니다.

---

## ⑥ 아직 못 막은 것

1. **무차별 대입(brute force)을 앱에서 막지 못했습니다.**
   Supabase 쪽 기본 요청 제한 외에, 로그인 실패 횟수 제한이나 계정 잠금, CAPTCHA를 붙이지 않았습니다.
   흔한 비밀번호를 쓰는 계정은 반복 시도로 뚫릴 수 있습니다. 실패가 몇 번 쌓이면 잠기게 하는 것이 다음 순서입니다.

2. **비밀번호 재설정이 없습니다.**
   비밀번호를 잊으면 계정을 되찾을 방법이 없습니다. 반대로 재설정을 붙이면 메일 링크가 새는 순간
   계정이 통째로 넘어가므로, 링크 만료·1회용 처리까지 같이 만들어야 합니다.

3. **두 번째 인증 수단(2단계 인증)이 없습니다.** 비밀번호 하나만 알면 들어올 수 있습니다.

4. **이메일 확인을 껐습니다.**
   과제에서 심사하는 분이 메일함 없이 가입해 볼 수 있게 하려고 껐습니다.
   그래서 **남의 이메일 주소로도 가입이 됩니다.** 실제로 쓸 서비스라면 반드시 켜야 합니다.

5. **액세스 토큰 자체는 여전히 무상태입니다.**
   데이터베이스를 지나는 요청은 `session_is_live()` 로 로그아웃 즉시 끊기게 만들었지만,
   나중에 Storage나 Realtime 같은 다른 경로를 붙이면 그쪽은 이 확인을 지나지 않으므로
   만료 전(최대 1시간)까지 통합니다.

6. **누가 언제 무엇을 했는지 남기는 기록(감사 로그)이 없습니다.**
   지금은 사고가 나도 되짚을 자료가 없습니다.

7. **토큰이 브라우저 저장소에 있습니다.**
   XSS가 하나라도 생기면 토큰을 가져갈 수 있습니다. 지금은 모든 사용자 입력을 `esc()` 로 글자 처리해
   스크립트가 실행되지 않게 막아 두었지만, 저장 방식 자체를 더 안전하게 바꾸지는 못했습니다.

---

## 비밀값 취급

- 브라우저 코드에 들어 있는 키는 **publishable(anon) 키 하나뿐**입니다. 이 키는 RLS로 보호되는 공개용 키라
  노출되어도 남의 자료를 볼 수 없습니다 (④ 확인 1·4·5가 그 근거입니다).
- **service_role 키(비밀키)는 소스·배포 파일·Git 기록 어디에도 없습니다.** 한 번도 코드에 넣은 적이 없습니다.
- JWT 서명에 쓰이는 비밀키는 Supabase 서버 안에만 있고, 앱은 그 값을 알지도 못합니다.
- 이 문서와 제출물의 토큰·해시는 전부 앞부분만 남기고 `…(생략)` 처리했습니다.
