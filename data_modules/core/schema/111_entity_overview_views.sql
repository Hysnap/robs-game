-- res://data_modules/core/schema/views/111_entity_overview_views.sql
-- Tier 111: Entity Overview Views (Residents, Households, Contracts, Establishments, Bonds, and Job Slots)
CREATE VIEW
    IF NOT EXISTS v_residents_overview AS
SELECT
    r.resident_id,
    r.household_id,
    e.district_id,
    d.display_name AS district_name,
    d.borough_id,
    b.display_name AS borough_name,
    r.first_name,
    r.current_surname,
    r.birth_surname,
    l_gender.code AS gender_code,
    l_gender.title AS gender_title,
    r.dob AS dob_day_offset,
    date (
        (
            SELECT
                value
            FROM
                world_metadata
            WHERE
                key = 'epoch_date'
        ),
        '+' || r.dob || ' days'
    ) AS formatted_birth_date,
    r.dod AS dod_day_offset,
    CASE
        WHEN r.dod IS NOT NULL THEN date (
            (
                SELECT
                    value
                FROM
                    world_metadata
                WHERE
                    key = 'epoch_date'
            ),
            '+' || r.dod || ' days'
        )
        ELSE NULL
    END AS formatted_death_date,
    CASE
        WHEN r.dod IS NULL THEN 1
        ELSE 0
    END AS is_alive,
    l_edu.code AS education_code,
    l_edu.title AS education_title,
    l_eth.title AS ethnicity_title,
    l_rel.title AS religion_title,
    r.church_id,
    e_church.name AS church_name,
    r.local_pub_id,
    e_pub.name AS local_pub_name,
    r.openness,
    r.conscientiousness,
    r.extraversion,
    r.agreeableness,
    r.neuroticism,
    r.is_active_agent
FROM
    residents r
    JOIN households h ON r.household_id = h.household_id
    JOIN establishments e ON h.establishment_id = e.establishment_id
    JOIN districts d ON e.district_id = d.district_id
    LEFT JOIN boroughs b ON d.borough_id = b.borough_id
    JOIN system_labels l_gender ON r.gender_id = l_gender.label_id
    JOIN system_labels l_edu ON r.education_level_id = l_edu.label_id
    JOIN system_labels l_eth ON r.ethnicity_id = l_eth.label_id
    JOIN system_labels l_rel ON r.religion_id = l_rel.label_id
    LEFT JOIN establishments e_church ON r.church_id = e_church.establishment_id
    LEFT JOIN establishments e_pub ON r.local_pub_id = e_pub.establishment_id;

CREATE VIEW
    IF NOT EXISTS v_households_overview AS
SELECT
    h.household_id,
    h.head_resident_id,
    b.display_name AS borough_name,
    b.borough_id,
    d.display_name AS district_name,
    d.district_id,
    l_res.code AS residence_type_code,
    l_res.title AS residence_type_title,
    h.wealth_bracket_id,
    r_head.local_pub_id AS local_pub_id,
    e_pub.name AS local_pub_name,
    r_head.church_id AS church_id,
    e_church.name AS church_name,
    l_eth.title AS dominant_ethnicity_title,
    l_rel.title AS dominant_religion_title
FROM
    households h
    JOIN establishments e ON h.establishment_id = e.establishment_id
    JOIN districts d ON e.district_id = d.district_id
    LEFT JOIN boroughs b ON d.borough_id = b.borough_id
    JOIN system_labels l_res ON h.residence_type_id = l_res.label_id
    JOIN system_labels l_eth ON h.ethnicity_id = l_eth.label_id
    JOIN system_labels l_rel ON h.religion_id = l_rel.label_id
    LEFT JOIN residents r_head ON h.head_resident_id = r_head.resident_id
    LEFT JOIN establishments e_pub ON r_head.local_pub_id = e_pub.establishment_id
    LEFT JOIN establishments e_church ON r_head.church_id = e_church.establishment_id;

CREATE VIEW
    IF NOT EXISTS v_active_contracts AS
SELECT
    c.contract_id,
    c.resident_id,
    r.first_name || ' ' || r.current_surname AS full_name,
    e_home.district_id AS home_district_id,
    c.employer_org_id,
    c.employer_establishment_id,
    COALESCE(o.display_name, e_work.name, '') AS employer_name,
    l_class.code AS contract_class_code,
    l_class.title AS contract_class_title,
    l_type.code AS contract_type_code,
    l_type.title AS contract_type_title,
    l_role.code AS role_title_code,
    l_role.title AS role_title,
    l_sched.code AS schedule_window_code,
    l_sched.title AS schedule_title,
    c.weekly_hours,
    c.compensation_rate,
    date (
        (
            SELECT
                value
            FROM
                world_metadata
            WHERE
                key = 'epoch_date'
        ),
        '+' || c.valid_from || ' days'
    ) AS contract_start_date
