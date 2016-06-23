/******************************************************************

# @file ACHILLESHEEL.SQL
#
# Copyright 2014 Observational Health Data Sciences and Informatics
#
# This file is part of ACHILLES
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# @author Observational Health Data Sciences and Informatics




*******************************************************************/


/*******************************************************************

Achilles Heel - data quality assessment based on database profiling summary statistics

SQL for ACHILLES results (for either OMOP CDM v4 or OMOP CDM v5)


*******************************************************************/

{DEFAULT @cdm_database_schema = 'CDM.dbo'}
{DEFAULT @source_name = 'CDM NAME'}
{DEFAULT @smallcellcount = 5}
{DEFAULT @createTable = TRUE}

 
--@results_database_schema.ACHILLES_Heel part:

--prepare the tables first

IF OBJECT_ID('@results_database_schema.ACHILLES_HEEL_results', 'U') IS NOT NULL
  DROP TABLE @results_database_schema.ACHILLES_HEEL_results;

CREATE TABLE @results_database_schema.ACHILLES_HEEL_results (
  analysis_id INT,
	ACHILLES_HEEL_warning VARCHAR(255),
	rule_id INT,
	record_count BIGINT
);


--new part of Heel requires derived tables (per suggestion of Patrick)
--table structure is up for discussion
--per DQI group suggestion: measure_id is made into a string to make derivation
--and sql authoring easy
--computation is quick so the whole table gets wiped every time Heel is executed


IF OBJECT_ID('@results_database_schema.ACHILLES_results_derived', 'U') IS NOT NULL
  drop table @results_database_schema.ACHILLES_results_derived;

create table @results_database_schema.ACHILLES_results_derived
(
	analysis_id int,
	stratum_1 varchar(255),
	statistic_type varchar(255),
	statistic_value float,
	measure_id varchar(255)
);


--general derived measures
--non-CDM sources may generate derived measures directly
--for CDM and Achilles: the fastest way to compute derived measures is to use
--existing measures
--derived measures have IDs over 100 000 (not any more, instead, they use measure_id as their id)


--event type derived measures analysis xx05 is often analysis by xx_type
--generate counts for meas type, drug type, proc type, obs type
--optional TODO: possibly rewrite this with CASE statement to better make 705 into drug, 605 into proc ...etc
--               in measure_id column (or make that separate sql calls for each category)
insert into @results_database_schema.ACHILLES_results_derived (analysis_id, stratum_1, statistic_value,measure_id)    
select 
  --100000+analysis_id, 
  NULL as analysis_id,
  stratum_2 as stratum_1,
  sum(count_value) as statistic_value,
  'ach_'+CAST(analysis_id as VARCHAR) + ':GlobalCnt' as measure_id
from @results_database_schema.achilles_results 
where analysis_id in(1805,705,605,805,405) group by analysis_id,stratum_2;




--total number of rows per domain
--this derived measure is used for later measure of % of unmapped rows
--this produces a total count of rows in condition table, procedure table etc.
--used as denominator in later measures
    insert into @results_database_schema.ACHILLES_results_derived (statistic_value,measure_id)    
    select sum(count_value) as statistic_value, 
           'ach_'+CAST(analysis_id as VARCHAR) + ':GlobalRowCnt' as measure_id
    from @results_database_schema.achilles_results 
    where analysis_id in (401,601,701,801,1801) group by analysis_id
    ;

--concept_0 global row  Counts per domain
--this is numerator for percentage value of unmapped rows (per domain)
insert into @results_database_schema.ACHILLES_results_derived (statistic_value,measure_id)    
    select count_value as statistic_value, 
           'UnmappedData:ach_'+CAST(analysis_id as VARCHAR) + ':GlobalRowCnt' as measure_id
    from @results_database_schema.achilles_results 
    --TODO:stratum_1 is varchar and this comparison may fail on some db engines
    --indeed, mysql got error, changed to a string comparison
    where analysis_id in (401,601,701,801,1801) and stratum_1 = '0' 
    ;
    


--iris measures by percentage
--for this part, derived table is trying to adopt DQI terminolgy 
--and generalize analysis naming scheme (and generalize the DQ rules)

insert into @results_database_schema.ACHILLES_results_derived (statistic_value,measure_id)    
select 
   100.0*count_value/(select count_value as total_pts from @results_database_schema.achilles_results r where analysis_id =1) as statistic_value,
   'ach_'+CAST(analysis_id as VARCHAR) + ':Percentage' as measure_id
  from @results_database_schema.achilles_results 

  where analysis_id in (2000,2001,2002,2003);
  


insert into @results_database_schema.ACHILLES_results_derived (statistic_value,measure_id)    
    select sum(count_value) as statistic_value, 
           'Visit:InstanceCnt' as measure_id
 from @results_database_schema.achilles_results where analysis_id = 201;
 
 --in dist analysis/measure 203 - a number similar to that is computed above but it is on person level 


--age at first observation by decile
insert into @results_database_schema.ACHILLES_results_derived (stratum_1,statistic_value,measure_id)    
select cast(floor(cast(stratum_1 as int)/10) as varchar) as stratum_1,
  sum(count_value) as statistic_value,
  'AgeAtFirstObsByDecile:PersonCnt' as measure_id
  from @results_database_schema.achilles_results where analysis_id = 101
group by floor(cast(stratum_1 as int)/10);

--count whether all deciles from 0 to 8 are there  (has later a rule: if less the threshold, issue notification)
insert into @results_database_schema.ACHILLES_results_derived (statistic_value,measure_id)    
select count(*) as statistic_value,
 'AgeAtFirstObsByDecile:DecileCnt' as measure_id
from @results_database_schema.ACHILLES_results_derived
where measure_id = 'AgeAtFirstObsByDecile:PersonCnt' 
and cast(stratum_1 as int) <=8;


