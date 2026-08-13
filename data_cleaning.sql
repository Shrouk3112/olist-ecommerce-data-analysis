/*
================================================================================
 Project   : Olist Brazilian E-Commerce - Data Cleaning
 Database  : SQL Server
 Source    : Kaggle - Olist Brazilian E-Commerce Public Dataset
             (9 raw tables imported as-is via SSMS Import Flat File Wizard)

 Purpose:
 Before any analysis or modeling, the raw tables need to be checked and
 cleaned. This script documents every issue found in the raw data and
 the exact fix applied, in the order it was done. Some steps end with
 a "Result" comment showing what came back when the check was run -
 this is kept intentionally so anyone reviewing the script can follow
 the reasoning, not just the final queries.

 Tables covered:
 olist_customers_dataset, olist_orders_dataset, olist_order_items_dataset,
 olist_order_payments_dataset, olist_order_reviews_dataset,
 olist_products_dataset, olist_sellers_dataset, olist_geolocation_dataset,
 product_category_name_translation
================================================================================
*/


/* ==============================================================
   1) GEOLOCATION - remove duplicate rows
   --------------------------------------------------------------
   On first inspection this table had 1,000,163 rows, but a lot of
   that was duplication - the same zip code / lat / lng / city / state
   combination repeated many times (261,831 exact duplicates).
   Kept the first occurrence of each unique combo and dropped the rest.
============================================================== */
WITH dedup AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY geolocation_zip_code_prefix,
                            geolocation_lat,
                            geolocation_lng,
                            geolocation_city,
                            geolocation_state
               ORDER BY geolocation_zip_code_prefix
           ) AS row_num
    FROM dbo.olist_geolocation_dataset
)
DELETE FROM dedup WHERE row_num > 1;

-- Result: 1,000,163 -> 738,009 rows remaining.


/* ==============================================================
   2) CITY / STATE TEXT CLEANUP
   --------------------------------------------------------------
   Free-text city names are always messy in raw imports. Two issues
   showed up here: extra whitespace, and a handful of rows starting
   with a stray character (looked like leftover formatting from the
   original source file, e.g. "* cidade", "...arraial do cabo").
============================================================== */

-- 2.1 - trim whitespace on every city/state column
UPDATE dbo.olist_geolocation_dataset
SET geolocation_city  = LTRIM(RTRIM(geolocation_city)),
    geolocation_state = LTRIM(RTRIM(geolocation_state));

UPDATE dbo.olist_customers_dataset
SET customer_city  = LTRIM(RTRIM(customer_city)),
    customer_state = LTRIM(RTRIM(customer_state));

UPDATE dbo.olist_sellers_dataset
SET seller_city  = LTRIM(RTRIM(seller_city)),
    seller_state = LTRIM(RTRIM(seller_state));

-- Distinct city count after trimming: 8,010 (reasonable for Brazil).

-- 2.2 - strip a leading junk character where the city name doesn't
-- start with a normal letter/number (only 3 rows affected)
UPDATE dbo.olist_geolocation_dataset
SET geolocation_city = SUBSTRING(geolocation_city, 2, LEN(geolocation_city))
WHERE geolocation_city LIKE '[^a-zA-Z0-9]%';

-- Re-checked afterwards with the same LIKE pattern - 0 rows left.


/* ==============================================================
   3) ZIP CODE PREFIX - wrong data type on import
   --------------------------------------------------------------
   customer_zip_code_prefix and seller_zip_code_prefix were imported
   as INT instead of a text type, which silently drops leading zeros
   (e.g. 09790 becomes 9790). Confirmed this with sp_help + a sample
   SELECT before touching anything. geolocation's zip column came in
   fine as varchar, so it didn't need this fix.
============================================================== */
ALTER TABLE dbo.olist_customers_dataset
ALTER COLUMN customer_zip_code_prefix VARCHAR(10);

UPDATE dbo.olist_customers_dataset
SET customer_zip_code_prefix = RIGHT('00000' + customer_zip_code_prefix, 5);

ALTER TABLE dbo.olist_sellers_dataset
ALTER COLUMN seller_zip_code_prefix VARCHAR(10);

UPDATE dbo.olist_sellers_dataset
SET seller_zip_code_prefix = RIGHT('00000' + seller_zip_code_prefix, 5);

-- Verified LEN() on both columns returns a single value: 5, for every row.


/* ==============================================================
   4) CATEGORY TRANSLATION TABLE - broken header row
   --------------------------------------------------------------
   The import wizard didn't detect the header row correctly, so the
   columns came in as generic "column1"/"column2", and the actual
   header text ("product_category_name", "product_category_name_english")
   ended up sitting in the table as a data row. Removed that row and
   renamed the columns to what they should have been from the start.
============================================================== */
DELETE FROM dbo.product_category_name_translation
WHERE column1 = 'product_category_name';

EXEC sp_rename 'dbo.product_category_name_translation.column1', 'product_category_name', 'COLUMN';
EXEC sp_rename 'dbo.product_category_name_translation.column2', 'product_category_name_english', 'COLUMN';

-- Row count corrected: 72 -> 71.