FROM
    livelihood_contracts c
    JOIN residents r ON c.resident_id = r.resident_id
    JOIN households h ON r.household_id = h.household_id
    JOIN establishments e_home ON h.establishment_id = e_home.establishment_id
    LEFT JOIN organizations o ON c.employer_org_id = o.org_id
    LEFT JOIN establishments e_work ON c.employer_establishment_id = e_work.establishment_id
    JOIN system_labels l_class ON c.contract_class_id = l_class.label_id
    JOIN system_labels l_type ON c.contract_type_id = l_type.label_id
    JOIN system_labels l_role ON c.role_title_id = l_role.label_id
    JOIN system_labels l_sched ON c.schedule_window_id = l_sched.label_id
WHERE
    c.valid_to IS NULL
    AND r.dod IS NULL;

CREATE VIEW
    IF NOT EXISTS v_establishments_overview AS
SELECT
    e.establishment_id,
    b.display_name AS borough_name,
    d.borough_id,
    d.display_name AS district_name,
    e.district_id,
    e.name,
    e.owner_org_id,
    o.display_name AS owner_org_name,
    e.is_vacant,
    l_cat.code AS category_code,
    l_cat.title AS category_title,
    e.capacity,
    COUNT(c.contract_id) AS active_contract_count
FROM
    establishments e
    JOIN districts d ON d.district_id = e.district_id
    LEFT JOIN boroughs b ON b.borough_id = d.borough_id
    LEFT JOIN organizations o ON e.owner_org_id = o.org_id
    JOIN system_labels l_cat ON e.category_id = l_cat.label_id
    LEFT JOIN livelihood_contracts c ON e.establishment_id = c.employer_establishment_id
    AND c.valid_to IS NULL
WHERE
    e.valid_to IS NULL
GROUP BY
    e.establishment_id;

CREATE VIEW
    IF NOT EXISTS v_composite_bonds AS
SELECT
    r.from_resident_id,
    r.to_resident_id,
    COUNT(*) AS shared_ties_count,
    SUM(r.affinity_score) AS total_affinity,
    GROUP_CONCAT (l.title, ', ') AS ties_summary
FROM
    social_relationships r
    JOIN system_labels l ON r.relationship_type_id = l.label_id
WHERE
    r.valid_to IS NULL
GROUP BY
    r.from_resident_id,
    r.to_resident_id;

CREATE VIEW
    IF NOT EXISTS v_workplace_jobs AS
SELECT
    w.slot_id,
    e.establishment_id,
    e.name AS establishment_name,
    e.owner_org_id,
    o.display_name AS owner_org_name,
    b.display_name AS borough_name,
    d.borough_id,
    d.display_name AS district_name,
    e.district_id,
    l_sec.code AS sector_category_code,
    l_sec.title AS sector_category_title,
    l_rtit.code AS role_title_code,
    l_rtit.title AS role_title,
    l_conc.code AS contract_class_code,
    l_conc.title AS contract_class_title,
    l_cont.code AS contract_type_code,
    l_cont.title AS contract_type_title,
    l_medu.code AS minimum_education_code,
    l_medu.title AS minimum_education_title,
    l_shwi.code AS schedule_window_code,
    l_shwi.title AS schedule_window_title,
    w.weekly_hours,
    w.hourly_rate,
    w.is_field_worker,
    w.is_filled,
    w.active_resident_id,
    r.first_name || ' ' || r.current_surname AS active_worker_name,
    date (
        (
            SELECT
                value
            FROM
                world_metadata
            WHERE
                key = 'epoch_date'
        ),
        '+' || w.valid_from || ' days'
    ) AS slot_created_date
FROM
    workplace_job_slots w
    JOIN establishments e ON w.establishment_id = e.establishment_id
    LEFT JOIN organizations o ON e.owner_org_id = o.org_id
    JOIN districts d ON e.district_id = d.district_id
    LEFT JOIN boroughs b ON d.borough_id = b.borough_id
    JOIN system_labels l_sec ON w.sector_category_id = l_sec.label_id
    JOIN system_labels l_rtit ON w.role_title_id = l_rtit.label_id
    JOIN system_labels l_conc ON w.contract_class_id = l_conc.label_id
    JOIN system_labels l_cont ON w.contract_type_id = l_cont.label_id
    JOIN system_labels l_medu ON w.min_education_level_id = l_medu.label_id
    JOIN system_labels l_shwi ON w.schedule_window_id = l_shwi.label_id
    LEFT JOIN residents r ON w.active_resident_id = r.resident_id
WHERE
    w.valid_to IS NULL;