--data density measures
--for drug (exposure and eras)
insert into @results_database_schema.ACHILLES_results_derived (statistic_value,measure_id)    
select count(*) as statistic_value, 'DrugExposure:ConceptCnt' as measure_id 
from @results_database_schema.ACHILLES_results where analysis_id = 701;

insert into @results_database_schema.ACHILLES_results_derived (statistic_value,measure_id)    
select count(*) as statistic_value, 'DrugEra:ConceptCnt' as measure_id 
from @results_database_schema.ACHILLES_results where analysis_id = 901;


--unmapped data (concept_0) derived measures (focusing on source values)

insert into @results_database_schema.ACHILLES_results_derived (stratum_1,statistic_value,measure_id)    
select stratum_1,
count(*) as statistic_value,
'UnmappedDataByDomain:SourceValueCnt' as measure_id
from @results_database_schema.achilles_results where analysis_id = 1900 group by stratum_1;


--count of specialties in the provider table 
--(subsequent rule can check if this count is > trehshold) (general population dataset only))
insert into @results_database_schema.ACHILLES_results_derived (statistic_value,measure_id)    
select 
count(*) as statistic_value,
'Provider:SpeciatlyCnt' as measure_id
from @results_database_schema.achilles_results where analysis_id = 301;

--end of derived general measures ********************************************************************







--actual Heel rules start from here *****************************************







--Some rules check conformance to the CDM model, other rules look at data quality


--ruleid 1 check for non-zero counts from checks of improper data (invalid ids, out-of-bound data, inconsistent dates)
INSERT INTO @results_database_schema.ACHILLES_HEEL_results (
	analysis_id,
	ACHILLES_HEEL_warning,
	rule_id,
	record_count
	)
SELECT DISTINCT or1.analysis_id,
	'ERROR: ' + cast(or1.analysis_id as VARCHAR) + '-' + oa1.analysis_name + '; count (n=' + cast(or1.count_value as VARCHAR) + ') should not be > 0' AS ACHILLES_HEEL_warning,
	1 as rule_id,
	or1.count_value
FROM @results_database_schema.ACHILLES_results or1
INNER JOIN @results_database_schema.ACHILLES_analysis oa1
	ON or1.analysis_id = oa1.analysis_id
WHERE or1.analysis_id IN (
		7,
		8,
		9,
		114,
		115,
		118,
		207,
		208,
		209,
		210,
		302,
		409,
		410,
		411,
		412,
		413,
		509,
		510,
		609,
		610,
		612,
		613,
		709,
		710,
		711,
		712,
		713,
		809,
		810,
		812,
		813,
		814,
		908,
		909,
		910,
		1008,
		1009,
		1010,
		1415,
		1500,
		1501,
		1600,
		1601,
		1701
		) --all explicit counts of data anamolies
	AND or1.count_value > 0;

--ruleid 2 distributions where min should not be negative
INSERT INTO @results_database_schema.ACHILLES_HEEL_results (
	analysis_id,
	ACHILLES_HEEL_warning,
	rule_id,
	record_count
	)
SELECT DISTINCT ord1.analysis_id,
  'ERROR: ' + cast(ord1.analysis_id as VARCHAR) + ' - ' + oa1.analysis_name + ' (count = ' + cast(COUNT_BIG(ord1.min_value) as VARCHAR) + '); min value should not be negative' AS ACHILLES_HEEL_warning,
  2 as rule_id,
  COUNT_BIG(ord1.min_value) as record_count
FROM @results_database_schema.ACHILLES_results_dist ord1
INNER JOIN @results_database_schema.ACHILLES_analysis oa1
	ON ord1.analysis_id = oa1.analysis_id
WHERE ord1.analysis_id IN (
		103,
		105,
		206,
		406,
		506,
		606,
		706,
		715,
		716,
		717,
		806,
		906,
		907,
		1006,
		1007,
		1502,
		1503,
		1504,
		1505,
		1506,
		1507,
		1508,
		1509,
		1510,
		1511,
		1602,
		1603,
		1604,
		1605,
		1606,
		1607,
		1608
		)
	AND ord1.min_value < 0
	GROUP BY ord1.analysis_id,  oa1.analysis_name;

--ruleid 3 death distributions where max should not be positive
INSERT INTO @results_database_schema.ACHILLES_HEEL_results (
	analysis_id,
	ACHILLES_HEEL_warning,
	rule_id,
	record_count
)
SELECT DISTINCT ord1.analysis_id,
  'WARNING: ' + cast(ord1.analysis_id as VARCHAR) + '-' + oa1.analysis_name + ' (count = ' + cast(COUNT_BIG(ord1.max_value) as VARCHAR) + '); max value should not be positive, otherwise its a zombie with data >1mo after death ' AS ACHILLES_HEEL_warning,
  3 as rule_id,
  COUNT_BIG(ord1.max_value) as record_count
FROM @results_database_schema.ACHILLES_results_dist ord1
INNER JOIN @results_database_schema.ACHILLES_analysis oa1
	ON ord1.analysis_id = oa1.analysis_id
WHERE ord1.analysis_id IN (
		511,
		512,
		513,
		514,
		515
		)
	AND ord1.max_value > 30
GROUP BY ord1.analysis_id, oa1.analysis_name;

--ruleid 4 CDM-conformance rule: invalid concept_id
INSERT INTO @results_database_schema.ACHILLES_HEEL_results (
	analysis_id,
	ACHILLES_HEEL_warning,
	rule_id,
	record_count
)
SELECT or1.analysis_id,
	'ERROR: ' + cast(or1.analysis_id as VARCHAR) + '-' + oa1.analysis_name + '; ' + cast(COUNT_BIG(DISTINCT stratum_1) AS VARCHAR) + ' concepts in data are not in vocabulary' AS ACHILLES_HEEL_warning,
  4 as rule_id,
  COUNT_BIG(DISTINCT stratum_1) as record_count
