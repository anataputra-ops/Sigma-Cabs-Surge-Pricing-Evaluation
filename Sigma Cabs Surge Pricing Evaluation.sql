CREATE VIEW vw_customer_loyalty_risk AS
-- 1. CTE untuk menghitung Median dan Modus secara dinamis
WITH Imputation_Values AS (
    SELECT 
        -- Menghitung Median untuk data numerik (Robust terhadap outlier)
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY "Customer_Rating") AS med_rating,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY "Cancellation_Last_1Month") AS med_cancel,
        -- Menghitung Modus untuk data ordinal/kategorikal
        MODE() WITHIN GROUP (ORDER BY "Customer_Since_Months") AS mode_tenure,
        MODE() WITHIN GROUP (ORDER BY "Type_of_Cab") AS mode_cab
    FROM sigma_cabs
),
-- 2. CTE untuk membersihkan duplikasi baris
Deduplicated_Cabs AS (
    SELECT 
        *,
        ROW_NUMBER() OVER(PARTITION BY "Trip_ID" ORDER BY "Trip_ID") as row_num
    FROM sigma_cabs
)
-- 3. Kueri utama yang menggabungkan data asli dengan nilai imputasi
SELECT 
    d."Trip_ID",
    d."Trip_Distance",   
    -- Imputasi Kategorikal menggunakan Modus
    COALESCE(d."Type_of_Cab", i.mode_cab) AS "Type_of_Cab", 
    -- Imputasi Numerik menggunakan Median
    COALESCE(d."Customer_Rating", i.med_rating) AS "Customer_Rating",
    COALESCE(d."Cancellation_Last_1Month", i.med_cancel) AS "Cancellation_Last_1Month",
    COALESCE(d."Customer_Since_Months", i.mode_tenure) AS "Customer_Since_Months",
    d."Surge_Pricing_Type",
    -- 3-Level Customer Tenure Segmentation (Menggunakan nilai yang sudah diimputasi)
    CASE 
        WHEN COALESCE(d."Customer_Since_Months", i.mode_tenure) <= 3 THEN '1. Newbies (0-3 months)'
        WHEN COALESCE(d."Customer_Since_Months", i.mode_tenure) BETWEEN 4 AND 7 THEN '2. Regulars (4-7 months)'
        WHEN COALESCE(d."Customer_Since_Months", i.mode_tenure) >= 8 THEN '3. Veterans (8-10 months)'
    END AS "Tenure_Segment",
    -- 5-Level Customer Risk Segmentation (Menggunakan nilai yang sudah diimputasi)
    CASE
        WHEN COALESCE(d."Customer_Rating", i.med_rating) >= 4.0 AND COALESCE(d."Cancellation_Last_1Month", i.med_cancel) = 0 THEN '1. Excellent (Zero Risk)'
        WHEN COALESCE(d."Customer_Rating", i.med_rating) >= 3.0 AND COALESCE(d."Cancellation_Last_1Month", i.med_cancel) <= 1 THEN '2. Good (Low Risk)'
        WHEN COALESCE(d."Customer_Rating", i.med_rating) > 2.5 AND COALESCE(d."Cancellation_Last_1Month", i.med_cancel) >= 2 THEN '3. High Cancel Risk'
        WHEN COALESCE(d."Customer_Rating", i.med_rating) <= 2.5 AND COALESCE(d."Cancellation_Last_1Month", i.med_cancel) <= 1 THEN '4. Attitude Risk'
        WHEN COALESCE(d."Customer_Rating", i.med_rating) <= 2.5 AND COALESCE(d."Cancellation_Last_1Month", i.med_cancel) >= 2 THEN '5. Toxic Customer'
        ELSE 'Moderate'
    END AS "Risk_Profile"
FROM Deduplicated_Cabs d
CROSS JOIN Imputation_Values i
WHERE d.row_num = 1; -- Hanya mengekstrak data yang unik (bebas duplikat)

select * from vw_customer_loyalty_risk;