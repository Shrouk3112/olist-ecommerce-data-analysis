/*
================================================================================
 Project   : Olist Brazilian E-Commerce - Data Modeling (Star Schema)
 Database  : SQL Server
 Source    : Cleaned tables from data_cleaning.sql

 Purpose:
 Turn the cleaned raw tables into a proper Star Schema - one fact
 table holding the measurable numbers (price, freight, payment,
 review score), surrounded by dimension tables that give that data
 context (who bought it, what was bought, who sold it, when it
 happened). This is what gets connected in Power BI afterwards.
================================================================================
*/


/* ==============================================================
   DIM_CUSTOMERS
   --------------------------------------------------------------
   Who is the customer? Pulled straight from the cleaned customers
   table - nothing to join or calculate here.
============================================================== */
SELECT
    customer_id,
    customer_unique_id,
    customer_city,
    customer_state,
    customer_zip_code_prefix
INTO dim_customers
FROM dbo.olist_customers_dataset;

-- Row count check: 99,441 - matches source.


/* ==============================================================
   DIM_PRODUCTS
   --------------------------------------------------------------
   What is the product? Joined in the English category name from
   the translation table alongside the original Portuguese one.

   Used LEFT JOIN on purpose, not a plain JOIN - about 610 products
   have product_category_name = 'unknown' (flagged during cleaning),
   and 'unknown' has no row in the translation table. A plain JOIN
   would have quietly dropped those 610 products out of the
   dimension entirely. LEFT JOIN keeps every product; the ones with
   no translation just get a blank product_category_name_english.
============================================================== */
SELECT
    p.product_id,
    p.product_category_name,
    t.product_category_name_english,
    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm
INTO dim_products
FROM dbo.olist_products_dataset p
LEFT JOIN dbo.product_category_name_translation t
    ON p.product_category_name = t.product_category_name;

-- Row count check: 32,951 - matches source.


/* ==============================================================
   DIM_SELLERS
   --------------------------------------------------------------
   Who is the seller? Straightforward, no joins needed.
============================================================== */
SELECT
    seller_id,
    seller_city,
    seller_state,
    seller_zip_code_prefix
INTO dim_sellers
FROM dbo.olist_sellers_dataset;

-- Row count check: 3,095 - matches source.


/* ==============================================================
   DIM_DATE
   --------------------------------------------------------------
   When did it happen? Unlike the other dimensions, there's no
   source table for this one - built it from the distinct purchase
   dates in orders, then broke each one down into
   year/month/day/weekday/quarter so Power BI can filter and group
   by any time period without extra calculation later.
============================================================== */
SELECT DISTINCT
    CAST(order_purchase_timestamp AS DATE) AS date_id,
    YEAR(order_purchase_timestamp) AS year,
    MONTH(order_purchase_timestamp) AS month,
    DATENAME(MONTH, order_purchase_timestamp) AS month_name,
    DAY(order_purchase_timestamp) AS day,
    DATENAME(WEEKDAY, order_purchase_timestamp) AS day_name,
    DATEPART(QUARTER, order_purchase_timestamp) AS quarter
INTO dim_date
FROM dbo.olist_orders_dataset;

-- Row count check: 634 distinct dates.


/* ==============================================================
   FACT_ORDER_ITEMS
   --------------------------------------------------------------
   The core of the model - one row per product sold within an
   order, holding every measurable number (price, freight, payment,
   review score) plus the foreign keys out to each dimension.

   Join logic:
   - INNER JOIN orders: every order item is guaranteed to belong to
     a real order (checked during the referential integrity pass in
     cleaning), so an inner join here is safe and won't drop rows.
   - LEFT JOIN payments: keeps every order item even on the rare
     chance payment info is missing, instead of silently dropping it.
   - LEFT JOIN reviews: same reasoning - not every order has a
     review, and those order items still belong in the fact table.
============================================================== */
SELECT
    oi.order_id,
    oi.order_item_id,
    oi.product_id,
    oi.seller_id,
    o.customer_id,
    CAST(o.order_purchase_timestamp AS DATE) AS date_id,
    oi.price,
    oi.freight_value,
    p.payment_type,
    p.payment_installments,
    p.payment_value,
    r.review_score,
    o.order_status