FROM @results_database_schema.ACHILLES_results or1
INNER JOIN @results_database_schema.ACHILLES_analysis oa1
	ON or1.analysis_id = oa1.analysis_id
LEFT JOIN @vocab_database_schema.concept c1
	ON or1.stratum_1 = CAST(c1.concept_id AS VARCHAR)
WHERE or1.analysis_id IN (
		2,
		4,
		5,
		200,
		301,
		400,
		500,
		505,
		600,
		700,
		800,
		900,
		1000,
		1609,
		1610
		)
	AND or1.stratum_1 IS NOT NULL
	AND c1.concept_id IS NULL
GROUP BY or1.analysis_id,
	oa1.analysis_name;

--ruleid 5 CDM-conformance rule:invalid type concept_id
INSERT INTO @results_database_schema.ACHILLES_HEEL_results (
	analysis_id,
	ACHILLES_HEEL_warning,
	rule_id,
	record_count
	)
SELECT or1.analysis_id,
	'ERROR: ' + cast(or1.analysis_id as VARCHAR) + '-' + oa1.analysis_name + '; ' + cast(COUNT_BIG(DISTINCT stratum_2) AS VARCHAR) + ' concepts in data are not in vocabulary' AS ACHILLES_HEEL_warning,
  5 as rule_id,
  COUNT_BIG(DISTINCT stratum_2) as record_count
FROM @results_database_schema.ACHILLES_results or1
INNER JOIN @results_database_schema.ACHILLES_analysis oa1
	ON or1.analysis_id = oa1.analysis_id
LEFT JOIN @vocab_database_schema.concept c1
	ON or1.stratum_2 = CAST(c1.concept_id AS VARCHAR)
WHERE or1.analysis_id IN (
		405,
		605,
		705,
		805
		)
	AND or1.stratum_2 IS NOT NULL
	AND c1.concept_id IS NULL
GROUP BY or1.analysis_id,
	oa1.analysis_name;

--ruleid 6 CDM-conformance rule:invalid concept_id
INSERT INTO @results_database_schema.ACHILLES_HEEL_results (
	analysis_id,
	ACHILLES_HEEL_warning,
	rule_id,
	record_count
	)
SELECT or1.analysis_id,
	'WARNING: ' + cast(or1.analysis_id as VARCHAR) + '-' + oa1.analysis_name + '; data with unmapped concepts' AS ACHILLES_HEEL_warning,
  6 as rule_id,
  null as record_count
FROM @results_database_schema.ACHILLES_results or1
INNER JOIN @results_database_schema.ACHILLES_analysis oa1
	ON or1.analysis_id = oa1.analysis_id
WHERE or1.analysis_id IN (
		2,
		4,
		5,
		200,
		301,
		400,
		500,
		505,
		600,
		700,
		800,
		900,
		1000,
		1609,
		1610
		)
	AND or1.stratum_1 = '0'
GROUP BY or1.analysis_id,
	oa1.analysis_name;

--concept from the wrong vocabulary
--ruleid 7 CDM-conformance rule:gender  - 12 HL7
INSERT INTO @results_database_schema.ACHILLES_HEEL_results (
	analysis_id,
	ACHILLES_HEEL_warning,
	rule_id,
	record_count
	)
SELECT or1.analysis_id,
	'ERROR: ' + cast(or1.analysis_id as VARCHAR) + '-' + oa1.analysis_name + '; ' + cast(COUNT_BIG(DISTINCT stratum_1) AS VARCHAR) + ' concepts in data are not in correct vocabulary' AS ACHILLES_HEEL_warning,
  7 as rule_id,
  COUNT_BIG(DISTINCT stratum_1) as record_count
FROM @results_database_schema.ACHILLES_results or1
INNER JOIN @results_database_schema.ACHILLES_analysis oa1
	ON or1.analysis_id = oa1.analysis_id
INNER JOIN @vocab_database_schema.concept c1
	ON or1.stratum_1 = CAST(c1.concept_id AS VARCHAR)
WHERE or1.analysis_id IN (2)
	AND or1.stratum_1 IS NOT NULL
	AND c1.concept_id <> 0 
  AND lower(c1.domain_id) NOT IN ('gender')
GROUP BY or1.analysis_id,
	oa1.analysis_name;

--ruleid 8 race  - 13 CDC Race
INSERT INTO @results_database_schema.ACHILLES_HEEL_results (
	analysis_id,
	ACHILLES_HEEL_warning,
	rule_id,
	record_count
	)
SELECT or1.analysis_id,
	'ERROR: ' + cast(or1.analysis_id as VARCHAR) + '-' + oa1.analysis_name + '; ' + cast(COUNT_BIG(DISTINCT stratum_1) AS VARCHAR) + ' concepts in data are not in correct vocabulary' AS ACHILLES_HEEL_warning,
  8 as rule_id,
  COUNT_BIG(DISTINCT stratum_1) as record_count
FROM @results_database_schema.ACHILLES_results or1
INNER JOIN @results_database_schema.ACHILLES_analysis oa1
	ON or1.analysis_id = oa1.analysis_id
INNER JOIN @vocab_database_schema.concept c1
	ON or1.stratum_1 = CAST(c1.concept_id AS VARCHAR)
WHERE or1.analysis_id IN (4)
	AND or1.stratum_1 IS NOT NULL
	AND c1.concept_id <> 0 
  AND lower(c1.domain_id) NOT IN ('race')
GROUP BY or1.analysis_id,
	oa1.analysis_name;

--ruleid 9 ethnicity - 44 ethnicity
INSERT INTO @results_database_schema.ACHILLES_HEEL_results (
	analysis_id,
	ACHILLES_HEEL_warning,
	rule_id,
	record_count
	)
