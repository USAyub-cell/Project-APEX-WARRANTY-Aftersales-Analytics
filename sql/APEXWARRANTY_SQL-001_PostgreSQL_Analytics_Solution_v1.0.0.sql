-- =============================================================================
-- Project APEX-WARRANTY
-- PostgreSQL Analytics Solution v1.0.0
-- Purpose: Synthetic Aftersales Warranty Audit, Governance & Performance Capstone
-- IMPORTANT: This is a professional capstone consulting simulation.
-- It contains no confidential Bentley, VW Group, retailer, customer or warranty data.
-- Brand names are used only as synthetic analytical labels.
-- =============================================================================
-- Recommended environment: PostgreSQL 15+
--
-- HOW TO LOAD:
-- 1) Open APEXWARRANTY_D-001_Raw_Aftersales_Warranty_Audit_Data_v1.0.0.xlsx
-- 2) Export each raw sheet to UTF-8 CSV with the same sheet name.
-- 3) Create the staging tables below.
-- 4) Use \copy commands (examples below) from psql.
-- 5) Run the cleaning, governance, KPI, risk and insight queries.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS apex_warranty;
SET search_path TO apex_warranty;

-- -----------------------------------------------------------------------------
-- 1. STAGING TABLES
-- Raw data is intentionally loaded mainly as TEXT so validation happens before
-- business typing. This protects the analytical model from bad raw values.
-- -----------------------------------------------------------------------------

DROP TABLE IF EXISTS stg_retailer CASCADE;
CREATE TABLE stg_retailer (
    retailer_id text,
    retailer_name text,
    brand text,
    region text,
    country text,
    city text,
    importer_group text,
    active_flag text
);

DROP TABLE IF EXISTS stg_vehicle_program CASCADE;
CREATE TABLE stg_vehicle_program (
    vehicle_program_id text,
    brand text,
    model_family text,
    powertrain text,
    launch_year text,
    warranty_months text,
    warranty_km text
);

DROP TABLE IF EXISTS stg_vehicle_sales CASCADE;
CREATE TABLE stg_vehicle_sales (
    sales_txn_id text,
    sale_month text,
    retailer_id text,
    brand text,
    vehicle_program_id text,
    units_sold text,
    sales_revenue_gbp text,
    warranty_reserve_gbp text,
    market_region text,
    country text,
    source_system text
);

DROP TABLE IF EXISTS stg_warranty_claim CASCADE;
CREATE TABLE stg_warranty_claim (
    claim_id text,
    claim_date text,
    repair_date text,
    close_date text,
    retailer_id text,
    retailer_name text,
    brand text,
    vehicle_program_id text,
    vin text,
    model_year text,
    mileage_km text,
    claim_type text,
    failure_category text,
    part_code text,
    labor_hours text,
    labor_rate_gbp text,
    parts_cost_gbp text,
    calculated_claim_cost_gbp text,
    approved_amount_gbp text,
    claim_status text,
    documentation_complete text,
    days_to_close text,
    customer_satisfaction_score text,
    risk_score text,
    risk_band text,
    source_system text
);

DROP TABLE IF EXISTS stg_retailer_audit CASCADE;
CREATE TABLE stg_retailer_audit (
    audit_id text,
    retailer_id text,
    brand text,
    region text,
    country text,
    audit_type text,
    planned_date text,
    completed_date text,
    report_issued_date text,
    audit_status text,
    sample_claims text,
    compliance_score_pct text,
    major_findings text,
    minor_findings text,
    total_findings text,
    recovery_value_gbp text,
    training_required text,
    lead_auditor text,
    stakeholder_group text,
    source_system text
);

DROP TABLE IF EXISTS stg_improvement_action CASCADE;
CREATE TABLE stg_improvement_action (
    action_id text,
    audit_id text,
    retailer_id text,
    action_category text,
    action_description text,
    owner_role text,
    due_date text,
    closed_date text,
    action_status text,
    training_action_flag text,
    priority text
);

-- Example psql load commands: edit paths before running.
-- \copy stg_retailer FROM 'Retailer_Master_Raw.csv' CSV HEADER ENCODING 'UTF8';
-- \copy stg_vehicle_program FROM 'Vehicle_Programs_Raw.csv' CSV HEADER ENCODING 'UTF8';
-- \copy stg_vehicle_sales FROM 'Vehicle_Sales_Raw.csv' CSV HEADER ENCODING 'UTF8';
-- \copy stg_warranty_claim FROM 'Warranty_Claims_Raw.csv' CSV HEADER ENCODING 'UTF8';
-- \copy stg_retailer_audit FROM 'Retailer_Audits_Raw.csv' CSV HEADER ENCODING 'UTF8';
-- \copy stg_improvement_action FROM 'Training_Actions_Raw.csv' CSV HEADER ENCODING 'UTF8';

