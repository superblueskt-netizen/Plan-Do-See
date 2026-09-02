-- 플랜두씨 다이어리 1 (T06) — Supabase 스키마
-- 실행 방법: Supabase 대시보드 → SQL Editor → 새 쿼리 → 이 파일 전체 붙여넣기 → Run
--
-- 날짜/시간 규칙:
--   * 모든 timestamptz 컬럼은 UTC로 저장됩니다 (Postgres 기본 동작).
--   * "지연" 판정 등 화면에 보여줄 때는 Asia/Seoul(UTC+9) 기준으로 환산해서 비교/표시합니다.
--   * deadline(마감일)은 시간 없는 date 컬럼이며, 사용자가 서울 시간 기준으로 고른 날짜를 그대로 저장합니다.

create extension if not exists pgcrypto;

-- 1) 계획 (Plan) ----------------------------------------------------------
create table if not exists plans (
id uuid primary key default gen_random_uuid(),
title text not null,
period_start date not null,
period_end date not null,
priority text not null check (priority in ('high','medium','low')),
success_criteria text not null,
estimated_hours numeric not null check (estimated_hours >= 0),
carried_note text,
deleted_at timestamptz,
created_at timestamptz not null default now(),
updated_at timestamptz not null default now()
);

-- 계획 수정 이력: 수정 "전" 값을 스냅샷으로 남긴다 (계획 ID는 그대로, 최신 값만 plans에 남음)
create table if not exists plan_revisions (
id uuid primary key default gen_random_uuid(),
plan_id uuid not null references plans(id) on delete cascade,
title text not null,
period_start date not null,
period_end date not null,
priority text not null,
success_criteria text not null,
estimated_hours numeric not null,
revised_at timestamptz not null default now()
);

-- plans 테이블이 UPDATE 되기 "직전" 값을 자동으로 plan_revisions에 적재하는 트리거
create or replace function fn_snapshot_plan_before_update()
returns trigger as $$
begin
insert into plan_revisions
(plan_id, title, period_start, period_end, priority, success_criteria, estimated_hours, revised_at)
values
(old.id, old.title, old.period_start, old.period_end, old.priority, old.success_criteria, old.estimated_hours, now());
new.updated_at := now();
return new;
end;
$$ language plpgsql;

drop trigger if exists trg_snapshot_plan_before_update on plans;
create trigger trg_snapshot_plan_before_update
before update on plans
for each row
when (
old.title is distinct from new.title or
old.period_start is distinct from new.period_start or
old.period_end is distinct from new.period_end or
old.priority is distinct from new.priority or
old.success_criteria is distinct from new.success_criteria or
old.estimated_hours is distinct from new.estimated_hours
)
execute function fn_snapshot_plan_before_update();

-- 2) 할 일 (Todo) ----------------------------------------------------------
create table if not exists todos (
id uuid primary key default gen_random_uuid(),
plan_id uuid not null references plans(id) on delete cascade,
title text not null,
deadline date,
priority text check (priority in ('high','medium','low')),
tags text[] not null default '{}',
estimated_minutes integer not null default 0 check (estimated_minutes >= 0),
status text not null default 'in_progress' check (status in ('in_progress','done')),
completed_at timestamptz,
deleted_at timestamptz,
created_at timestamptz not null default now(),
updated_at timestamptz not null default now()
);

create index if not exists idx_todos_plan_id on todos(plan_id);
create index if not exists idx_todos_status on todos(status);
create index if not exists idx_todos_deadline on todos(deadline);

-- 3) 실행 기록 (Execution record) -------------------------------------------
-- kind='session'    : 실제로 일한 시작/종료/걸린 시간/막힌 이유 기록 (여러 건 가능)
-- kind='completion'  : "완료" 처리 이벤트 1건 (todos.status 조건부 UPDATE가 실제로 바뀐 경우에만 클라이언트가 삽입)
create table if not exists execution_records (
id uuid primary key default gen_random_uuid(),
todo_id uuid not null references todos(id) on delete cascade,
kind text not null check (kind in ('session','completion')),
started_at timestamptz,
ended_at timestamptz,
actual_minutes integer check (actual_minutes >= 0),
blocker_reason text,
created_at timestamptz not null default now()
);

create index if not exists idx_exec_todo_id on execution_records(todo_id);
create index if not exists idx_exec_kind on execution_records(kind);

-- 4) 돌아보기 피드백 (다음 계획으로 넘길 한 줄) -------------------------------
create table if not exists review_feedback (
id uuid primary key default gen_random_uuid(),
plan_id uuid references plans(id) on delete set null,
note text not null,
consumed_at timestamptz,
created_at timestamptz not null default now()
);

-- RLS: 이번 과제는 로그인이 없으므로(링크를 아는 사람은 누구나 읽고/쓸 수 있음), 모든 테이블을 공개로 둔다.
-- 잠그는 작업은 7번 과제에서 진행한다.
alter table plans enable row level security;
alter table plan_revisions enable row level security;
alter table todos enable row level security;
alter table execution_records enable row level security;
alter table review_feedback enable row level security;

drop policy if exists anon_all_plans on plans;
create policy anon_all_plans on plans for all using (true) with check (true);

drop policy if exists anon_all_plan_revisions on plan_revisions;
create policy anon_all_plan_revisions on plan_revisions for all using (true) with check (true);

drop policy if exists anon_all_todos on todos;
create policy anon_all_todos on todos for all using (true) with check (true);

drop policy if exists anon_all_execution_records on execution_records;
create policy anon_all_execution_records on execution_records for all using (true) with check (true);

drop policy if exists anon_all_review_feedback on review_feedback;
create policy anon_all_review_feedback on review_feedback for all using (true) with check (true);