SELECT or1.analysis_id,
	'ERROR: ' + cast(or1.analysis_id as VARCHAR) + '-' + oa1.analysis_name + '; ' + cast(COUNT_BIG(DISTINCT stratum_1) AS VARCHAR) + ' concepts in data are not in correct vocabulary (CMS Ethnicity)' AS ACHILLES_HEEL_warning,
  9 as rule_id,
  COUNT_BIG(DISTINCT stratum_1) as record_count
FROM @results_database_schema.ACHILLES_results or1
INNER JOIN @results_database_schema.ACHILLES_analysis oa1
	ON or1.analysis_id = oa1.analysis_id
INNER JOIN @vocab_database_schema.concept c1
	ON or1.stratum_1 = CAST(c1.concept_id AS VARCHAR)
WHERE or1.analysis_id IN (5)
	AND or1.stratum_1 IS NOT NULL
	AND c1.concept_id <> 0 
  AND lower(c1.domain_id) NOT IN ('ethnicity')
GROUP BY or1.analysis_id,
	oa1.analysis_name;

--ruleid 10 place of service - 14 CMS place of service, 24 OMOP visit
INSERT INTO @results_database_schema.ACHILLES_HEEL_results (
	analysis_id,
	ACHILLES_HEEL_warning,
	rule_id,
	record_count
	)
SELECT or1.analysis_id,
	'ERROR: ' + cast(or1.analysis_id as VARCHAR) + '-' + oa1.analysis_name + '; ' + cast(COUNT_BIG(DISTINCT stratum_1) AS VARCHAR) + ' concepts in data are not in correct vocabulary' AS ACHILLES_HEEL_warning,
  10 as rule_id,
  COUNT_BIG(DISTINCT stratum_1) as record_count
FROM @results_database_schema.ACHILLES_results or1
INNER JOIN @results_database_schema.ACHILLES_analysis oa1
	ON or1.analysis_id = oa1.analysis_id
INNER JOIN @vocab_database_schema.concept c1
	ON or1.stratum_1 = CAST(c1.concept_id AS VARCHAR)
WHERE or1.analysis_id IN (202)
	AND or1.stratum_1 IS NOT NULL
	AND c1.concept_id <> 0 
  AND lower(c1.domain_id) NOT IN ('visit')
GROUP BY or1.analysis_id,
	oa1.analysis_name;

--ruleid 11 CDM-conformance rule:specialty - 48 specialty
INSERT INTO @results_database_schema.ACHILLES_HEEL_results (
	analysis_id,
	ACHILLES_HEEL_warning,
	rule_id,
	record_count
	)
SELECT or1.analysis_id,
	'ERROR: ' + cast(or1.analysis_id as VARCHAR) + '-' + oa1.analysis_name + '; ' + cast(COUNT_BIG(DISTINCT stratum_1) AS VARCHAR) + ' concepts in data are not in correct vocabulary (Specialty)' AS ACHILLES_HEEL_warning,
  11 as rule_id,
  COUNT_BIG(DISTINCT stratum_1) as record_count
FROM @results_database_schema.ACHILLES_results or1
INNER JOIN @results_database_schema.ACHILLES_analysis oa1
	ON or1.analysis_id = oa1.analysis_id
INNER JOIN @vocab_database_schema.concept c1
	ON or1.stratum_1 = CAST(c1.concept_id AS VARCHAR)
WHERE or1.analysis_id IN (301)
	AND or1.stratum_1 IS NOT NULL
	AND c1.concept_id <> 0 
  AND lower(c1.domain_id) NOT IN ('provider specialty')
GROUP BY or1.analysis_id,
	oa1.analysis_name;

--ruleid 12 condition occurrence, era - 1 SNOMED
INSERT INTO @results_database_schema.ACHILLES_HEEL_results (
	analysis_id,
	ACHILLES_HEEL_warning,
	rule_id,
	record_count
	)
SELECT or1.analysis_id,
	'ERROR: ' + cast(or1.analysis_id as VARCHAR) + '-' + oa1.analysis_name + '; ' + cast(COUNT_BIG(DISTINCT stratum_1) AS VARCHAR) + ' concepts in data are not in correct vocabulary' AS ACHILLES_HEEL_warning,
  12 as rule_id,
  COUNT_BIG(DISTINCT stratum_1) as record_count
FROM @results_database_schema.ACHILLES_results or1
INNER JOIN @results_database_schema.ACHILLES_analysis oa1
	ON or1.analysis_id = oa1.analysis_id
INNER JOIN @vocab_database_schema.concept c1
	ON or1.stratum_1 = CAST(c1.concept_id AS VARCHAR)
WHERE or1.analysis_id IN (
		400,
		1000
		)
	AND or1.stratum_1 IS NOT NULL
	AND c1.concept_id <> 0 
  AND lower(c1.domain_id) NOT IN ('condition','condition/drug', 'condition/meas', 'condition/obs', 'condition/procedure')
GROUP BY or1.analysis_id,
	oa1.analysis_name;

--ruleid 13 drug exposure - 8 RxNorm
INSERT INTO @results_database_schema.ACHILLES_HEEL_results (
	analysis_id,
	ACHILLES_HEEL_warning,
	rule_id,
	record_count
	)
SELECT or1.analysis_id,
	'ERROR: ' + cast(or1.analysis_id as VARCHAR) + '-' + oa1.analysis_name + '; ' + cast(COUNT_BIG(DISTINCT stratum_1) AS VARCHAR) + ' concepts in data are not in correct vocabulary' AS ACHILLES_HEEL_warning,
  13 as rule_id,
  COUNT_BIG(DISTINCT stratum_1) as record_count
FROM @results_database_schema.ACHILLES_results or1
INNER JOIN @results_database_schema.ACHILLES_analysis oa1
	ON or1.analysis_id = oa1.analysis_id
