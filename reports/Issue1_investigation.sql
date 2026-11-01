select 
lc.employer_entity_id
, lc.contract_id
, lc.contract_class_id
, lc.contract_type_id
, r.resident_id
, r.first_name
, r.current_surname
, r.dob
, r.gender_id
, r.education_level_id
, r.ethnicity_id
, r.religion_id
, round((r.dob - timediff( '1980-01-01', '1900-01-01'))/365.25)  as age
, wjc.active_resident_id
, wjc.establishment_id
, wjc.sector_category_id
, wjc.contract_class_id
from livelihood_contracts as lc
left join workplace_job_slots as wjc on lc.resident_id = wjc.active_resident_id
left join residents as r on lc.resident_id = r.resident_id
where lc.employer_entity_id = "ESTAB_4615"