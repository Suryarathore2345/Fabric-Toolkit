-- Find out Running Queries that are taking more than 1 minute
SELECT
    r.session_id,
    s.login_name,
    s.program_name, 
    r.command,
    r.status,
    r.start_time,
    r.total_elapsed_time / 1000 / 60 AS elapsed_minutes,
    r.cpu_time,
    r.logical_reads,
    r.wait_time /60000 AS wait_minutes,
    r.wait_type
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s
    ON r.session_id = s.session_id
WHERE r.status = 'running' --OR r.status = 'Cancelling'
  AND r.total_elapsed_time >=  1 * 60 * 1000  
  and program_name <> 'QueryInsights'
ORDER BY r.total_elapsed_time desc;


--- Kill a Query 
KILL session_id ;