INNER JOIN @vocab_database_schema.concept c1
	ON or1.stratum_1 = CAST(c1.concept_id AS VARCHAR)
WHERE or1.analysis_id IN (
		700,
		900
		)
	AND or1.stratum_1 IS NOT NULL
	AND c1.concept_id <> 0 
  AND lower(c1.domain_id) NOT IN ('drug','condition/drug', 'device/drug', 'drug/measurement', 'drug/obs', 'drug/procedure')
GROUP BY or1.analysis_id,
	oa1.analysis_name;

--ruleid 14 procedure - 4 CPT4/5 HCPCS/3 ICD9P
INSERT INTO @results_database_schema.ACHILLES_HEEL_results (
	analysis_id,
	ACHILLES_HEEL_warning,
	rule_id,
	record_count
	)
SELECT or1.analysis_id,
	'ERROR: ' + cast(or1.analysis_id as VARCHAR) + '-' + oa1.analysis_name + '; ' + cast(COUNT_BIG(DISTINCT stratum_1) AS VARCHAR) + ' concepts in data are not in correct vocabulary' AS ACHILLES_HEEL_warning,
  14 as rule_id,
  COUNT_BIG(DISTINCT stratum_1) as record_count
FROM @results_database_schema.ACHILLES_results or1
INNER JOIN @results_database_schema.ACHILLES_analysis oa1
	ON or1.analysis_id = oa1.analysis_id
INNER JOIN @vocab_database_schema.concept c1
	ON or1.stratum_1 = CAST(c1.concept_id AS VARCHAR)
WHERE or1.analysis_id IN (600)
	AND or1.stratum_1 IS NOT NULL
	AND c1.concept_id <> 0 
  AND lower(c1.domain_id) NOT IN ('procedure','condition/procedure', 'device/procedure', 'drug/procedure', 'obs/procedure')
GROUP BY or1.analysis_id,
	oa1.analysis_name;

--15 observation  - 6 LOINC

--NOT APPLICABLE IN CDMv5


--16 disease class - 40 DRG

--NOT APPLICABLE IN CDMV5

--ruleid 17 revenue code - 43 revenue code
INSERT INTO @results_database_schema.ACHILLES_HEEL_results (
	analysis_id,
	ACHILLES_HEEL_warning,
	rule_id,
	record_count
	)
SELECT or1.analysis_id,
	'ERROR: ' + cast(or1.analysis_id as VARCHAR) + '-' + oa1.analysis_name + '; ' + cast(COUNT_BIG(DISTINCT stratum_1) AS VARCHAR) + ' concepts in data are not in correct vocabulary (revenue code)' AS ACHILLES_HEEL_warning,
  17 as rule_id,
  COUNT_BIG(DISTINCT stratum_1) as record_count
FROM @results_database_schema.ACHILLES_results or1
INNER JOIN @results_database_schema.ACHILLES_analysis oa1
	ON or1.analysis_id = oa1.analysis_id
INNER JOIN @vocab_database_schema.concept c1
	ON or1.stratum_1 = CAST(c1.concept_id AS VARCHAR)
WHERE or1.analysis_id IN (1610)
	AND or1.stratum_1 IS NOT NULL
	AND c1.concept_id <> 0 
  AND lower(c1.domain_id) NOT IN ('revenue code')
GROUP BY or1.analysis_id,
	oa1.analysis_name;


--ruleid 18 ERROR:  year of birth in the future
INSERT INTO @results_database_schema.ACHILLES_HEEL_results (
	analysis_id,
	ACHILLES_HEEL_warning,
	rule_id,
	record_count
	)
SELECT DISTINCT or1.analysis_id,
	'ERROR: ' + cast(or1.analysis_id as VARCHAR) + '-' + oa1.analysis_name + '; should not have year of birth in the future, (n=' + cast(sum(or1.count_value) as VARCHAR) + ')' AS ACHILLES_HEEL_warning,
  18 as rule_id,
  sum(or1.count_value) as record_count
FROM @results_database_schema.ACHILLES_results or1
INNER JOIN @results_database_schema.ACHILLES_analysis oa1
	ON or1.analysis_id = oa1.analysis_id
WHERE or1.analysis_id IN (3)
	AND CAST(or1.stratum_1 AS INT) > year(getdate())
	AND or1.count_value > 0
GROUP BY or1.analysis_id,
  oa1.analysis_name;


--ruleid 19 WARNING:  year of birth < 1800
INSERT INTO @results_database_schema.ACHILLES_HEEL_results (
	analysis_id,
	ACHILLES_HEEL_warning,
	rule_id,
	record_count
	)
SELECT or1.analysis_id,
	'ERROR: ' + cast(or1.analysis_id as VARCHAR) + '-' + oa1.analysis_name + '; should not have year of birth < 1800, (n=' + cast(sum(or1.count_value) as VARCHAR) + ')' AS ACHILLES_HEEL_warning,
  19 as rule_id,
  sum(or1.count_value) as record_count
FROM @results_database_schema.ACHILLES_results or1
INNER JOIN @results_database_schema.ACHILLES_analysis oa1
	ON or1.analysis_id = oa1.analysis_id
WHERE or1.analysis_id IN (3)
	AND cAST(or1.stratum_1 AS INT) < 1800
	AND or1.count_value > 0
GROUP BY or1.analysis_id,
  oa1.analysis_name;

--ruleid 20 ERROR:  age < 0
INSERT INTO @results_database_schema.ACHILLES_HEEL_results (
	analysis_id,
	ACHILLES_HEEL_warning,
	rule_id,
	record_count
	)
