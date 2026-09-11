-- Wall-clock process and top-level compiler durations. Nested durations must
-- not be added together or treated as independent wall-clock costs.
SELECT name, ROUND(dur / 1e9, 3) AS seconds
FROM slice
WHERE category = 'buildprof.process'
ORDER BY dur DESC LIMIT 8;

SELECT name, ROUND(dur / 1e9, 3) AS seconds,
       extract_arg(arg_set_id, 'debug.detail') AS detail
FROM slice
WHERE category = 'buildprof.compiler'
ORDER BY dur DESC LIMIT 25;

SELECT extract_arg(arg_set_id, 'debug.detail') AS module,
       ROUND(dur / 1e9, 3) AS seconds, track_id
FROM slice
WHERE category = 'buildprof.compiler' AND name = 'OptModule'
ORDER BY dur DESC LIMIT 20;

-- Aggregate elapsed task durations across potentially parallel workers.
-- These totals are not the link's elapsed time or measured CPU time.
SELECT
  CASE
    WHEN extract_arg(arg_set_id, 'debug.detail') GLOB 'bun-zig*'
      THEN 'Zig objects'
    WHEN extract_arg(arg_set_id, 'debug.detail') GLOB '*webkit*'
      THEN 'WebKit/ICU'
    WHEN extract_arg(arg_set_id, 'debug.detail') GLOB 'libbun-profile.a*'
      THEN 'Bun C/C++'
    ELSE extract_arg(arg_set_id, 'debug.detail')
  END AS inputs,
  COUNT(*) AS modules,
  ROUND(SUM(dur) / 1e9, 3) AS aggregate_task_seconds,
  ROUND(MAX(dur) / 1e9, 3) AS longest_task_seconds
FROM slice
WHERE category = 'buildprof.compiler' AND name = 'OptModule'
GROUP BY inputs
ORDER BY aggregate_task_seconds DESC;
