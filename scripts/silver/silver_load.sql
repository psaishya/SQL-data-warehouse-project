-- Checking Duplicate values
SELECT cst_id,COUNT(*) 
FROM dwh_bronze.crm_cust_info
GROUP BY cst_id
HAVING COUNT(*) >1
;

-- Selecting unique values(most recent one in case of duplicate cst_id)
SELECT * FROM(
SELECT *, ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) as flag_last
FROM dwh_bronze.crm_cust_info) temp
WHERE flag_last=1;

-- trimming spaces in first name and last name and normalizing marital status and gender to full form
SELECT
			cst_id,
			cst_key,
			TRIM(cst_firstname) AS cst_firstname,
			TRIM(cst_lastname) AS cst_lastname,
			CASE 
				WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
				WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
				ELSE 'n/a'
			END AS cst_marital_status, -- 
			CASE 
				WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
				WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
				ELSE 'n/a'
			END AS cst_gndr, 
			cst_create_date
		FROM (
			SELECT
				*,
				ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) AS flag_last
			FROM dwh_bronze.crm_cust_info
			WHERE cst_id IS NOT NULL AND cst_id!=0
		) t
		WHERE flag_last = 1;

-- inserting into table
INSERT INTO dwh_silver.crm_cust_info (
			cst_id, 
			cst_key, 
			cst_firstname, 
			cst_lastname, 
			cst_marital_status, 
			cst_gndr,
			cst_create_date
		)
        SELECT
			cst_id,
			cst_key,
			TRIM(cst_firstname) AS cst_firstname,
			TRIM(cst_lastname) AS cst_lastname,
			CASE 
				WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
				WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
				ELSE 'n/a'
			END AS cst_marital_status, -- 
			CASE 
				WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
				WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
				ELSE 'n/a'
			END AS cst_gndr, 
			cst_create_date
		FROM (
			SELECT
				*,
				ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) AS flag_last
			FROM dwh_bronze.crm_cust_info
			WHERE cst_id IS NOT NULL AND cst_id!=0
		) t
		WHERE flag_last = 1;


INSERT INTO dwh_silver.crm_prd_info (
			prd_id,
			cat_id,
			prd_key,
			prd_nm,
			prd_cost,
			prd_line,
			prd_start_dt,
			prd_end_dt
		)
		SELECT
			prd_id,
			REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_') AS cat_id, -- Extract category ID
			SUBSTRING(prd_key, 7) AS prd_key,        -- Extract product key
			prd_nm,
			IFNULL(prd_cost, 0) AS prd_cost,
			CASE 
				WHEN UPPER(TRIM(prd_line)) = 'M' THEN 'Mountain'
				WHEN UPPER(TRIM(prd_line)) = 'R' THEN 'Road'
				WHEN UPPER(TRIM(prd_line)) = 'S' THEN 'Other Sales'
				WHEN UPPER(TRIM(prd_line)) = 'T' THEN 'Touring'
				ELSE 'n/a'
			END AS prd_line, -- product line codes to descriptive values
			CAST(prd_start_dt AS DATE) AS prd_start_dt,
			DATE_SUB(
                    LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt),
                    INTERVAL 1 DAY
            ) AS prd_end_dt -- Calculate end date as one day before the next start date
		FROM dwh_bronze.crm_prd_info;


INSERT INTO dwh_silver.crm_sales_details (
			sls_ord_num,
			sls_prd_key,
			sls_cust_id,
			sls_order_dt,
			sls_ship_dt,
			sls_due_dt,
			sls_sales,
			sls_quantity,
			sls_price
		)
		SELECT 
			sls_ord_num,
			sls_prd_key,
			sls_cust_id,
			CASE 
                WHEN sls_order_dt = 0 OR LENGTH(sls_order_dt) != 8 THEN NULL
                ELSE STR_TO_DATE(sls_order_dt, '%Y%m%d')
            END AS sls_order_dt,
            CASE 
                WHEN sls_ship_dt = 0 OR LENGTH(sls_ship_dt) != 8 THEN NULL
                ELSE STR_TO_DATE(sls_ship_dt, '%Y%m%d')
            END AS sls_ship_dt,
            CASE 
                WHEN sls_due_dt = 0 OR LENGTH(sls_due_dt) != 8 THEN NULL
                ELSE STR_TO_DATE(sls_due_dt, '%Y%m%d')
            END AS sls_due_dt,
			CASE 
				WHEN sls_sales IS NULL OR sls_sales <= 0 OR sls_sales != sls_quantity * ABS(sls_price) 
					THEN sls_quantity * ABS(sls_price)
				ELSE sls_sales
			END AS sls_sales, -- Recalculate sales if original value is missing or incorrect
			sls_quantity,
			
            CASE 
                WHEN sls_price IS NULL OR sls_price <= 0 THEN
                    CASE 
                        WHEN sls_quantity IS NULL OR sls_quantity = 0 THEN 0
                        ELSE sls_sales / sls_quantity
                    END
                ELSE sls_price
            END AS sls_price
		FROM dwh_bronze.crm_sales_details;


INSERT INTO dwh_silver.erp_cust_az12 (
			cid,
			bdate,
			gen
		)
		SELECT
			CASE
				WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4) -- Remove 'NAS' prefix if present
				ELSE cid
			END AS cid, 
			CASE
				WHEN bdate > CURRENT_DATE THEN NULL
				ELSE bdate
			END AS bdate, -- Set future birthdates to NULL
			CASE
				WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
				WHEN UPPER(TRIM(gen)) IN ('M', 'MALE') THEN 'Male'
				ELSE 'n/a'
			END AS gen -- Normalize gender values and handle unknown cases
		FROM dwh_bronze.erp_cust_az12;


INSERT INTO dwh_silver.erp_loc_a101 (
			cid,
			cntry
		)
		SELECT
			REPLACE(cid, '-', '') AS cid, 
			CASE
				WHEN TRIM(cntry) = 'DE' THEN 'Germany'
				WHEN TRIM(cntry) IN ('US', 'USA') THEN 'United States'
				WHEN TRIM(cntry) = '' OR cntry IS NULL THEN 'n/a'
				ELSE TRIM(cntry)
			END AS cntry -- Normalize and Handle missing or blank country codes
		FROM dwh_bronze.erp_loc_a101;

INSERT INTO dwh_silver.erp_px_cat_g1v2 (
			id,
			cat,
			subcat,
			maintenance
		)
		SELECT
			id,
			cat,
			subcat,
			maintenance
		FROM dwh_bronze.erp_px_cat_g1v2;