-- -----------------------------------------------------------------------------
-- 2. DATA PROFILING / AUDIT TESTS
-- Run these BEFORE cleaning. They demonstrate governance thinking.
-- -----------------------------------------------------------------------------

-- 2.1 Duplicate claim business keys
SELECT claim_id, COUNT(*) AS row_count
FROM stg_warranty_claim
GROUP BY claim_id
HAVING COUNT(*) > 1
ORDER BY row_count DESC, claim_id;

-- 2.2 Missing / invalid VINs
SELECT
    COUNT(*) FILTER (WHERE NULLIF(TRIM(vin),'') IS NULL) AS missing_vin,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(vin),'') IS NOT NULL AND LENGTH(TRIM(vin)) <> 17) AS invalid_vin_length
FROM stg_warranty_claim;

-- 2.3 Missing retailer keys
SELECT COUNT(*) AS missing_retailer_id
FROM stg_warranty_claim
WHERE NULLIF(TRIM(retailer_id),'') IS NULL;

-- 2.4 Non-governed brand values
SELECT brand, COUNT(*) AS rows
FROM stg_warranty_claim
GROUP BY brand
ORDER BY rows DESC;

-- 2.5 Negative numeric values
SELECT
    COUNT(*) FILTER (WHERE NULLIF(mileage_km,'')::numeric < 0) AS negative_mileage_rows,
    COUNT(*) FILTER (WHERE NULLIF(parts_cost_gbp,'')::numeric < 0) AS negative_parts_cost_rows
FROM stg_warranty_claim;

-- 2.6 Raw cost-reconciliation failures
SELECT COUNT(*) AS mismatched_claim_cost_rows
FROM stg_warranty_claim
WHERE ABS(
    NULLIF(calculated_claim_cost_gbp,'')::numeric
    - (
        NULLIF(parts_cost_gbp,'')::numeric
        + NULLIF(labor_hours,'')::numeric * NULLIF(labor_rate_gbp,'')::numeric
      )
) > 1;

-- 2.7 Audit scores outside valid range
SELECT audit_id, retailer_id, compliance_score_pct
FROM stg_retailer_audit
WHERE NULLIF(compliance_score_pct,'')::numeric NOT BETWEEN 0 AND 100;

-- -----------------------------------------------------------------------------
-- 3. GOVERNED DIMENSIONS
-- -----------------------------------------------------------------------------

DROP TABLE IF EXISTS dim_retailer CASCADE;
CREATE TABLE dim_retailer AS
SELECT DISTINCT
    TRIM(retailer_id) AS retailer_id,
    TRIM(retailer_name) AS retailer_name,
    CASE
        WHEN regexp_replace(lower(trim(brand)), '\.', '', 'g') IN ('bentley','bentley motors') THEN 'Bentley'
        WHEN regexp_replace(lower(trim(brand)), '\.', '', 'g') = 'audi' THEN 'Audi'
        WHEN regexp_replace(lower(trim(brand)), '\.', '', 'g') = 'porsche' THEN 'Porsche'
        WHEN regexp_replace(lower(trim(brand)), '\.', '', 'g') IN ('bmw','bmw') THEN 'BMW'
        WHEN regexp_replace(lower(trim(brand)), '\.', '', 'g') IN ('mercedes','mercedes-benz','mercedes benz') THEN 'Mercedes-Benz'
        WHEN regexp_replace(lower(trim(brand)), '\.', '', 'g') = 'jaguar' THEN 'Jaguar'
        WHEN regexp_replace(lower(trim(brand)), '\.', '', 'g') IN ('landrover','land rover') THEN 'Land Rover'
        ELSE TRIM(brand)
    END AS brand,
    CASE WHEN lower(trim(region))='uk' THEN 'UK' ELSE initcap(trim(region)) END AS region,
    TRIM(country) AS country,
    TRIM(city) AS city,
    TRIM(importer_group) AS importer_group,
    upper(trim(active_flag)) AS active_flag
FROM stg_retailer
WHERE NULLIF(TRIM(retailer_id),'') IS NOT NULL;

ALTER TABLE dim_retailer ADD PRIMARY KEY (retailer_id);

DROP TABLE IF EXISTS dim_vehicle_program CASCADE;
CREATE TABLE dim_vehicle_program AS
SELECT DISTINCT
    TRIM(vehicle_program_id) AS vehicle_program_id,
    TRIM(brand) AS brand,
    TRIM(model_family) AS model_family,
    TRIM(powertrain) AS powertrain,
    NULLIF(launch_year,'')::int AS launch_year,
    NULLIF(warranty_months,'')::int AS warranty_months,
    NULLIF(warranty_km,'')::int AS warranty_km
FROM stg_vehicle_program;

ALTER TABLE dim_vehicle_program ADD PRIMARY KEY (vehicle_program_id);