INTO fact_order_items
FROM dbo.olist_order_items_dataset oi
INNER JOIN dbo.olist_orders_dataset o
    ON oi.order_id = o.order_id
LEFT JOIN dbo.olist_order_payments_dataset p
    ON oi.order_id = p.order_id
LEFT JOIN dbo.olist_order_reviews_dataset r
    ON oi.order_id = r.order_id;

-- Row count: 118,310 (vs. 112,650 in the original order_items table).
-- This is expected, not a bug: some orders were paid using more than
-- one payment method (e.g. part voucher + part credit card), so the
-- LEFT JOIN to payments duplicates those order items once per
-- payment method. Fine for this model as-is; if a clean "total
-- revenue" number is ever needed without that duplication, it
-- should be pulled from the payments table directly rather than
-- summed off this fact table.


/* ==============================================================
   PRIMARY KEYS
   --------------------------------------------------------------
   SELECT INTO creates the table structure and data but no primary
   key. Adding one to each table below - it's good practice for a
   star schema regardless, and it's also required by SSMS's
   Database Diagram tool before a table can be dragged into a
   relationship with another one.

   dim_date needed an extra step first: date_id came in as nullable
   by default (SELECT INTO doesn't carry over NOT NULL), and SQL
   Server won't allow a primary key on a nullable column.
============================================================== */
ALTER TABLE fact_order_items
ADD fact_id INT IDENTITY(1,1) PRIMARY KEY;

ALTER TABLE dim_customers
ADD CONSTRAINT PK_dim_customers PRIMARY KEY (customer_id);

ALTER TABLE dim_products
ADD CONSTRAINT PK_dim_products PRIMARY KEY (product_id);

ALTER TABLE dim_sellers
ADD CONSTRAINT PK_dim_sellers PRIMARY KEY (seller_id);

ALTER TABLE dim_date
ALTER COLUMN date_id DATE NOT NULL;

ALTER TABLE dim_date
ADD CONSTRAINT PK_dim_date PRIMARY KEY (date_id);


/* ==============================================================
   RELATIONSHIP VALIDATION
   --------------------------------------------------------------
   Before wiring this up in the Database Diagram (and later in
   Power BI), confirmed every foreign key in the fact table actually
   matches a row in its dimension table. Any mismatch here would
   mean silently losing rows once relationships are built downstream.
============================================================== */
SELECT f.customer_id
FROM fact_order_items f
LEFT JOIN dim_customers d ON f.customer_id = d.customer_id
WHERE d.customer_id IS NULL;

SELECT f.product_id
FROM fact_order_items f
LEFT JOIN dim_products d ON f.product_id = d.product_id
WHERE d.product_id IS NULL;

SELECT f.seller_id
FROM fact_order_items f
LEFT JOIN dim_sellers d ON f.seller_id = d.seller_id
WHERE d.seller_id IS NULL;

SELECT f.date_id
FROM fact_order_items f
LEFT JOIN dim_date d ON f.date_id = d.date_id
WHERE d.date_id IS NULL;

-- All four checks returned 0 rows. Every relationship in the model
-- is valid - no orphan keys in either direction.


/*
================================================================================
 SUMMARY

   dim_customers      99,441 rows
   dim_products       32,951 rows
   dim_sellers         3,095 rows
   dim_date              634 rows
   fact_order_items   118,310 rows

 fact_order_items sits at the center of the star, connected to all
 four dimensions through matching primary/foreign keys - built and
 confirmed both in SQL and visually in the Database Diagram tool
 (saved as dbo.Data Modeling, exported as erd_diagram.png).

 Model is clean, validated, and ready for SQL analysis and Power BI.
================================================================================
*/
