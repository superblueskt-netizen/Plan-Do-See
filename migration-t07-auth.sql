-- 플랜두씨 다이어리 2 (T07) — 인증 붙이기 마이그레이션 (실제 실행한 내용)
-- 실행 순서: 1) 이 파일의 [1]~[4] 실행 → 2) 가입해서 내 계정 UID 확보
--            → 3) [5] 이관 UPDATE 실행 → 4) [6] 정책을 세션 확인까지 포함하도록 교체

-- =====================================================================
-- [1] 각 테이블에 소유자 컬럼 추가
-- =====================================================================
alter table plans             add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table plan_revisions    add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table todos             add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table execution_records add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table review_feedback   add column if not exists user_id uuid references auth.users(id) on delete cascade;

alter table plans             alter column user_id set default auth.uid();
alter table plan_revisions    alter column user_id set default auth.uid();
alter table todos             alter column user_id set default auth.uid();
alter table execution_records alter column user_id set default auth.uid();
alter table review_feedback   alter column user_id set default auth.uid();

create index if not exists idx_plans_user_id            on plans(user_id);
create index if not exists idx_plan_revisions_user_id   on plan_revisions(user_id);
create index if not exists idx_todos_user_id            on todos(user_id);
create index if not exists idx_execution_records_user_id on execution_records(user_id);
create index if not exists idx_review_feedback_user_id  on review_feedback(user_id);

-- =====================================================================
-- [2] 수정 이력 트리거가 소유자도 함께 복사하도록 교체
-- =====================================================================
create or replace function fn_snapshot_plan_before_update()
returns trigger as $$
begin
  insert into plan_revisions
    (plan_id, user_id, title, period_start, period_end, priority, success_criteria, estimated_hours, revised_at)
  values
    (old.id, old.user_id, old.title, old.period_start, old.period_end, old.priority, old.success_criteria, old.estimated_hours, now());
  new.updated_at := now();
  return new;
end;
$$ language plpgsql;

-- =====================================================================
-- [3] 계획 규칙 변경 기록 테이블 (2일차 뒤 · 3일차 앞에 1건)
-- =====================================================================
create table if not exists plan_rule_changes (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade default auth.uid(),
  metric          text not null,
  metric_unit     text not null,
  before_value    text not null,
  after_value     text not null,
  reason          text not null,
  before_ref_date date not null,
  after_ref_date  date not null,
  changed_at      timestamptz not null default now(),
  created_at      timestamptz not null default now()
);
create index if not exists idx_prc_user_id on plan_rule_changes(user_id);
alter table plan_rule_changes enable row level security;

-- =====================================================================
-- [4] anon 공개 정책 제거 → 로그인한 본인 것만 (1차)
-- =====================================================================
alter table plans             force row level security;
alter table plan_revisions    force row level security;
alter table todos             force row level security;
alter table execution_records force row level security;
alter table review_feedback   force row level security;
alter table plan_rule_changes force row level security;

drop policy if exists anon_all_plans             on plans;
drop policy if exists anon_all_plan_revisions    on plan_revisions;
drop policy if exists anon_all_todos             on todos;
drop policy if exists anon_all_execution_records on execution_records;
drop policy if exists anon_all_review_feedback   on review_feedback;
-- anon 롤에는 어떤 정책도 남기지 않는다 = 로그인 전에는 아무 행도 보이지 않음

-- =====================================================================
-- [5] 기존 T06 자료를 내 계정으로 이관한 뒤 NOT NULL 로 잠금
--     '<MY_UID>' 는 Authentication → Users 에서 확인한 실제 UID
-- =====================================================================
-- update plans             set user_id = '<MY_UID>' where user_id is null;
-- update plan_revisions    set user_id = '<MY_UID>' where user_id is null;
-- update todos             set user_id = '<MY_UID>' where user_id is null;
-- update execution_records set user_id = '<MY_UID>' where user_id is null;
-- update review_feedback   set user_id = '<MY_UID>' where user_id is null;
alter table plans             alter column user_id set not null;
alter table plan_revisions    alter column user_id set not null;
alter table todos             alter column user_id set not null;
alter table execution_records alter column user_id set not null;
alter table review_feedback   alter column user_id set not null;

-- =====================================================================
-- [6] 로그아웃을 진짜로 끊기 위한 "세션이 아직 살아있는가" 확인
--     Supabase 액세스 토큰(JWT)은 서명과 만료만 검사되므로, 로그아웃해도
--     만료 전까지는 그 토큰이 계속 통한다. 그래서 토큰 안의 session_id 가
--     auth.sessions 에 아직 남아 있는지를 정책에서 함께 확인한다.
--     로그아웃(scope=global)하면 그 행이 지워지므로 즉시 거절된다.
-- =====================================================================
create or replace function public.session_is_live() returns boolean
language sql stable security definer set search_path = auth, public as $$
  select exists (
    select 1 from auth.sessions s
    where s.id = nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'session_id','')::uuid
  );
