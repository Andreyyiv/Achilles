-- 109	Number of persons with continuous observation in each year
-- Note: using temp table instead of nested query because this gives vastly improved performance in Oracle

--HINT DISTRIBUTE_ON_KEY(obs_year)
SELECT DISTINCT 
  YEAR(observation_period_start_date) AS obs_year,
  DATEFROMPARTS(YEAR(observation_period_start_date), 1, 1) AS obs_year_start,
  DATETIMEFROMPARTS(YEAR(observation_period_start_date), 12, 31, 23, 59, 59, 999) AS obs_year_end
INTO
  #temp_dates_109
FROM @cdmDatabaseSchema.observation_period
;

--HINT DISTRIBUTE_ON_KEY(stratum_1)
SELECT 
  109 AS analysis_id,  
	CAST(obs_year AS VARCHAR(255)) AS stratum_1,
	cast(null as varchar(255)) as stratum_2, cast(null as varchar(255)) as stratum_3, cast(null as varchar(255)) as stratum_4, cast(null as varchar(255)) as stratum_5,
	COUNT_BIG(DISTINCT person_id) AS count_value
into @scratchDatabaseSchema@schemaDelim@tempAchillesPrefix_109
FROM @cdmDatabaseSchema.observation_period,
	#temp_dates_109
WHERE  
		observation_period_start_date <= obs_year_start
	AND 
		observation_period_end_date >= obs_year_end
GROUP BY 
	obs_year
;

TRUNCATE TABLE #temp_dates_109;
DROP TABLE #temp_dates_109;
