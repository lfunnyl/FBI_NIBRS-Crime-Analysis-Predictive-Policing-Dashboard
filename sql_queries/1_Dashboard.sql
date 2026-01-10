/* FBI Dashboard Data Source - v5 (Silah Türleri Eklendi) */
CREATE OR REPLACE VIEW `fbi-crimes-eda.analytics_mart.anasayfa` AS
/* FBI Dashboard Data Source - v6 (FINAL - Tüm Alanlar Dahil) */

WITH 
-- 1. Mülk Kaybı
Property_Stats AS (
    SELECT 
        p.incident_id,
        SUM(pd.property_value) AS total_property_loss
    FROM `fbi-crimes-eda.fbi_nibrs_external.dolthub_fbi-nibrs_main_nibrs_property` p
    JOIN `fbi-crimes-eda.fbi_nibrs_external.dolthub_fbi-nibrs_main_nibrs_property_desc` pd 
      ON p.property_id = pd.property_id
    GROUP BY p.incident_id
),

-- 2. Mağdur İstatistikleri (Yaş Grubu ve Irk Eklendi)
Victim_Stats AS (
    SELECT 
        v.incident_id,
        AVG(CASE WHEN v.age_num BETWEEN 1 AND 99 THEN v.age_num ELSE NULL END) AS avg_victim_age,
        
        -- YAŞ KATEGORİSİ (Reşit / Reşit Olmayan)
        CASE 
            WHEN MIN(CASE WHEN v.age_num BETWEEN 0 AND 99 THEN v.age_num END) < 18 THEN 'Reşit Olmayan'
            WHEN MIN(CASE WHEN v.age_num BETWEEN 0 AND 99 THEN v.age_num END) >= 18 THEN 'Reşit'
            ELSE 'Bilinmiyor'
        END AS victim_age_group,
        
        -- IRK BİLGİSİ
        STRING_AGG(DISTINCT rr.race_desc, ', ') AS victim_races
        
    FROM `fbi-crimes-eda.fbi_nibrs_external.dolthub_fbi-nibrs_main_nibrs_victim` v
    LEFT JOIN `fbi-crimes-eda.fbi_nibrs_external.dolthub_fbi-nibrs_main_ref_race` rr 
        ON v.race_id = rr.race_id
    GROUP BY v.incident_id
),

-- 3. Suçlu İstatistikleri (Yaş Grubu ve Irk Eklendi)
Offender_Stats AS (
    SELECT 
        o.incident_id,
        AVG(CASE WHEN o.age_num BETWEEN 1 AND 99 THEN o.age_num ELSE NULL END) AS avg_offender_age,
        
        -- YAŞ KATEGORİSİ
        CASE 
            WHEN MIN(CASE WHEN o.age_num BETWEEN 0 AND 99 THEN o.age_num END) < 18 THEN 'Reşit Olmayan'
            WHEN MIN(CASE WHEN o.age_num BETWEEN 0 AND 99 THEN o.age_num END) >= 18 THEN 'Reşit'
            ELSE 'Bilinmiyor'
        END AS offender_age_group,
        
        -- IRK BİLGİSİ
        STRING_AGG(DISTINCT rr.race_desc, ', ') AS offender_races

    FROM `fbi-crimes-eda.fbi_nibrs_external.dolthub_fbi-nibrs_main_nibrs_offender` o
    LEFT JOIN `fbi-crimes-eda.fbi_nibrs_external.dolthub_fbi-nibrs_main_ref_race` rr 
        ON o.race_id = rr.race_id
    GROUP BY o.incident_id
),

-- 4. Tutuklama Bilgileri
Arrest_Stats AS (
    SELECT 
        incident_id,
        COUNT(arrestee_id) AS total_arrests,
        MIN(arrest_date) AS first_arrest_date
    FROM `fbi-crimes-eda.fbi_nibrs_external.dolthub_fbi-nibrs_main_nibrs_arrestee`
    GROUP BY incident_id
),

