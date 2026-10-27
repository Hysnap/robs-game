-- Read-only SQL reference for systems/city_auditor.gd.
-- Do not add INSERT, UPDATE, DELETE, DROP, ALTER, or CREATE statements here.

-- QUERY: entity_counts
SELECT 'boroughs' AS entity, COUNT(*) AS count FROM boroughs
UNION ALL SELECT 'districts', COUNT(*) FROM districts
UNION ALL SELECT 'establishments', COUNT(*) FROM establishments
UNION ALL SELECT 'households', COUNT(*) FROM households
UNION ALL SELECT 'residents', COUNT(*) FROM residents
UNION ALL SELECT 'contracts', COUNT(*) FROM livelihood_contracts
UNION ALL SELECT 'relationships', COUNT(*) FROM social_relationships;

-- QUERY: district_distribution
SELECT
    district_id,
    district_name,
    total_households,
    active_living_population AS active_population,
    formally_employed_count,
    street_informal_count,
    incarcerated_count
FROM v_district_census
ORDER BY active_population DESC, district_id ASC;

-- QUERY: borough_distribution
SELECT
    borough_id,
    borough_name,
    total_districts,
    total_households,
    active_living_population AS active_population,
    formally_employed_count,
    street_informal_count,
    incarcerated_count
FROM v_borough_census
ORDER BY active_population DESC, borough_id ASC;

-- QUERY: establishment_categories
SELECT
    l.code AS category,
    COUNT(*) AS establishment_count,
    SUM(e.capacity) AS total_capacity,
    SUM(CASE WHEN e.is_vacant = 1 THEN 1 ELSE 0 END) AS vacant_count
FROM establishments e
JOIN system_labels l ON e.category_id = l.label_id
GROUP BY l.code
ORDER BY establishment_count DESC, category ASC;

-- QUERY: employment_classes
SELECT
    l.code AS contract_class,
    COUNT(*) AS contract_count,
    ROUND(AVG(c.weekly_hours), 2) AS average_weekly_hours,
    ROUND(AVG(c.compensation_rate), 2) AS average_compensation_rate
FROM livelihood_contracts c
JOIN system_labels l ON c.contract_class_id = l.label_id
WHERE c.valid_to IS NULL
GROUP BY l.code
ORDER BY contract_count DESC, contract_class ASC;

-- QUERY: social_degree
SELECT
    degree_bucket,
    COUNT(*) AS resident_count
FROM (
    SELECT
        r.resident_id,
        CASE
            WHEN COUNT(sr.relationship_id) = 0 THEN '0'
            WHEN COUNT(sr.relationship_id) BETWEEN 1 AND 2 THEN '1-2'
            WHEN COUNT(sr.relationship_id) BETWEEN 3 AND 5 THEN '3-5'
            WHEN COUNT(sr.relationship_id) BETWEEN 6 AND 10 THEN '6-10'
            ELSE '11+'
        END AS degree_bucket
    FROM residents r
    LEFT JOIN social_relationships sr
        ON sr.from_resident_id = r.resident_id
        OR sr.to_resident_id = r.resident_id
    WHERE r.dod IS NULL
    GROUP BY r.resident_id
)
GROUP BY degree_bucket
ORDER BY CASE degree_bucket
    WHEN '0' THEN 0
    WHEN '1-2' THEN 1
    WHEN '3-5' THEN 2
    WHEN '6-10' THEN 3
    ELSE 4
END;

-- QUERY: integrity_checks
SELECT
    'orphan_establishments' AS check_name,
    COUNT(*) AS failures
FROM establishments e
LEFT JOIN districts d ON d.district_id = e.district_id
WHERE d.district_id IS NULL
UNION ALL
SELECT
    'orphan_households',
    COUNT(*)
FROM households h
LEFT JOIN establishments e ON e.establishment_id = h.establishment_id
WHERE e.establishment_id IS NULL
UNION ALL
SELECT
    'orphan_residents',
    COUNT(*)
FROM residents r
LEFT JOIN households h ON h.household_id = r.household_id
WHERE h.household_id IS NULL
UNION ALL
SELECT
    'orphan_relationships',
    COUNT(*)
FROM social_relationships sr
LEFT JOIN residents rf ON rf.resident_id = sr.from_resident_id
LEFT JOIN residents rt ON rt.resident_id = sr.to_resident_id
WHERE rf.resident_id IS NULL OR rt.resident_id IS NULL
UNION ALL
SELECT
    'orphan_contracts',
    COUNT(*)
FROM livelihood_contracts c
LEFT JOIN residents r ON r.resident_id = c.resident_id
WHERE r.resident_id IS NULL;

-- QUERY: district_capacity
SELECT
    d.district_id,
    d.display_name AS district_name,
    COUNT(DISTINCT CASE WHEN r.dod IS NULL THEN r.resident_id END) AS active_population,
    COALESCE(SUM(
        CASE
            WHEN l.code IN ('RESIDENTIAL_UNIT', 'RESIDENTIAL') THEN e.capacity
            ELSE 0
        END
    ), 0) AS residential_capacity
FROM districts d
LEFT JOIN establishments e ON e.district_id = d.district_id
LEFT JOIN system_labels l ON l.label_id = e.category_id
LEFT JOIN households h ON h.establishment_id = e.establishment_id
LEFT JOIN residents r ON r.household_id = h.household_id
GROUP BY d.district_id, d.display_name
ORDER BY d.district_id ASC;