-- -----------------------------------------------------------------------------
-- 4. CLEAN WARRANTY CLAIM FACT
-- Business rules:
-- * Deduplicate ClaimID.
-- * Standardise brand labels.
-- * Recover missing RetailerID only where retailer name maps uniquely.
-- * Recalculate governed claim cost from parts + labour.
-- * Do NOT invent invalid VIN, mileage or cost values.
-- * Retain DQ flags so users can quantify data trust.
-- -----------------------------------------------------------------------------

DROP TABLE IF EXISTS fact_warranty_claim CASCADE;
CREATE TABLE fact_warranty_claim AS
WITH retailer_name_map AS (
    SELECT retailer_name, MIN(retailer_id) AS retailer_id
    FROM dim_retailer
    GROUP BY retailer_name
    HAVING COUNT(*) = 1
),
dedup AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY claim_id ORDER BY claim_id) AS rn
    FROM stg_warranty_claim
),
typed AS (
    SELECT
        TRIM(d.claim_id) AS claim_id,
        NULLIF(d.claim_date,'')::date AS claim_date,
        NULLIF(d.repair_date,'')::date AS repair_date,
        NULLIF(d.close_date,'')::date AS close_date,
        COALESCE(NULLIF(TRIM(d.retailer_id),''), rnm.retailer_id) AS retailer_id,
        TRIM(d.retailer_name) AS retailer_name,
        CASE
            WHEN regexp_replace(lower(trim(d.brand)), '\.', '', 'g') IN ('bentley','bentley motors') THEN 'Bentley'
            WHEN regexp_replace(lower(trim(d.brand)), '\.', '', 'g') = 'audi' THEN 'Audi'
            WHEN regexp_replace(lower(trim(d.brand)), '\.', '', 'g') = 'porsche' THEN 'Porsche'
            WHEN regexp_replace(lower(trim(d.brand)), '\.', '', 'g') = 'bmw' THEN 'BMW'
            WHEN regexp_replace(lower(trim(d.brand)), '\.', '', 'g') IN ('mercedes','mercedes-benz','mercedes benz') THEN 'Mercedes-Benz'
            WHEN regexp_replace(lower(trim(d.brand)), '\.', '', 'g') = 'jaguar' THEN 'Jaguar'
            WHEN regexp_replace(lower(trim(d.brand)), '\.', '', 'g') IN ('landrover','land rover') THEN 'Land Rover'
            ELSE TRIM(d.brand)
        END AS brand,
        TRIM(d.vehicle_program_id) AS vehicle_program_id,
        NULLIF(TRIM(d.vin),'') AS vin,
        NULLIF(d.model_year,'')::int AS model_year,
        NULLIF(d.mileage_km,'')::numeric AS raw_mileage_km,
        TRIM(d.claim_type) AS claim_type,
        TRIM(d.failure_category) AS failure_category,
        TRIM(d.part_code) AS part_code,
        NULLIF(d.labor_hours,'')::numeric AS labor_hours,
        NULLIF(d.labor_rate_gbp,'')::numeric AS labor_rate_gbp,
        NULLIF(d.parts_cost_gbp,'')::numeric AS parts_cost_gbp,
        NULLIF(d.calculated_claim_cost_gbp,'')::numeric AS raw_claim_cost_gbp,
        NULLIF(d.approved_amount_gbp,'')::numeric AS approved_amount_gbp,
        TRIM(d.claim_status) AS claim_status,
        upper(trim(d.documentation_complete)) AS documentation_complete,
        NULLIF(d.days_to_close,'')::int AS days_to_close,
        NULLIF(d.customer_satisfaction_score,'')::numeric AS customer_satisfaction_score,
        NULLIF(d.risk_score,'')::int AS source_risk_score,
        TRIM(d.source_system) AS source_system
    FROM dedup d
    LEFT JOIN retailer_name_map rnm
      ON TRIM(d.retailer_name)=rnm.retailer_name
    WHERE rn=1
)
SELECT
    *,
    CASE WHEN raw_mileage_km >= 0 THEN raw_mileage_km END AS mileage_km,
    CASE
        WHEN parts_cost_gbp >= 0 AND labor_hours >= 0 AND labor_rate_gbp >= 0
        THEN ROUND(parts_cost_gbp + labor_hours * labor_rate_gbp,2)
    END AS clean_total_claim_cost_gbp,
    CASE WHEN vin IS NOT NULL AND LENGTH(vin)=17 THEN 'Y' ELSE 'N' END AS vin_valid_flag,
    CASE
        WHEN parts_cost_gbp >= 0
         AND ABS(raw_claim_cost_gbp - (parts_cost_gbp + labor_hours*labor_rate_gbp)) <= 1
        THEN 'Y' ELSE 'N'
    END AS cost_reconciled_flag,
    (
       CASE WHEN vin IS NULL OR LENGTH(vin)<>17 THEN 1 ELSE 0 END
     + CASE WHEN raw_mileage_km < 0 THEN 1 ELSE 0 END
     + CASE WHEN parts_cost_gbp < 0 THEN 1 ELSE 0 END
     + CASE WHEN ABS(raw_claim_cost_gbp - (parts_cost_gbp + labor_hours*labor_rate_gbp)) > 1 THEN 1 ELSE 0 END
     + CASE WHEN retailer_id IS NULL THEN 1 ELSE 0 END
    ) AS dq_issue_count,
    CASE WHEN
       (CASE WHEN vin IS NULL OR LENGTH(vin)<>17 THEN 1 ELSE 0 END
      + CASE WHEN raw_mileage_km < 0 THEN 1 ELSE 0 END
      + CASE WHEN parts_cost_gbp < 0 THEN 1 ELSE 0 END
      + CASE WHEN ABS(raw_claim_cost_gbp - (parts_cost_gbp + labor_hours*labor_rate_gbp)) > 1 THEN 1 ELSE 0 END
      + CASE WHEN retailer_id IS NULL THEN 1 ELSE 0 END) = 0
      THEN 'Pass' ELSE 'Remediation' END AS dq_status,
    CASE
        WHEN parts_cost_gbp >= 0
         AND labor_hours >= 0
         AND labor_rate_gbp >= 0
         AND retailer_id IS NOT NULL
        THEN 'Y' ELSE 'N'
    END AS is_analytics_valid
