-- res://data_modules/core/schema/views/101_census_views.sql
-- Tier 101: District and Borough Demographic & Labor Census Views
CREATE VIEW
    IF NOT EXISTS v_district_census AS
SELECT
    d.district_id,
    d.display_name AS district_name,
    d.borough_id,
    b.display_name AS borough_name,
    -- Demographics
    COUNT(DISTINCT r.resident_id) AS total_residents,
    COUNT(DISTINCT r.household_id) AS total_households,
    COUNT(
        DISTINCT CASE
            WHEN r.dod IS NULL THEN r.resident_id
        END
    ) AS active_population,
    -- Dynamic Age Cohorts (Computed against world_metadata without hardcoded ages)
    COUNT(
        DISTINCT CASE
            WHEN r.dod IS NULL
            AND (
                (
                    CAST(
                        (
                            SELECT
                                value
                            FROM
                                world_metadata
                            WHERE
                                key = 'current_sim_day'
                        ) AS REAL
                    ) - r.dob
                ) / 365.25
            ) < CAST(
                (
                    SELECT
                        value
                    FROM
                        world_metadata
                    WHERE
                        key = 'min_working_age'
                ) AS REAL
            ) THEN r.resident_id
        END
    ) AS children_under_working_age_count,
    COUNT(
        DISTINCT CASE
            WHEN r.dod IS NULL
            AND (
                (
                    CAST(
                        (
                            SELECT
                                value
                            FROM
                                world_metadata
                            WHERE
                                key = 'current_sim_day'
                        ) AS REAL
                    ) - r.dob
                ) / 365.25
            ) >= CAST(
                (
                    SELECT
                        value
                    FROM
                        world_metadata
                    WHERE
                        key = 'min_working_age'
                ) AS REAL
            )
            AND (
                (
                    CAST(
                        (
                            SELECT
                                value
                            FROM
                                world_metadata
                            WHERE
                                key = 'current_sim_day'
                        ) AS REAL
                    ) - r.dob
                ) / 365.25
            ) < CASE
                WHEN l_gender.code = 'FEMALE' THEN CAST(
                    (
                        SELECT
                            value
                        FROM
                            world_metadata
                        WHERE
                            key = 'pension_age_female'
                    ) AS REAL
                )
                ELSE CAST(
                    (
                        SELECT
                            value
                        FROM
                            world_metadata
                        WHERE
                            key = 'pension_age_male'
                    ) AS REAL
                )
            END THEN r.resident_id
        END
    ) AS working_age_population,
    COUNT(
        DISTINCT CASE
            WHEN r.dod IS NULL
            AND (
                (
                    CAST(
                        (
                            SELECT
                                value
                            FROM
                                world_metadata
                            WHERE
                                key = 'current_sim_day'
                        ) AS REAL
                    ) - r.dob
                ) / 365.25
            ) >= CASE
                WHEN l_gender.code = 'FEMALE' THEN CAST(
                    (
                        SELECT
                            value
                        FROM
                            world_metadata
                        WHERE
                            key = 'pension_age_female'
                    ) AS REAL
                )
                ELSE CAST(
                    (
                        SELECT
                            value
                        FROM
                            world_metadata
                        WHERE
                            key = 'pension_age_male'
                    ) AS REAL
                )
            END THEN r.resident_id
        END
    ) AS pensioners_count,
    -- Housing Tenancy vs. Active Domestic Households
    COUNT(DISTINCT h.household_id) AS total_active_households,
    COUNT(
        DISTINCT CASE
            WHEN l_cat.code = 'RESIDENTIAL_UNIT' THEN e.establishment_id
        END
    ) AS total_residential_units,
    COUNT(
        DISTINCT CASE
            WHEN l_cat.code = 'RESIDENTIAL_UNIT'
            AND e.is_vacant = 0 THEN e.establishment_id
        END
    ) AS occupied_residential_units,
    COUNT(
        DISTINCT CASE
            WHEN l_cat.code = 'RESIDENTIAL_UNIT'
            AND e.is_vacant != 0 THEN e.establishment_id
        END
    ) AS vacant_residential_units,
    ROUND(
        CAST(
            COUNT(
                DISTINCT CASE
                    WHEN l_cat.code = 'RESIDENTIAL_UNIT'
                    AND e.is_vacant = 0 THEN e.establishment_id
                END
            ) AS REAL
        ) / MAX(
            1.0,
            CAST(
                COUNT(
                    DISTINCT CASE
                        WHEN l_cat.code = 'RESIDENTIAL_UNIT' THEN e.establishment_id
                    END
                ) AS REAL
            )
        ),
        3
    ) AS residential_occupancy_rate,
    ROUND(
        CAST(
            COUNT(
                DISTINCT CASE
                    WHEN r.dod IS NULL THEN r.resident_id
                END
            ) AS REAL
        ) / MAX(
            1.0,
            CAST(
                COUNT(
                    DISTINCT CASE
                        WHEN l_cat.code = 'RESIDENTIAL_UNIT'
                        AND e.is_vacant = 0 THEN e.establishment_id
                    END
                ) AS REAL
            )
        ),
        2
    ) AS avg_residents_per_occupied_dwelling,
    ROUND(
        CAST(
            COUNT(
                DISTINCT CASE
                    WHEN r.dod IS NULL THEN r.resident_id
                END
            ) AS REAL
        ) / MAX(1.0, CAST(COUNT(DISTINCT h.household_id) AS REAL)),
        2
    ) AS avg_household_size,
    -- Commercial & Industrial Units
    COUNT(
        DISTINCT CASE
            WHEN l_cat.code = 'COMMERCIAL' THEN e.establishment_id
        END
    ) AS total_commercial_units,
    COUNT(
        DISTINCT CASE
            WHEN l_cat.code = 'COMMERCIAL'
            AND e.is_vacant != 0 THEN e.establishment_id
        END
    ) AS vacant_commercial_units,
    COUNT(
        DISTINCT CASE
            WHEN l_cat.code = 'INDUSTRIAL' THEN e.establishment_id
        END
    ) AS total_industrial_units,
    COUNT(
        DISTINCT CASE
            WHEN l_cat.code = 'INDUSTRIAL'
            AND e.is_vacant != 0 THEN e.establishment_id
        END
    ) AS vacant_industrial_units,
    COUNT(
        DISTINCT CASE
            WHEN l_cat.code NOT IN ('RESIDENTIAL_UNIT', 'COMMERCIAL', 'INDUSTRIAL') THEN e.establishment_id
        END
    ) AS civic_anchors_count,
    -- Non-Exclusive Overlapping Labor Categories
    COUNT(
        DISTINCT CASE
            WHEN r.dod IS NULL
            AND c.contract_id IS NOT NULL
            AND l_class.code = 'FORMAL_LEGAL' THEN r.resident_id
        END
    ) AS formally_employed_count,
    COUNT(
        DISTINCT CASE
            WHEN r.dod IS NULL
            AND c.contract_id IS NOT NULL
            AND l_class.code IN ('INFORMAL_GREY', 'ILLICIT_SYNDICATE') THEN r.resident_id
        END
    ) AS street_informal_count,
    COUNT(
        DISTINCT CASE
            WHEN r.dod IS NULL
            AND c.contract_id IS NOT NULL
            AND l_class.code = 'CUSTODIAL_INMATE' THEN r.resident_id
        END
    ) AS incarcerated_count,
    COUNT(
        DISTINCT CASE
            WHEN r.dod IS NULL
            AND (
                (
                    CAST(
                        (
                            SELECT
                                value
                            FROM
                                world_metadata
                            WHERE
                                key = 'current_sim_day'
                        ) AS REAL
                    ) - r.dob
                ) / 365.25
            ) >= CAST(
                (
                    SELECT
                        value
                    FROM
                        world_metadata
                    WHERE
                        key = 'min_working_age'
                ) AS REAL
            )
            AND (
                (
                    CAST(
                        (
                            SELECT
                                value
                            FROM
                                world_metadata
                            WHERE
                                key = 'current_sim_day'
                        ) AS REAL
                    ) - r.dob
                ) / 365.25
            ) < CASE
                WHEN l_gender.code = 'FEMALE' THEN CAST(
                    (
                        SELECT
                            value
                        FROM
                            world_metadata
                        WHERE
                            key = 'pension_age_female'
                    ) AS REAL
                )
                ELSE CAST(
                    (
                        SELECT
                            value
                        FROM
                            world_metadata
                        WHERE
                            key = 'pension_age_male'
                    ) AS REAL
                )
            END
            AND NOT EXISTS (
                SELECT
                    1
                FROM
                    livelihood_contracts c_check
                    JOIN system_labels l_c ON c_check.contract_class_id = l_c.label_id
                WHERE
                    c_check.resident_id = r.resident_id
                    AND c_check.valid_to IS NULL
                    AND l_c.code IN ('FORMAL_LEGAL', 'CUSTODIAL_INMATE')
            ) THEN r.resident_id
        END
    ) AS unemployed_count,
    -- Sparse Measure Integration (Long Term Sick)
    COUNT(
        DISTINCT CASE
            WHEN r.dod IS NULL
            AND EXISTS (
                SELECT
                    1
                FROM
                    entity_adhoc_measures eam
                    JOIN adhoc_measure_definitions amd ON eam.measure_id = amd.measure_id
                WHERE
                    eam.entity_type = 'RESIDENT'
                    AND eam.entity_id = CAST(r.resident_id AS TEXT)
                    AND amd.code = 'LONG_TERM_SICK'
                    AND eam.num_value > 0.0
                    AND eam.valid_to IS NULL
            ) THEN r.resident_id
        END
    ) AS long_term_sick_count,
    -- Economic Context
    d.base_disposable_income
