CREATE OR REPLACE TABLE `fbi_nibrs_external.tahmin_raporu_tablosu` AS
SELECT
    *
FROM
  ML.PREDICT(MODEL `fbi_nibrs_external.model_is_solved_prediction`,
    (
    SELECT
        -- Orijinal Veriler (Gerçek Durum)
        CASE 
            WHEN inc.cleared_except_date IS NOT NULL THEN 1
            WHEN (SELECT COUNT(*) FROM `fbi-crimes-eda.fbi_nibrs_external.dolthub_fbi-nibrs_main_nibrs_arrestee` arr WHERE arr.incident_id = inc.incident_id) > 0 THEN 1
            ELSE 0 
        END AS gercek_durum,

        -- Raporlama için Ekstra Bilgiler
        inc.incident_id,
        ag.agency_name,
        
        -- MODEL ÖZNİTELİKLERİ (Eksiksiz)
        CAST(inc.incident_hour AS STRING) AS incident_hour_str,
        ag.population,
        ag.total_officers,
        rs.state_name,
        ot.offense_name,
        lt.location_name,
        CASE WHEN v.age_num < 18 THEN 'Minor' ELSE 'Adult' END AS victim_age_group,
        v.sex_code AS victim_sex
        
    FROM `fbi-crimes-eda.fbi_nibrs_external.dolthub_fbi-nibrs_main_nibrs_incident` inc
    JOIN `fbi-crimes-eda.fbi_nibrs_external.dolthub_fbi-nibrs_main_cde_agencies` ag ON inc.agency_id = ag.agency_id AND inc.data_year = ag.data_year
    JOIN `fbi-crimes-eda.fbi_nibrs_external.dolthub_fbi-nibrs_main_ref_state` rs ON ag.state_id = rs.state_id
    JOIN `fbi-crimes-eda.fbi_nibrs_external.dolthub_fbi-nibrs_main_nibrs_offense` off_link ON inc.incident_id = off_link.incident_id
    JOIN `fbi-crimes-eda.fbi_nibrs_external.dolthub_fbi-nibrs_main_nibrs_offense_type` ot ON off_link.offense_type_id = ot.offense_type_id
    JOIN `fbi-crimes-eda.fbi_nibrs_external.dolthub_fbi-nibrs_main_nibrs_location_type` lt ON off_link.location_id = lt.location_id
    LEFT JOIN `fbi-crimes-eda.fbi_nibrs_external.dolthub_fbi-nibrs_main_nibrs_victim` v ON inc.incident_id = v.incident_id

    WHERE 
        inc.data_year BETWEEN 2013 AND 2015
        AND v.sex_code IN ('M', 'F')
    -- LIMIT KALDIRILDI! Tüm veriyi analiz ediyoruz.
    ));