FROM typed;

ALTER TABLE fact_warranty_claim ADD PRIMARY KEY (claim_id);

-- -----------------------------------------------------------------------------
-- 5. CLEAN SALES, AUDIT & IMPROVEMENT FACTS
-- -----------------------------------------------------------------------------

DROP TABLE IF EXISTS fact_vehicle_sale CASCADE;
CREATE TABLE fact_vehicle_sale AS
SELECT
    TRIM(sales_txn_id) AS sales_txn_id,
    NULLIF(sale_month,'')::date AS sale_month,
    TRIM(retailer_id) AS retailer_id,
    CASE
        WHEN regexp_replace(lower(trim(brand)), '\.', '', 'g') IN ('bentley','bentley motors') THEN 'Bentley'
        WHEN regexp_replace(lower(trim(brand)), '\.', '', 'g')='audi' THEN 'Audi'
        WHEN regexp_replace(lower(trim(brand)), '\.', '', 'g')='porsche' THEN 'Porsche'
        WHEN regexp_replace(lower(trim(brand)), '\.', '', 'g')='bmw' THEN 'BMW'
        WHEN regexp_replace(lower(trim(brand)), '\.', '', 'g') IN ('mercedes','mercedes-benz','mercedes benz') THEN 'Mercedes-Benz'
        WHEN regexp_replace(lower(trim(brand)), '\.', '', 'g')='jaguar' THEN 'Jaguar'
        WHEN regexp_replace(lower(trim(brand)), '\.', '', 'g') IN ('landrover','land rover') THEN 'Land Rover'
        ELSE TRIM(brand)
    END AS brand,
    TRIM(vehicle_program_id) AS vehicle_program_id,
    NULLIF(units_sold,'')::int AS units_sold,
    NULLIF(sales_revenue_gbp,'')::numeric AS sales_revenue_gbp,
    NULLIF(warranty_reserve_gbp,'')::numeric AS warranty_reserve_gbp,
    CASE WHEN lower(trim(market_region))='uk' THEN 'UK' ELSE initcap(trim(market_region)) END AS market_region,
    TRIM(country) AS country,
    TRIM(source_system) AS source_system,
    CASE WHEN NULLIF(units_sold,'')::int > 0 THEN 'Y' ELSE 'N' END AS units_valid_flag
FROM stg_vehicle_sales;

ALTER TABLE fact_vehicle_sale ADD PRIMARY KEY (sales_txn_id);

DROP TABLE IF EXISTS fact_retailer_audit CASCADE;
CREATE TABLE fact_retailer_audit AS
SELECT
    TRIM(audit_id) AS audit_id,
    TRIM(retailer_id) AS retailer_id,
    TRIM(brand) AS brand,
    CASE WHEN lower(trim(region))='uk' THEN 'UK' ELSE initcap(trim(region)) END AS region,
    TRIM(country) AS country,
    TRIM(audit_type) AS audit_type,
    NULLIF(planned_date,'')::date AS planned_date,
    NULLIF(completed_date,'')::date AS completed_date,
    NULLIF(report_issued_date,'')::date AS report_issued_date,
    TRIM(audit_status) AS audit_status,
    NULLIF(sample_claims,'')::int AS sample_claims,
    CASE
        WHEN NULLIF(compliance_score_pct,'')::numeric BETWEEN 0 AND 100
        THEN NULLIF(compliance_score_pct,'')::numeric
    END AS compliance_score_pct,
    NULLIF(major_findings,'')::int AS major_findings,
    NULLIF(minor_findings,'')::int AS minor_findings,
    NULLIF(total_findings,'')::int AS total_findings,
    NULLIF(recovery_value_gbp,'')::numeric AS recovery_value_gbp,
    NULLIF(TRIM(training_required),'') AS training_required,
    TRIM(lead_auditor) AS lead_auditor,
    TRIM(stakeholder_group) AS stakeholder_group,
    TRIM(source_system) AS source_system,
    CASE
        WHEN NULLIF(compliance_score_pct,'') IS NULL
          OR NULLIF(compliance_score_pct,'')::numeric BETWEEN 0 AND 100
        THEN 'Y' ELSE 'N'
    END AS compliance_score_valid_flag