FROM
    districts d
    LEFT JOIN boroughs b ON d.borough_id = b.borough_id
    LEFT JOIN establishments e ON d.district_id = e.district_id
    LEFT JOIN system_labels l_cat ON e.category_id = l_cat.label_id
    LEFT JOIN households h ON h.establishment_id = e.establishment_id
    LEFT JOIN residents r ON h.household_id = r.household_id
    LEFT JOIN system_labels l_gender ON r.gender_id = l_gender.label_id
    LEFT JOIN livelihood_contracts c ON r.resident_id = c.resident_id
    AND c.valid_to IS NULL
    LEFT JOIN system_labels l_class ON c.contract_class_id = l_class.label_id
GROUP BY
    d.district_id,
    d.display_name,
    d.borough_id,
    b.display_name,
    d.base_disposable_income;

CREATE VIEW
    IF NOT EXISTS v_borough_census AS
SELECT
    b.borough_id,
    b.display_name AS borough_name,
    COUNT(DISTINCT d.district_id) AS total_districts,
    -- Demographics
    COUNT(DISTINCT r.resident_id) AS total_residents,
    COUNT(DISTINCT r.household_id) AS total_households,
    COUNT(
        DISTINCT CASE
            WHEN r.dod IS NULL THEN r.resident_id
        END
    ) AS active_population,
    -- Dynamic Age Cohorts
    COUNT(
        DISTINCT CASE
            WHEN r.dod IS NULL
            AND (
                (
                    CAST(
                        (
                            SELECT
                                value
                            FROM
                                world_metadata
                            WHERE
                                key = 'current_sim_day'
                        ) AS REAL
                    ) - r.dob
                ) / 365.25
            ) < CAST(
                (
                    SELECT
                        value
                    FROM
                        world_metadata
                    WHERE
                        key = 'min_working_age'
                ) AS REAL
            ) THEN r.resident_id
        END
    ) AS children_under_working_age_count,
    COUNT(
        DISTINCT CASE
            WHEN r.dod IS NULL
            AND (
                (
                    CAST(
                        (
                            SELECT
                                value
                            FROM
                                world_metadata
                            WHERE
                                key = 'current_sim_day'
                        ) AS REAL
                    ) - r.dob
                ) / 365.25
            ) >= CAST(
                (
                    SELECT
                        value
                    FROM
                        world_metadata
                    WHERE
                        key = 'min_working_age'
                ) AS REAL
            )
            AND (
                (
                    CAST(
                        (
                            SELECT
                                value
                            FROM
                                world_metadata
                            WHERE
                                key = 'current_sim_day'
                        ) AS REAL
                    ) - r.dob
                ) / 365.25
            ) < CASE
                WHEN l_gender.code = 'FEMALE' THEN CAST(
                    (
                        SELECT
                            value
                        FROM
                            world_metadata
                        WHERE
                            key = 'pension_age_female'
                    ) AS REAL
                )
                ELSE CAST(
                    (
                        SELECT
                            value
                        FROM
                            world_metadata
                        WHERE
                            key = 'pension_age_male'
                    ) AS REAL
                )
            END THEN r.resident_id
        END
    ) AS working_age_population,
    COUNT(
        DISTINCT CASE
            WHEN r.dod IS NULL
            AND (
                (
                    CAST(
                        (
                            SELECT
                                value
                            FROM
                                world_metadata
                            WHERE
                                key = 'current_sim_day'
                        ) AS REAL
                    ) - r.dob
                ) / 365.25
            ) >= CASE
                WHEN l_gender.code = 'FEMALE' THEN CAST(
                    (
                        SELECT
                            value
                        FROM
                            world_metadata
                        WHERE
                            key = 'pension_age_female'
                    ) AS REAL
                )
                ELSE CAST(
                    (
                        SELECT
                            value
                        FROM
                            world_metadata
                        WHERE
                            key = 'pension_age_male'
                    ) AS REAL
                )
            END THEN r.resident_id
        END
    ) AS pensioners_count,
    -- Housing Tenancy vs. Households
    COUNT(DISTINCT h.household_id) AS total_active_households,
    COUNT(
        DISTINCT CASE
            WHEN l_cat.code = 'RESIDENTIAL_UNIT' THEN e.establishment_id
        END
    ) AS total_residential_units,
    COUNT(
        DISTINCT CASE
            WHEN l_cat.code = 'RESIDENTIAL_UNIT'
            AND e.is_vacant = 0 THEN e.establishment_id
        END
    ) AS occupied_residential_units,
    COUNT(
        DISTINCT CASE
            WHEN l_cat.code = 'RESIDENTIAL_UNIT'
            AND e.is_vacant != 0 THEN e.establishment_id
        END
    ) AS vacant_residential_units,
    -- Commercial & Industrial Units
    COUNT(
        DISTINCT CASE
            WHEN l_cat.code = 'COMMERCIAL' THEN e.establishment_id
        END
    ) AS total_commercial_units,
    COUNT(
        DISTINCT CASE
            WHEN l_cat.code = 'COMMERCIAL'
            AND e.is_vacant != 0 THEN e.establishment_id
        END
    ) AS vacant_commercial_units,
    COUNT(
        DISTINCT CASE
            WHEN l_cat.code = 'INDUSTRIAL' THEN e.establishment_id
        END
    ) AS total_industrial_units,
    COUNT(
        DISTINCT CASE
            WHEN l_cat.code = 'INDUSTRIAL'
            AND e.is_vacant != 0 THEN e.establishment_id
        END
    ) AS vacant_industrial_units,
    -- Non-Exclusive Overlapping Labor Categories
    COUNT(
        DISTINCT CASE
            WHEN r.dod IS NULL
            AND c.contract_id IS NOT NULL
            AND l_class.code = 'FORMAL_LEGAL' THEN r.resident_id
        END
    ) AS formally_employed_count,
    COUNT(
        DISTINCT CASE
            WHEN r.dod IS NULL
            AND c.contract_id IS NOT NULL
            AND l_class.code IN ('INFORMAL_GREY', 'ILLICIT_SYNDICATE') THEN r.resident_id
        END
    ) AS street_informal_count,
    COUNT(
        DISTINCT CASE
            WHEN r.dod IS NULL
            AND c.contract_id IS NOT NULL
            AND l_class.code = 'CUSTODIAL_INMATE' THEN r.resident_id
        END
    ) AS incarcerated_count
FROM
    boroughs b
    LEFT JOIN districts d ON b.borough_id = d.borough_id
    LEFT JOIN establishments e ON d.district_id = e.district_id
    LEFT JOIN system_labels l_cat ON e.category_id = l_cat.label_id
    LEFT JOIN households h ON h.establishment_id = e.establishment_id
    LEFT JOIN residents r ON h.household_id = r.household_id
    LEFT JOIN system_labels l_gender ON r.gender_id = l_gender.label_id
    LEFT JOIN livelihood_contracts c ON r.resident_id = c.resident_id
    AND c.valid_to IS NULL
    LEFT JOIN system_labels l_class ON c.contract_class_id = l_class.label_id
GROUP BY
    b.borough_id,
    b.display_name;