SELECT or1.analysis_id,
	'ERROR: ' + cast(or1.analysis_id as VARCHAR) + '-' + oa1.analysis_name + '; should not have age < 0, (n=' + cast(sum(or1.count_value) as VARCHAR) + ')' AS ACHILLES_HEEL_warning,
  20 as rule_id,
  sum(or1.count_value) as record_count
FROM @results_database_schema.ACHILLES_results or1
INNER JOIN @results_database_schema.ACHILLES_analysis oa1
	ON or1.analysis_id = oa1.analysis_id
WHERE or1.analysis_id IN (101)
	AND CAST(or1.stratum_1 AS INT) < 0
	AND or1.count_value > 0
GROUP BY or1.analysis_id,
  oa1.analysis_name;

--ruleid 21 ERROR: age > 150  (TODO lower number seems more appropriate)
INSERT INTO @results_database_schema.ACHILLES_HEEL_results (
	analysis_id,
	ACHILLES_HEEL_warning,
	rule_id,
	record_count
	)
SELECT or1.analysis_id,
	'ERROR: ' + cast(or1.analysis_id as VARCHAR) + '-' + oa1.analysis_name + '; should not have age > 150, (n=' + cast(sum(or1.count_value) as VARCHAR) + ')' AS ACHILLES_HEEL_warning,
  21 as rule_id,
  sum(or1.count_value) as record_count
FROM @results_database_schema.ACHILLES_results or1
INNER JOIN @results_database_schema.ACHILLES_analysis oa1
	ON or1.analysis_id = oa1.analysis_id
WHERE or1.analysis_id IN (101)
	AND CAST(or1.stratum_1 AS INT) > 150
	AND or1.count_value > 0
GROUP BY or1.analysis_id,
  oa1.analysis_name;

--ruleid 22 WARNING:  monthly change > 100%
INSERT INTO @results_database_schema.ACHILLES_HEEL_results (
	analysis_id,
	ACHILLES_HEEL_warning,
	rule_id
	
	)
SELECT DISTINCT ar1.analysis_id,
	'WARNING: ' + cast(ar1.analysis_id as VARCHAR) + '-' + aa1.analysis_name + '; theres a 100% change in monthly count of events' AS ACHILLES_HEEL_warning,
  22 as rule_id
  
FROM @results_database_schema.ACHILLES_analysis aa1
INNER JOIN @results_database_schema.ACHILLES_results ar1
	ON aa1.analysis_id = ar1.analysis_id
INNER JOIN @results_database_schema.ACHILLES_results ar2
	ON ar1.analysis_id = ar2.analysis_id
		AND ar1.analysis_id IN (
			420,
			620,
			720,
			820,
			920,
			1020
			)
WHERE (
		CAST(ar1.stratum_1 AS INT) + 1 = CAST(ar2.stratum_1 AS INT)
		OR CAST(ar1.stratum_1 AS INT) + 89 = CAST(ar2.stratum_1 AS INT)
		)
	AND 1.0 * abs(ar2.count_value - ar1.count_value) / ar1.count_value > 1
	AND ar1.count_value > 10;

--ruleid 23 WARNING:  monthly change > 100% at concept level
INSERT INTO @results_database_schema.ACHILLES_HEEL_results (
	analysis_id,
	ACHILLES_HEEL_warning,
	rule_id,
	record_count
	)
SELECT ar1.analysis_id,
	'WARNING: ' + cast(ar1.analysis_id as VARCHAR) + '-' + aa1.analysis_name + '; ' + cast(COUNT_BIG(DISTINCT ar1.stratum_1) AS VARCHAR) + ' concepts have a 100% change in monthly count of events' AS ACHILLES_HEEL_warning,
  23 as rule_id,
  COUNT_BIG(DISTINCT ar1.stratum_1) as record_count
FROM @results_database_schema.ACHILLES_analysis aa1
INNER JOIN @results_database_schema.ACHILLES_results ar1
	ON aa1.analysis_id = ar1.analysis_id
INNER JOIN @results_database_schema.ACHILLES_results ar2
	ON ar1.analysis_id = ar2.analysis_id
		AND ar1.stratum_1 = ar2.stratum_1
		AND ar1.analysis_id IN (
			402,
			602,
			702,
			802,
			902,
			1002
			)
WHERE (
		CAST(ar1.stratum_2 AS INT) + 1 = CAST(ar2.stratum_2 AS INT)
		OR CAST(ar1.stratum_2 AS INT) + 89 = CAST(ar2.stratum_2 AS INT)
		)
	AND 1.0 * abs(ar2.count_value - ar1.count_value) / ar1.count_value > 1
	AND ar1.count_value > 10
GROUP BY ar1.analysis_id,
	aa1.analysis_name;

--ruleid 24 WARNING: days_supply > 180 
INSERT INTO @results_database_schema.ACHILLES_HEEL_results (
	analysis_id,
	ACHILLES_HEEL_warning,
	rule_id,
	record_count
	)
SELECT DISTINCT ord1.analysis_id,
  'WARNING: ' + cast(ord1.analysis_id as VARCHAR) + '-' + oa1.analysis_name + ' (count = ' + cast(COUNT_BIG(ord1.max_value) as VARCHAR) + '); max value should not be > 180' AS ACHILLES_HEEL_warning,
  24 as rule_id,
  COUNT_BIG(ord1.max_value) as record_count
FROM @results_database_schema.ACHILLES_results_dist ord1
INNER JOIN @results_database_schema.ACHILLES_analysis oa1
	ON ord1.analysis_id = oa1.analysis_id
WHERE ord1.analysis_id IN (715)
	AND ord1.max_value > 180
GROUP BY ord1.analysis_id, oa1.analysis_name;

--ruleid 25 WARNING:  refills > 10
INSERT INTO @results_database_schema.ACHILLES_HEEL_results (
	analysis_id,
	ACHILLES_HEEL_warning,
	rule_id,
	record_count
	)