FROM stg_retailer_audit;

ALTER TABLE fact_retailer_audit ADD PRIMARY KEY (audit_id);

DROP TABLE IF EXISTS fact_improvement_action CASCADE;
CREATE TABLE fact_improvement_action AS
SELECT
    TRIM(action_id) AS action_id,
    TRIM(audit_id) AS audit_id,
    TRIM(retailer_id) AS retailer_id,
    TRIM(action_category) AS action_category,
    TRIM(action_description) AS action_description,
    TRIM(owner_role) AS owner_role,
    NULLIF(due_date,'')::date AS due_date,
    NULLIF(closed_date,'')::date AS closed_date,
    CASE
        WHEN lower(trim(action_status)) IN ('closed') THEN 'Closed'
        WHEN lower(trim(action_status)) IN ('closed late') THEN 'Closed Late'
        WHEN lower(replace(trim(action_status),' ',''))='overdue' THEN 'Overdue'
        WHEN lower(trim(action_status))='open' THEN 'Open'
        ELSE initcap(trim(action_status))
    END AS action_status,
    upper(trim(training_action_flag)) AS training_action_flag,
    initcap(trim(priority)) AS priority
FROM stg_improvement_action;

ALTER TABLE fact_improvement_action ADD PRIMARY KEY (action_id);

-- -----------------------------------------------------------------------------
-- 6. ANALYTICAL DATE DIMENSION
-- -----------------------------------------------------------------------------

DROP TABLE IF EXISTS dim_date CASCADE;
CREATE TABLE dim_date AS
SELECT
    d::date AS date_key,
    EXTRACT(YEAR FROM d)::int AS year,
    EXTRACT(QUARTER FROM d)::int AS quarter,
    EXTRACT(MONTH FROM d)::int AS month_number,
    TO_CHAR(d,'Mon') AS month_name,
    TO_CHAR(d,'YYYY-MM') AS year_month
FROM generate_series('2025-01-01'::date,'2026-12-31'::date,'1 day') d;

ALTER TABLE dim_date ADD PRIMARY KEY (date_key);

-- -----------------------------------------------------------------------------
-- 7. EXECUTIVE KPI QUERIES
-- -----------------------------------------------------------------------------

-- 7.1 Overall executive KPI pack
WITH claims AS (
    SELECT
        COUNT(*) FILTER (WHERE is_analytics_valid='Y') AS valid_claims,
        SUM(clean_total_claim_cost_gbp) FILTER (WHERE is_analytics_valid='Y') AS warranty_cost,
        SUM(COALESCE(approved_amount_gbp,0)) FILTER (WHERE is_analytics_valid='Y') AS approved_amount,
        AVG(days_to_close) FILTER (WHERE is_analytics_valid='Y' AND days_to_close IS NOT NULL) AS avg_days_to_close,
        COUNT(*) FILTER (WHERE is_analytics_valid='Y' AND risk_band='High') AS high_risk_claims,
        COUNT(*) FILTER (WHERE dq_status='Pass') AS dq_pass,
        COUNT(*) AS clean_claim_rows
    FROM fact_warranty_claim
),
sales AS (
    SELECT
        SUM(units_sold) FILTER (WHERE units_valid_flag='Y') AS units_sold,
        SUM(sales_revenue_gbp) FILTER (WHERE units_valid_flag='Y') AS sales_revenue,
        SUM(warranty_reserve_gbp) FILTER (WHERE units_valid_flag='Y') AS warranty_reserve
    FROM fact_vehicle_sale
),
audits AS (
    SELECT
        COUNT(*) AS planned_audits,
        COUNT(*) FILTER (WHERE audit_status='Completed') AS completed_audits,
        AVG(compliance_score_pct) FILTER (WHERE audit_status='Completed') AS avg_compliance,
        SUM(COALESCE(recovery_value_gbp,0)) FILTER (WHERE audit_status='Completed') AS recovery_value
    FROM fact_retailer_audit
),
actions AS (
    SELECT
        COUNT(*) AS all_actions,
        COUNT(*) FILTER (WHERE action_status IN ('Closed','Closed Late')) AS closed_actions,
        COUNT(*) FILTER (WHERE action_status='Overdue') AS overdue_actions,
        COUNT(*) FILTER (WHERE training_action_flag='Y') AS training_actions,
        COUNT(*) FILTER (WHERE training_action_flag='Y' AND action_status IN ('Closed','Closed Late')) AS completed_training_actions
    FROM fact_improvement_action
)
SELECT
    c.valid_claims,
    ROUND(c.warranty_cost,2) AS total_warranty_cost_gbp,
    ROUND(c.approved_amount,2) AS approved_amount_gbp,
    s.units_sold,
    ROUND(c.warranty_cost / NULLIF(s.units_sold,0),2) AS warranty_cost_per_vehicle_gbp,
    ROUND(c.valid_claims * 100.0 / NULLIF(s.units_sold,0),2) AS claims_per_100_vehicles,
    ROUND(a.completed_audits * 100.0 / NULLIF(a.planned_audits,0),1) AS audit_plan_completion_pct,
    ROUND(a.avg_compliance,1) AS avg_audit_compliance_pct,
    ROUND(a.recovery_value,2) AS audit_recovery_value_gbp,
    ROUND(c.high_risk_claims * 100.0 / NULLIF(c.valid_claims,0),1) AS high_risk_claim_pct,
    ROUND(c.avg_days_to_close,1) AS avg_days_to_close,
    ROUND(c.dq_pass * 100.0 / NULLIF(c.clean_claim_rows,0),1) AS dq_pass_rate_pct,
    ROUND(ac.closed_actions * 100.0 / NULLIF(ac.all_actions,0),1) AS action_closure_pct,
    ac.overdue_actions,
    ROUND(ac.completed_training_actions * 100.0 / NULLIF(ac.training_actions,0),1) AS training_completion_pct,
    ROUND(c.warranty_cost * 100.0 / NULLIF(s.sales_revenue,0),3) AS warranty_cost_pct_of_sales,
    ROUND(c.warranty_cost * 100.0 / NULLIF(s.warranty_reserve,0),1) AS warranty_cost_vs_reserve_pct