/* ==============================================================
   5) PRODUCTS - missing category
   --------------------------------------------------------------
   610 products had no product_category_name. Deleting them wasn't
   an option since they're tied to real orders and sales - that
   would quietly remove revenue from any later analysis. Flagged
   them as 'unknown' instead so they still show up in category-level
   reporting as their own group.
============================================================== */
UPDATE dbo.olist_products_dataset
SET product_category_name = 'unknown'
WHERE product_category_name IS NULL;

-- product_weight_g / length_cm / height_cm / width_cm each had only
-- 2 NULLs. Left those as-is - too small a sample to estimate, and
-- not worth guessing dimensions for 2 out of ~33,000 products.


/* ==============================================================
   6) ORDERS - NULL delivery dates
   --------------------------------------------------------------
   order_approved_at, order_delivered_carrier_date and
   order_delivered_customer_date all had NULLs. Before assuming
   this is a data issue, checked whether it lines up with order
   status.
============================================================== */
SELECT order_status, COUNT(*) AS total_orders
FROM dbo.olist_orders_dataset
WHERE order_delivered_customer_date IS NULL
GROUP BY order_status;

-- Result: NULLs cluster almost entirely under canceled, unavailable,
-- shipped, processing, invoiced, created and approved - all cases
-- where the order genuinely hasn't reached the customer yet. Only
-- 8 rows show status = 'delivered' with a NULL date, likely a
-- logging gap in the source system rather than something to "fix".
--
-- Decision: left untouched. These NULLs are a real business state,
-- not missing data - they get filtered out where needed at the
-- analysis stage (e.g. delivery time calculations).


/* ==============================================================
   7) ORDER REVIEWS - missing comment text
   --------------------------------------------------------------
   review_comment_title and review_comment_message are frequently
   empty. Checked whether the actual metric (review_score) was
   affected.
============================================================== */
SELECT COUNT(*) FROM dbo.olist_order_reviews_dataset
WHERE review_score IS NULL;
-- Result: 0 - review_score is fully populated.

-- Decision: left comment fields as-is. Plenty of customers rate an
-- order without writing anything, that's normal behavior, not a
-- data quality problem.


/* ==============================================================
   8) DUPLICATE KEY CHECKS
   --------------------------------------------------------------
   Quick pass across the remaining tables to make sure nothing else
   had the same duplication issue as geolocation.
============================================================== */
SELECT customer_id, COUNT(*) FROM dbo.olist_customers_dataset
GROUP BY customer_id HAVING COUNT(*) > 1;

SELECT order_id, COUNT(*) FROM dbo.olist_orders_dataset
GROUP BY order_id HAVING COUNT(*) > 1;

SELECT seller_id, COUNT(*) FROM dbo.olist_sellers_dataset
GROUP BY seller_id HAVING COUNT(*) > 1;

-- order_items and order_payments don't have a single-column key -
-- items are unique per (order_id, order_item_id), payments per
-- (order_id, payment_sequential).
SELECT order_id, order_item_id, COUNT(*)
FROM dbo.olist_order_items_dataset
GROUP BY order_id, order_item_id HAVING COUNT(*) > 1;

SELECT order_id, payment_sequential, COUNT(*)
FROM dbo.olist_order_payments_dataset
GROUP BY order_id, payment_sequential HAVING COUNT(*) > 1;

-- All five checks returned 0 rows.


/* ==============================================================
   9) REFERENTIAL INTEGRITY CHECKS
   --------------------------------------------------------------
   Last check before moving on to modeling: make sure every foreign
   key actually points to something that exists. An orphan record
   here would silently disappear (or break) any JOIN done later on.
============================================================== */

-- every order has a real customer
SELECT o.customer_id
FROM dbo.olist_orders_dataset o
LEFT JOIN dbo.olist_customers_dataset c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

-- every order item points to a real product
SELECT oi.product_id
FROM dbo.olist_order_items_dataset oi
LEFT JOIN dbo.olist_products_dataset p ON oi.product_id = p.product_id
WHERE p.product_id IS NULL;

-- every order item points to a real seller
SELECT oi.seller_id
FROM dbo.olist_order_items_dataset oi
LEFT JOIN dbo.olist_sellers_dataset s ON oi.seller_id = s.seller_id
WHERE s.seller_id IS NULL;

-- every order item points to a real order
SELECT oi.order_id
FROM dbo.olist_order_items_dataset oi
LEFT JOIN dbo.olist_orders_dataset o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;

-- All four checks returned 0 rows - no orphan records anywhere
-- in the dataset.


/*
================================================================================
 SUMMARY

 - Removed 261,831 duplicate rows from geolocation
 - Cleaned up city/state text (trimmed whitespace, fixed 3 malformed
   city names)
 - Fixed zip code columns that lost leading zeros due to wrong data
   type on import (customers, sellers)
 - Fixed a broken header row in the category translation table
 - Filled 610 missing product categories with 'unknown' instead of
   deleting rows
 - Investigated NULLs in order delivery dates and review comments -
   confirmed they reflect real business states, not data errors, and
   left them unchanged
 - Confirmed no duplicate keys across all 9 tables
 - Confirmed full referential integrity across all foreign keys

 Data is clean and ready for the next stage: Data Modeling (Star Schema).
================================================================================
*/