SELECT DISTINCT ord1.analysis_id,
  'WARNING: ' + cast(ord1.analysis_id as VARCHAR) + '-' + oa1.analysis_name + ' (count = ' + cast(COUNT_BIG(ord1.max_value) as VARCHAR) + '); max value should not be > 10' AS ACHILLES_HEEL_warning,
  25 as rule_id,
  COUNT_BIG(ord1.max_value) as record_count
FROM @results_database_schema.ACHILLES_results_dist ord1
INNER JOIN @results_database_schema.ACHILLES_analysis oa1
	ON ord1.analysis_id = oa1.analysis_id
WHERE ord1.analysis_id IN (716)
	AND ord1.max_value > 10
GROUP BY ord1.analysis_id, oa1.analysis_name;

--ruleid 26 DQ rule: WARNING: quantity > 600
INSERT INTO @results_database_schema.ACHILLES_HEEL_results (
	analysis_id,
	ACHILLES_HEEL_warning,
	rule_id,
	record_count
	)
SELECT DISTINCT ord1.analysis_id,
  'WARNING: ' + cast(ord1.analysis_id as VARCHAR) + '-' + oa1.analysis_name + ' (count = ' + cast(count(ord1.max_value) as VARCHAR) + '); max value should not be > 600' AS ACHILLES_HEEL_warning,
  26 as rule_id,
  count(ord1.max_value) as record_count
FROM @results_database_schema.ACHILLES_results_dist ord1
INNER JOIN @results_database_schema.ACHILLES_analysis oa1
	ON ord1.analysis_id = oa1.analysis_id
WHERE ord1.analysis_id IN (717)
	AND ord1.max_value > 600
GROUP BY ord1.analysis_id, oa1.analysis_name;



--rules may require first a derived measure and the subsequent data quality 
--check is simpler to implement
--also results are accessible even if the rule did not generate a warning

--rule27
--due to most likely missint sql cast errors it was removed from this release
--will be included after more testing
--being fixed in this update

--compute derived measure first
insert into @results_database_schema.ACHILLES_results_derived (statistic_value,stratum_1,measure_id)    
select
  100.0*(select statistic_value from @results_database_schema.achilles_results_derived where measure_id like 'UnmappedData:ach_401:GlobalRowCnt')/statistic_value as statistic_value,
  'Condition' as stratum_1,
  'UnmappedData:byDomain:Percentage' as measure_id
from @results_database_schema.achilles_results_derived where measure_id ='ach_401:GlobalRowCnt';

insert into @results_database_schema.ACHILLES_results_derived (statistic_value,stratum_1,measure_id)    
select
  100.0*(select statistic_value from @results_database_schema.achilles_results_derived where measure_id = 'UnmappedData:ach_601:GlobalRowCnt')/statistic_value as statistic_value,
  'Procedure' as stratum_1,
  'UnmappedData:byDomain:Percentage' as measure_id
from @results_database_schema.achilles_results_derived where measure_id ='ach_601:GlobalRowCnt';

insert into @results_database_schema.ACHILLES_results_derived (statistic_value,stratum_1,measure_id)    
select
  100.0*(select statistic_value from @results_database_schema.achilles_results_derived where measure_id = 'UnmappedData:ach_701:GlobalRowCnt')/statistic_value as statistic_value,
  'DrugExposure' as stratum_1,
  'UnmappedData:byDomain:Percentage' as measure_id
from @results_database_schema.achilles_results_derived where measure_id ='ach_701:GlobalRowCnt';

insert into @results_database_schema.ACHILLES_results_derived (statistic_value,stratum_1,measure_id)    
select
  100.0*(select statistic_value from @results_database_schema.achilles_results_derived where measure_id = 'UnmappedData:ach_801:GlobalRowCnt')/statistic_value as statistic_value,
  'Observation' as stratum_1,
  'UnmappedData:byDomain:Percentage' as measure_id
from @results_database_schema.achilles_results_derived where measure_id ='ach_801:GlobalRowCnt';

insert into @results_database_schema.ACHILLES_results_derived (statistic_value,stratum_1,measure_id)    
select
  100.0*(select statistic_value from @results_database_schema.achilles_results_derived where measure_id = 'UnmappedData:ach_1801:GlobalRowCnt')/statistic_value as statistic_value,
  'Measurement' as stratum_1,
  'UnmappedData:byDomain:Percentage' as measure_id
from @results_database_schema.achilles_results_derived where measure_id ='ach_1801:GlobalRowCnt';


--actual rule27

  INSERT INTO @results_database_schema.ACHILLES_HEEL_results (ACHILLES_HEEL_warning,rule_id)
  SELECT 
   'NOTIFICATION:Unmapped data over percentage threshold in:' + cast(d.stratum_1 as varchar) as ACHILLES_HEEL_warning,
    27 as rule_id
  FROM @results_database_schema.ACHILLES_results_derived d
  where d.measure_id = 'UnmappedData:byDomain:Percentage'
  and d.statistic_value > 0.1  --thresholds will be decided in the ongoing DQ-Study2
  ;

--end of rule27

--rule28 DQ rule
--are all values (or more than threshold) in measurement table non numerical?
--(count of Measurment records with no numerical value is in analysis_id 1821)



with t1 (all_count) as 
  (select sum(count_value) as all_count from @results_database_schema.achilles_results where analysis_id = 1820)
  --count of all meas rows (I wish this would also be a measure) (1820 is count by month)
select 
CAST('percentage' AS VARCHAR(100)) as statistic_type,
(select count_value from @results_database_schema.achilles_results where analysis_id = 1821)*100.0/all_count as statistic_value,
CAST('Meas:NoNumValue:Percentage' AS VARCHAR(100)) as measure_id
into #tempResults 
from t1;