FROM claims c
CROSS JOIN sales s
CROSS JOIN audits a
CROSS JOIN actions ac;

-- 7.2 Brand performance: cost, frequency and service
WITH c AS (
    SELECT brand,
           COUNT(*) AS claims,
           SUM(clean_total_claim_cost_gbp) AS warranty_cost,
           AVG(days_to_close) FILTER (WHERE days_to_close IS NOT NULL) AS avg_days_to_close
    FROM fact_warranty_claim
    WHERE is_analytics_valid='Y'
    GROUP BY brand
),
s AS (
    SELECT brand,
           SUM(units_sold) AS units_sold,
           SUM(sales_revenue_gbp) AS sales_revenue,
           SUM(warranty_reserve_gbp) AS warranty_reserve
    FROM fact_vehicle_sale
    WHERE units_valid_flag='Y'
    GROUP BY brand
)
SELECT
    c.brand,
    c.claims,
    s.units_sold,
    ROUND(c.warranty_cost,2) AS warranty_cost_gbp,
    ROUND(c.warranty_cost / NULLIF(s.units_sold,0),2) AS cost_per_vehicle_gbp,
    ROUND(c.claims * 100.0 / NULLIF(s.units_sold,0),2) AS claims_per_100_vehicles,
    ROUND(c.avg_days_to_close,1) AS avg_days_to_close,
    ROUND(c.warranty_cost * 100.0 / NULLIF(s.sales_revenue,0),3) AS warranty_cost_pct_sales,
    ROUND(c.warranty_cost * 100.0 / NULLIF(s.warranty_reserve,0),1) AS reserve_consumption_pct
FROM c JOIN s USING (brand)
ORDER BY warranty_cost_gbp DESC;

-- 7.3 Failure-category cost risk
SELECT
    failure_category,
    COUNT(*) AS claims,
    ROUND(SUM(clean_total_claim_cost_gbp),2) AS warranty_cost_gbp,
    ROUND(AVG(clean_total_claim_cost_gbp),2) AS avg_claim_cost_gbp,
    ROUND(SUM(clean_total_claim_cost_gbp) * 100.0 /
          SUM(SUM(clean_total_claim_cost_gbp)) OVER (),1) AS pct_of_total_cost
FROM fact_warranty_claim
WHERE is_analytics_valid='Y'
GROUP BY failure_category
ORDER BY warranty_cost_gbp DESC;

-- 7.4 Retailer audit-risk ranking
WITH claim_risk AS (
    SELECT
        retailer_id,
        COUNT(*) AS claims,
        AVG(clean_total_claim_cost_gbp) AS avg_claim_cost,
        COUNT(*) FILTER (WHERE risk_band='High') * 100.0 / COUNT(*) AS high_risk_pct
    FROM fact_warranty_claim
    WHERE is_analytics_valid='Y'
    GROUP BY retailer_id
),
audit_risk AS (
    SELECT
        retailer_id,
        AVG(compliance_score_pct) AS avg_compliance,
        SUM(COALESCE(major_findings,0)) AS major_findings,
        SUM(COALESCE(recovery_value_gbp,0)) AS recovery_value
    FROM fact_retailer_audit
    WHERE audit_status='Completed'
    GROUP BY retailer_id
)
SELECT
    r.retailer_id,
    r.retailer_name,
    r.brand,
    r.region,
    c.claims,
    ROUND(c.avg_claim_cost,2) AS avg_claim_cost_gbp,
    ROUND(c.high_risk_pct,1) AS high_risk_claim_pct,
    ROUND(a.avg_compliance,1) AS avg_audit_compliance_pct,
    a.major_findings,
    ROUND(a.recovery_value,2) AS audit_recovery_value_gbp