$$;
grant execute on function public.session_is_live() to authenticated;

drop policy if exists owner_all_plans on plans;
create policy owner_all_plans on plans for all to authenticated
  using (auth.uid() = user_id and public.session_is_live())
  with check (auth.uid() = user_id and public.session_is_live());

drop policy if exists owner_all_plan_revisions on plan_revisions;
create policy owner_all_plan_revisions on plan_revisions for all to authenticated
  using (auth.uid() = user_id and public.session_is_live())
  with check (auth.uid() = user_id and public.session_is_live());

drop policy if exists owner_all_todos on todos;
create policy owner_all_todos on todos for all to authenticated
  using (auth.uid() = user_id and public.session_is_live())
  with check (auth.uid() = user_id and public.session_is_live());

drop policy if exists owner_all_execution_records on execution_records;
create policy owner_all_execution_records on execution_records for all to authenticated
  using (auth.uid() = user_id and public.session_is_live())
  with check (auth.uid() = user_id and public.session_is_live());

drop policy if exists owner_all_review_feedback on review_feedback;
create policy owner_all_review_feedback on review_feedback for all to authenticated
  using (auth.uid() = user_id and public.session_is_live())
  with check (auth.uid() = user_id and public.session_is_live());

drop policy if exists owner_all_plan_rule_changes on plan_rule_changes;
create policy owner_all_plan_rule_changes on plan_rule_changes for all to authenticated
  using (auth.uid() = user_id and public.session_is_live())
  with check (auth.uid() = user_id and public.session_is_live());

-- =====================================================================
-- [7] 거절을 404로 돌려주는 창구
--     PostgREST 는 RLS 로 걸러진 요청에 200 + 빈 배열을 돌려준다.
--     "없는 것"과 "남의 것"을 구분할 수 없게 404로 통일한다.
--     security invoker 이므로 함수 안에서도 RLS가 그대로 적용된다.
-- =====================================================================
create or replace function api_not_found() returns void language plpgsql as $$
begin
  raise sqlstate 'PGRST' using
    message = json_build_object('code','404','message','Not Found','details','해당 자료가 없거나 내 자료가 아닙니다','hint',null)::text,
    detail  = json_build_object('status',404,'headers',json_build_object())::text;
end;
$$;

create or replace function get_todo(p_id uuid) returns todos language plpgsql security invoker as $$
declare t todos;
begin
  select * into t from todos where id = p_id and deleted_at is null;
  if not found then perform api_not_found(); end if;
  return t;
end;
$$;

create or replace function update_todo_owned(p_id uuid, p_patch jsonb) returns todos language plpgsql security invoker as $$
declare t todos;
begin
  update todos set
    title             = coalesce(p_patch->>'title', title),
    deadline          = coalesce((p_patch->>'deadline')::date, deadline),
    priority          = coalesce(p_patch->>'priority', priority),
    estimated_minutes = coalesce((p_patch->>'estimated_minutes')::int, estimated_minutes),
    updated_at        = now()
  where id = p_id and deleted_at is null
  returning * into t;
  if not found then perform api_not_found(); end if;
  return t;
end;
$$;

create or replace function delete_todo_owned(p_id uuid) returns todos language plpgsql security invoker as $$
declare t todos;
begin
  update todos set deleted_at = now() where id = p_id and deleted_at is null returning * into t;
  if not found then perform api_not_found(); end if;
  return t;
end;
$$;

revoke all on function get_todo(uuid)                  from anon;
revoke all on function update_todo_owned(uuid, jsonb)  from anon;
revoke all on function delete_todo_owned(uuid)         from anon;
grant execute on function get_todo(uuid)                 to authenticated;
grant execute on function update_todo_owned(uuid, jsonb) to authenticated;
grant execute on function delete_todo_owned(uuid)        to authenticated;

-- =====================================================================
-- [8] 계정 삭제 (내 계정과 내 자료를 함께 지운다)
--     user_id 가 전부 on delete cascade 이므로 auth.users 한 행을 지우면
--     그 계정의 계획·할 일·실행 기록·회고·규칙 변경이 함께 지워진다.
-- =====================================================================
create or replace function delete_my_account() returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;
revoke all on function delete_my_account() from public;
revoke all on function delete_my_account() from anon;
grant execute on function delete_my_account() to authenticated;