insert into @results_database_schema.ACHILLES_results_derived (statistic_type, statistic_value, measure_id)    
  select  statistic_type,statistic_value,measure_id from #tempResults;



INSERT INTO @results_database_schema.ACHILLES_HEEL_results (ACHILLES_HEEL_warning,rule_id)
SELECT 
  'NOTIFICATION: percentage of non-numerical measurement records exceeds general population threshold ' as ACHILLES_HEEL_warning,
	28 as rule_id
FROM #tempResults t
--WHERE t.analysis_id IN (100730,100430) --umbrella version
WHERE measure_id='Meas:NoNumValue:Percentage' --t.analysis_id IN (100000)
--the intended threshold is 1 percent, this value is there to get pilot data from early adopters
	AND t.statistic_value >= 80
;


--clean up temp tables for rule 28
truncate table #tempResults;
drop table #tempResults;

--end of rule 28

--rule29 DQ rule
--unusual diagnosis present, this rule is terminology dependend

with tempcnt as(
	select sum(count_value) as pt_cnt from @results_database_schema.achilles_results 
	where analysis_id = 404 --dx by decile
	and stratum_1 = '195075' --meconium
	--and stratum_3 = '8507' --possible limit to males only
	and cast(stratum_4 as int) >= 5 --fifth decile or more
)
select pt_cnt as record_count 
into #tempResults
--set threshold here, currently it is zero
from tempcnt where pt_cnt > 0;


--using temp table because with clause that occurs prior insert into is causing problems 
--and with clause makes the code more readable
INSERT INTO @results_database_schema.ACHILLES_HEEL_results (ACHILLES_HEEL_warning,rule_id,record_count)
SELECT 
 'WARNING:[PLAUSIBILITY] infant-age diagnosis (195075) at age 50+' as ACHILLES_HEEL_warning,
  29 as rule_id,
  record_count
FROM #tempResults t;

truncate table #tempResults;
drop table #tempResults;
--end of rule29


--rule30 CDM-conformance rule: is CDM metadata table created at all?
  --create a derived measure for rule30
  --done strangly to possibly avoid from dual error on Oracle
  --done as not null just in case sqlRender has NOT NULL  hard coded
  --check if table exist and if yes - derive 1 for a derived measure
  
  --does not work on redshift :-( --commenting it out
--IF OBJECT_ID('@cdm_database_schema.CDM_SOURCE', 'U') IS NOT NULL
--insert into @results_database_schema.ACHILLES_results_derived (statistic_value,measure_id)    
--  select distinct analysis_id as statistic_value,
--  'MetaData:TblExists' as measure_id
--  from @results_database_schema.ACHILLES_results
--  where analysis_id = 1;
  
  --actual rule30
  
--end of rule30


--rule31 DQ rule
--ratio of providers to total patients

--compute a derived reatio
--TODO if provider count is zero it will generate division by zero (not sure how dirrerent db engins will react)
insert into @results_database_schema.ACHILLES_results_derived (statistic_value,measure_id)    
    select  1.0*(select count_value as total_pts from @results_database_schema.achilles_results r where analysis_id =1)/count_value as statistic_value,
    'Provider:PatientProviderRatio' as measure_id
    from @results_database_schema.achilles_results where analysis_id = 300
;

--actual rule
INSERT INTO @results_database_schema.ACHILLES_HEEL_results (ACHILLES_HEEL_warning,rule_id)
SELECT 
 'NOTIFICATION:[PLAUSIBILITY] database has too few providers defined (given the total patient number)' as ACHILLES_HEEL_warning,
  31 as rule_id
FROM @results_database_schema.ACHILLES_results_derived d
where d.measure_id = 'Provider:PatientProviderRatio'
and d.statistic_value > 10000  --thresholds will be decided in the ongoing DQ-Study2
;

--rule32 DQ rule
--uses iris: patients with at least one visit visit 
--does 100-THE IRIS MEASURE to check for percentage of patients with no visits

INSERT INTO @results_database_schema.ACHILLES_HEEL_results (ACHILLES_HEEL_warning,rule_id)
SELECT 
 'NOTIFICATION: Percentage of patients with no visits exceeds threshold' as ACHILLES_HEEL_warning,
  32 as rule_id
FROM @results_database_schema.ACHILLES_results_derived d
where d.measure_id = 'ach_2003:Percentage'
and 100-d.statistic_value > 5  --thresholds will be decided in the ongoing DQ-Study2
;

--rule33 DQ rule (for general population only)
--NOTIFICATION: database does not have all age 0-80 represented


INSERT INTO @results_database_schema.ACHILLES_HEEL_results (ACHILLES_HEEL_warning,rule_id)
SELECT 
 'NOTIFICATION: [GeneralPopulationOnly] Not all deciles represented at first observation' as ACHILLES_HEEL_warning,
  33 as rule_id
FROM @results_database_schema.ACHILLES_results_derived d
where d.measure_id = 'AgeAtFirstObsByDecile:DecileCnt' 
and d.statistic_value <9  --we expect deciles 0,1,2,3,4,5,6,7,8 
;

 
--rule34 DQ rule
--NOTIFICATION: number of unmapped source values exceeds threshold
--related to rule 27 that looks at percentage of unmapped rows (rows as focus)
--this rule is looking at source values (as focus)


INSERT INTO @results_database_schema.ACHILLES_HEEL_results (ACHILLES_HEEL_warning,rule_id,record_count)
SELECT 
 'NOTIFICATION: Count of unmapped source values exceeds threshold in: ' +cast(stratum_1 as varchar) as ACHILLES_HEEL_warning,
  34 as rule_id,
  cast(statistic_value as int) as record_count
FROM @results_database_schema.ACHILLES_results_derived d
where measure_id = 'UnmappedDataByDomain:SourceValueCnt'
and statistic_value > 1000; --threshold will be decided in DQ study 2





