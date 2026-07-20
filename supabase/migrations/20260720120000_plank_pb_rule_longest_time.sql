-- Plank PB rule: longer hold at the same load counts as a PB.
update public.exercises
set pb_rule = 'heaviestWeightThenLongestTime'
where id = '00000000-0000-0000-0000-000000000017';
