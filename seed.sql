-- 플랜두씨 다이어리 1 (T06) — 초기 데이터(내 실제 계획)
-- supabase-schema.sql을 먼저 실행한 뒤, 이 파일을 SQL Editor에서 한 번만 실행하세요.
-- 여기 들어간 내용은 예시가 아니라 실제로 진행 중인 "브롱스커피 브랜딩 프로젝트 재개" 계획입니다.
-- ⚠️ 실제 상황과 다른 부분(기간, 항목, 시간)은 앱의 '수정' 기능으로 직접 고쳐서 본인 것으로 채우세요.

do $$
declare
v_plan_id uuid;
v_todo1 uuid; v_todo2 uuid; v_todo3 uuid; v_todo4 uuid; v_todo5 uuid; v_todo6 uuid;
begin
insert into plans (title, period_start, period_end, priority, success_criteria, estimated_hours)
values (
'브롱스커피 브랜딩 프로젝트 재개',
current_date, current_date + interval '28 days',
'high',
'별빛 스티커 시안 1개 확정 + 드립백 목업 1개 제작 + 사촌에게 컨펌 받기',
20
)
returning id into v_plan_id;

insert into todos (plan_id, title, deadline, priority, tags, estimated_minutes, status)
values (v_plan_id, '지난 브랜딩 자료 다시 검토하기', current_date + 2, 'high', array['리서치'], 60, 'in_progress')
returning id into v_todo1;

insert into todos (plan_id, title, deadline, priority, tags, estimated_minutes, status)
values (v_plan_id, '별빛 스티커 시안 3개 뽑기', current_date + 5, 'high', array['디자인','별빛'], 180, 'in_progress')
returning id into v_todo2;

insert into todos (plan_id, title, deadline, priority, tags, estimated_minutes, status)
values (v_plan_id, '인트로 웹사이트 문구 초안 작성', current_date + 7, 'high', array['웹사이트','카피'], 120, 'in_progress')
returning id into v_todo3;

insert into todos (plan_id, title, deadline, priority, tags, estimated_minutes, status)
values (v_plan_id, '드립백 목업 제작', current_date + 10, 'medium', array['패키징'], 240, 'in_progress')
returning id into v_todo4;

insert into todos (plan_id, title, deadline, priority, tags, estimated_minutes, status)
values (v_plan_id, '원두백 목업 색상 확정', current_date + 12, 'medium', array['패키징'], 90, 'in_progress')
returning id into v_todo5;

insert into todos (plan_id, title, deadline, priority, tags, estimated_minutes, status)
values (v_plan_id, '사촌에게 시안 컨펌 받기', current_date + 14, 'low', array['커뮤니케이션'], 30, 'in_progress')
returning id into v_todo6;

-- 실제로 한 일 기록 (3건 이상)
insert into execution_records (todo_id, kind, started_at, ended_at, actual_minutes, blocker_reason)
values (v_todo1, 'session', now() - interval '1 day 4 hours', now() - interval '1 day 3 hours', 60, null);

insert into execution_records (todo_id, kind, started_at, ended_at, actual_minutes, blocker_reason)
values (v_todo2, 'session', now() - interval '20 hours', now() - interval '18 hours 30 minutes', 90, '폰트 라이선스 확인하다 막힘');

insert into execution_records (todo_id, kind, started_at, ended_at, actual_minutes, blocker_reason)
values (v_todo3, 'session', now() - interval '2 days 5 hours', now() - interval '2 days 4 hours', 60, '카피 방향이 안 잡힘');

insert into execution_records (todo_id, kind, started_at, ended_at, actual_minutes, blocker_reason)
values (v_todo4, 'session', now() - interval '10 hours', now() - interval '9 hours', 60, null);

-- todo1(지난 자료 검토)은 완료 처리: 조건부 UPDATE + completion 기록을 앱 로직과 동일하게 재현
update todos set status='done', completed_at=now() - interval '1 day 3 hours', updated_at=now()
where id=v_todo1 and status<>'done';

insert into execution_records (todo_id, kind, ended_at)
values (v_todo1, 'completion', now() - interval '1 day 3 hours');

end $$;