FROM dim_retailer r
JOIN claim_risk c USING (retailer_id)
LEFT JOIN audit_risk a USING (retailer_id)
ORDER BY a.avg_compliance NULLS LAST, c.high_risk_pct DESC;

-- 7.5 Audit-plan delivery by region
SELECT
    region,
    COUNT(*) AS planned_audits,
    COUNT(*) FILTER (WHERE audit_status='Completed') AS completed_audits,
    ROUND(COUNT(*) FILTER (WHERE audit_status='Completed') * 100.0 / COUNT(*),1) AS completion_pct,
    ROUND(AVG(compliance_score_pct) FILTER (WHERE audit_status='Completed'),1) AS avg_compliance_pct,
    ROUND(SUM(COALESCE(recovery_value_gbp,0)),2) AS recovery_value_gbp
FROM fact_retailer_audit
GROUP BY region
ORDER BY completion_pct, avg_compliance_pct;

-- 7.6 Improvement actions and training needs
SELECT
    action_category,
    COUNT(*) AS actions,
    COUNT(*) FILTER (WHERE action_status='Overdue') AS overdue,
    COUNT(*) FILTER (WHERE action_status IN ('Closed','Closed Late')) AS closed,
    ROUND(COUNT(*) FILTER (WHERE action_status IN ('Closed','Closed Late')) * 100.0 / COUNT(*),1) AS closure_pct,
    COUNT(*) FILTER (WHERE training_action_flag='Y') AS training_actions
FROM fact_improvement_action
GROUP BY action_category
ORDER BY overdue DESC, actions DESC;

-- 7.7 Monthly warranty trend
SELECT
    date_trunc('month', claim_date)::date AS month,
    brand,
    COUNT(*) AS claims,
    ROUND(SUM(clean_total_claim_cost_gbp),2) AS warranty_cost_gbp,
    ROUND(AVG(clean_total_claim_cost_gbp),2) AS avg_claim_cost_gbp
FROM fact_warranty_claim
WHERE is_analytics_valid='Y'
GROUP BY 1,2
ORDER BY 1,2;

-- -----------------------------------------------------------------------------
-- 8. STATISTICAL / MODELLING QUERIES
-- These are deliberately interpretable for an interview demonstration.
-- -----------------------------------------------------------------------------

-- 8.1 Retailer z-score: unusually high average claim cost
WITH retailer_cost AS (
    SELECT retailer_id,
           AVG(clean_total_claim_cost_gbp) AS avg_claim_cost
    FROM fact_warranty_claim
    WHERE is_analytics_valid='Y'
    GROUP BY retailer_id
),
stats AS (
    SELECT AVG(avg_claim_cost) AS mean_cost,
           STDDEV_SAMP(avg_claim_cost) AS sd_cost
    FROM retailer_cost
)
SELECT
    r.retailer_id,
    d.retailer_name,
    d.brand,
    ROUND(r.avg_claim_cost,2) AS avg_claim_cost_gbp,
    ROUND((r.avg_claim_cost - s.mean_cost) / NULLIF(s.sd_cost,0),2) AS cost_z_score,
    CASE
      WHEN ABS((r.avg_claim_cost - s.mean_cost) / NULLIF(s.sd_cost,0)) >= 2 THEN 'Investigate'
      ELSE 'Normal'
    END AS statistical_flag
FROM retailer_cost r
CROSS JOIN stats s
JOIN dim_retailer d USING (retailer_id)
ORDER BY cost_z_score DESC;

-- 8.2 Claim-level transparent risk model
SELECT
    claim_id,
    retailer_id,
    brand,
    clean_total_claim_cost_gbp,
    days_to_close,
    documentation_complete,
    claim_type,
    LEAST(
        100,
        5
        + CASE WHEN clean_total_claim_cost_gbp > 5000 THEN 25 ELSE 0 END
        + CASE WHEN days_to_close > 30 THEN 20 ELSE 0 END
        + CASE WHEN documentation_complete='N' THEN 20 ELSE 0 END
        + CASE WHEN claim_type='Goodwill' THEN 10 ELSE 0 END
    ) AS model_risk_score
FROM fact_warranty_claim
WHERE is_analytics_valid='Y'
ORDER BY model_risk_score DESC, clean_total_claim_cost_gbp DESC;