-- 5. Silah Detayları (İsim ve Bayrak)
Weapon_Stats AS (
    SELECT
        w.offense_id,
        MAX(CASE WHEN wt.weapon_code NOT IN ('__', '99', '95') THEN 1 ELSE 0 END) as has_weapon,
        STRING_AGG(DISTINCT wt.weapon_name, ', ') as weapon_description
    FROM `fbi-crimes-eda.fbi_nibrs_external.dolthub_fbi-nibrs_main_nibrs_weapon` w
    LEFT JOIN `fbi-crimes-eda.fbi_nibrs_external.dolthub_fbi-nibrs_main_nibrs_weapon_type` wt
      ON w.weapon_id = wt.weapon_id
    GROUP BY w.offense_id
)

-- ANA SORGU
SELECT 
    inc.incident_id,
    inc.data_year, 
    inc.incident_date,
    inc.incident_hour,
    
    rs.state_name, 
    ag.agency_name, 
    ag.population, 
    
    oft.offense_name, 
    oft.offense_category_name,
    oft.crime_against,
    
    -- EKSİK OLAN ALANLAR GERİ GELDİ:
    vic.victim_age_group,   -- Filtre için
    vic.victim_races,       -- Filtre için
    off.offender_age_group, -- Filtre için
    off.offender_races,     -- Filtre için
    
    -- Silah Açıklaması
    COALESCE(wep.weapon_description, 'Bilinmiyor/Yok') AS weapon_type_desc,
    
    -- Yeni Metrik Bayrakları
    CASE WHEN oft.crime_against = 'Person' THEN 1 ELSE 0 END AS is_violent_crime,
    CASE WHEN inc.incident_hour >= 22 OR inc.incident_hour <= 6 THEN 1 ELSE 0 END AS is_night_crime,
    COALESCE(wep.has_weapon, 0) AS is_armed_crime,

    -- Temel Metrikler
    COALESCE(prop.total_property_loss, 0) AS metric_property_loss, 
    vic.avg_victim_age, 
    off.avg_offender_age, 
    COALESCE(arr.total_arrests, 0) AS metric_total_arrests, 
    
    DATE_DIFF(DATE(arr.first_arrest_date), DATE(inc.incident_date), DAY) AS time_to_arrest_days, 
    
    CASE 
        WHEN COALESCE(arr.total_arrests, 0) > 0 THEN 1 
        WHEN inc.cleared_except_date IS NOT NULL THEN 1 
        ELSE 0 
    END AS is_solved,
    
    ag.icpsr_lat AS latitude,
    ag.icpsr_lng AS longitude

FROM `fbi-crimes-eda.fbi_nibrs_external.dolthub_fbi-nibrs_main_nibrs_incident` AS inc

JOIN `fbi-crimes-eda.analytics_mart.dolthub_fbi-nibrs_main_cde_agencies` AS ag 
    ON inc.agency_id = ag.agency_id AND inc.data_year = ag.data_year 
JOIN `fbi-crimes-eda.fbi_nibrs_external.dolthub_fbi-nibrs_main_ref_state` AS rs
    ON ag.state_id = rs.state_id

JOIN `fbi-crimes-eda.fbi_nibrs_external.dolthub_fbi-nibrs_main_nibrs_offense` AS off_link 
    ON inc.incident_id = off_link.incident_id
JOIN `fbi-crimes-eda.fbi_nibrs_external.dolthub_fbi-nibrs_main_nibrs_offense_type` AS oft 
    ON off_link.offense_type_id = oft.offense_type_id

-- İstatistik Bağlantıları
LEFT JOIN Property_Stats prop ON inc.incident_id = prop.incident_id
LEFT JOIN Victim_Stats vic ON inc.incident_id = vic.incident_id
LEFT JOIN Offender_Stats off ON inc.incident_id = off.incident_id
LEFT JOIN Arrest_Stats arr ON inc.incident_id = arr.incident_id
LEFT JOIN Weapon_Stats wep ON off_link.offense_id = wep.offense_id;
