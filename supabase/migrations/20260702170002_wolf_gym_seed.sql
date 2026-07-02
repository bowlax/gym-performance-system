-- Wolf gym and exercise seed data
-- Gym UUID matches the hosted Supabase project (applied via SQL editor before migrations existed).
-- Exercise UUIDs and display_order match src/resources/local-store/ExerciseSeedData.swift.

insert into gyms (id, teamup_provider_id, name)
values (
    '0abc9301-b048-40f5-8bdc-9bb389916b59',
    '5404319',
    'Way of Life Fitness'
)
on conflict (id) do nothing;

insert into exercises (
    id,
    gym_id,
    name,
    category,
    measurement_type,
    pb_rule,
    target_reps,
    minimum_reps,
    parent_exercise_id,
    display_order,
    is_active
) values
    ('00000000-0000-0000-0000-000000000001', '0abc9301-b048-40f5-8bdc-9bb389916b59', 'Overhead Press',           'pbExercise', 'weightAndReps', 'heaviestWeightAtReps', 5,    null, null,                                       1,  true),
    ('00000000-0000-0000-0000-000000000019', '0abc9301-b048-40f5-8bdc-9bb389916b59', 'Bike 60s',                 'pbExercise', 'distanceOnly',  'longestDistance',      null, null, null,                                       2,  true),
    ('00000000-0000-0000-0000-000000000002', '0abc9301-b048-40f5-8bdc-9bb389916b59', 'Free Squat',               'pbExercise', 'weightAndReps', 'heaviestWeightAtReps', 5,    null, null,                                       3,  true),
    ('00000000-0000-0000-0000-000000000003', '0abc9301-b048-40f5-8bdc-9bb389916b59', 'Box Squat',                'pbExercise', 'weightAndReps', 'heaviestWeightAtReps', 5,    null, '00000000-0000-0000-0000-000000000002', 4,  true),
    ('00000000-0000-0000-0000-000000000008', '0abc9301-b048-40f5-8bdc-9bb389916b59', '45-Degree Dumbbell Press', 'pbExercise', 'weightAndReps', 'bestWeightAndReps',    null, null, null,                                       5,  true),
    ('00000000-0000-0000-0000-000000000004', '0abc9301-b048-40f5-8bdc-9bb389916b59', 'Bench Press 3x5',          'pbExercise', 'weightAndReps', 'heaviestWeightAtReps', 5,    null, null,                                       6,  true),
    ('00000000-0000-0000-0000-000000000005', '0abc9301-b048-40f5-8bdc-9bb389916b59', 'Bench Press 1x5',          'pbExercise', 'weightAndReps', 'heaviestWeightAtReps', 5,    null, '00000000-0000-0000-0000-000000000004', 7,  true),
    ('00000000-0000-0000-0000-000000000006', '0abc9301-b048-40f5-8bdc-9bb389916b59', 'Straight Bar Deadlift',    'pbExercise', 'weightAndReps', 'heaviestWeightAtReps', 5,    null, null,                                       8,  true),
    ('00000000-0000-0000-0000-000000000007', '0abc9301-b048-40f5-8bdc-9bb389916b59', 'Trap Bar Deadlift',        'pbExercise', 'weightAndReps', 'heaviestWeightAtReps', 5,    null, '00000000-0000-0000-0000-000000000006', 9,  true),
    ('00000000-0000-0000-0000-000000000009', '0abc9301-b048-40f5-8bdc-9bb389916b59', 'Flat Dumbbell Press',      'pbExercise', 'weightAndReps', 'bestWeightAndReps',    null, null, null,                                       10, true),
    ('00000000-0000-0000-0000-000000000010', '0abc9301-b048-40f5-8bdc-9bb389916b59', 'Chest Dumbbell Row',       'pbExercise', 'weightAndReps', 'bestWeightAndReps',    null, null, null,                                       11, true),
    ('00000000-0000-0000-0000-000000000011', '0abc9301-b048-40f5-8bdc-9bb389916b59', 'Split Squat Dumbbell',     'pbExercise', 'weightAndReps', 'bestWeightAndReps',    null, null, null,                                       12, true),
    ('00000000-0000-0000-0000-000000000016', '0abc9301-b048-40f5-8bdc-9bb389916b59', 'Chin-ups',                 'pbExercise', 'repsOnly',      'mostReps',             null, null, null,                                       13, true),
    ('00000000-0000-0000-0000-000000000015', '0abc9301-b048-40f5-8bdc-9bb389916b59', 'Cable Row',                'pbExercise', 'weightAndReps', 'bestWeightAndReps',    null, null, null,                                       14, true),
    ('00000000-0000-0000-0000-000000000012', '0abc9301-b048-40f5-8bdc-9bb389916b59', 'One Arm Dumbbell Row',     'pbExercise', 'weightAndReps', 'bestWeightAndReps',    null, null, null,                                       15, true),
    ('00000000-0000-0000-0000-000000000013', '0abc9301-b048-40f5-8bdc-9bb389916b59', 'Push-ups',                 'pbExercise', 'weightAndReps', 'bestWeightAndReps',    null, null, null,                                       16, true),
    ('00000000-0000-0000-0000-000000000018', '0abc9301-b048-40f5-8bdc-9bb389916b59', 'Ski 500m',                 'pbExercise', 'timeOnly',      'fastestTime',          null, null, null,                                       17, true),
    ('00000000-0000-0000-0000-000000000017', '0abc9301-b048-40f5-8bdc-9bb389916b59', 'Plank',                    'pbExercise', 'weightAndTime', 'heaviestWeight',       null, null, null,                                       18, true),
    ('00000000-0000-0000-0000-000000000014', '0abc9301-b048-40f5-8bdc-9bb389916b59', 'Pulldown',                 'pbExercise', 'weightAndReps', 'bestWeightAndReps',    null, null, null,                                       19, true)
on conflict (id) do nothing;