-- 8.3 Does lower audit compliance associate with higher claim cost?
WITH retailer_claim AS (
    SELECT retailer_id, AVG(clean_total_claim_cost_gbp) AS avg_claim_cost
    FROM fact_warranty_claim
    WHERE is_analytics_valid='Y'
    GROUP BY retailer_id
),
retailer_audit AS (
    SELECT retailer_id, AVG(compliance_score_pct) AS avg_compliance
    FROM fact_retailer_audit
    WHERE audit_status='Completed' AND compliance_score_pct IS NOT NULL
    GROUP BY retailer_id
)
SELECT ROUND(CORR(a.avg_compliance,c.avg_claim_cost)::numeric,3) AS compliance_cost_correlation
FROM retailer_audit a
JOIN retailer_claim c USING (retailer_id);

-- 8.4 Vehicle-program impact
SELECT
    c.vehicle_program_id,
    v.brand,
    v.model_family,
    COUNT(*) AS claims,
    ROUND(SUM(c.clean_total_claim_cost_gbp),2) AS warranty_cost_gbp,
    ROUND(AVG(c.clean_total_claim_cost_gbp),2) AS avg_claim_cost_gbp,
    ROUND(AVG(c.days_to_close),1) AS avg_days_to_close
FROM fact_warranty_claim c
JOIN dim_vehicle_program v USING (vehicle_program_id)
WHERE c.is_analytics_valid='Y'
GROUP BY c.vehicle_program_id,v.brand,v.model_family
ORDER BY warranty_cost_gbp DESC;

-- -----------------------------------------------------------------------------
-- 9. DATA-QUALITY GOVERNANCE SCORECARD
-- -----------------------------------------------------------------------------

SELECT
    COUNT(*) AS clean_rows,
    COUNT(*) FILTER (WHERE dq_status='Pass') AS dq_pass_rows,
    ROUND(COUNT(*) FILTER (WHERE dq_status='Pass') * 100.0 / COUNT(*),1) AS dq_pass_rate_pct,
    COUNT(*) FILTER (WHERE vin_valid_flag='N') AS invalid_or_missing_vin,
    COUNT(*) FILTER (WHERE cost_reconciled_flag='N') AS cost_reconciliation_failures,
    COUNT(*) FILTER (WHERE is_analytics_valid='N') AS excluded_from_cost_analytics
FROM fact_warranty_claim;

-- -----------------------------------------------------------------------------
-- 10. INTERVIEW-READY GOVERNANCE VIEW
-- One compact view for a board-level dashboard source.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW vw_retailer_governance_summary AS
WITH claims AS (
    SELECT retailer_id,
           COUNT(*) FILTER (WHERE is_analytics_valid='Y') AS claims,
           SUM(clean_total_claim_cost_gbp) FILTER (WHERE is_analytics_valid='Y') AS warranty_cost,
           AVG(days_to_close) FILTER (WHERE is_analytics_valid='Y') AS avg_days_to_close,
           COUNT(*) FILTER (WHERE risk_band='High' AND is_analytics_valid='Y') AS high_risk_claims
    FROM fact_warranty_claim
    GROUP BY retailer_id
),
audits AS (
    SELECT retailer_id,
           COUNT(*) AS audits_planned,
           COUNT(*) FILTER (WHERE audit_status='Completed') AS audits_completed,
           AVG(compliance_score_pct) FILTER (WHERE audit_status='Completed') AS avg_compliance,
           SUM(COALESCE(recovery_value_gbp,0)) AS recovery_value
    FROM fact_retailer_audit
    GROUP BY retailer_id
),
actions AS (
    SELECT retailer_id,
           COUNT(*) AS actions,
           COUNT(*) FILTER (WHERE action_status='Overdue') AS overdue_actions
    FROM fact_improvement_action
    GROUP BY retailer_id
)
SELECT
    r.retailer_id,
    r.retailer_name,
    r.brand,
    r.region,
    r.country,
    COALESCE(c.claims,0) AS claims,
    ROUND(COALESCE(c.warranty_cost,0),2) AS warranty_cost_gbp,
    ROUND(c.avg_days_to_close,1) AS avg_days_to_close,
    COALESCE(c.high_risk_claims,0) AS high_risk_claims,
    COALESCE(a.audits_planned,0) AS audits_planned,
    COALESCE(a.audits_completed,0) AS audits_completed,
    ROUND(a.avg_compliance,1) AS avg_compliance_pct,
    ROUND(COALESCE(a.recovery_value,0),2) AS recovery_value_gbp,
    COALESCE(ac.actions,0) AS improvement_actions,
    COALESCE(ac.overdue_actions,0) AS overdue_actions
FROM dim_retailer r
LEFT JOIN claims c USING (retailer_id)
LEFT JOIN audits a USING (retailer_id)
LEFT JOIN actions ac USING (retailer_id);

-- End of Project APEX-WARRANTY PostgreSQL solution.
