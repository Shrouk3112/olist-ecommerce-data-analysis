-- Q1: What are the top 10 product categories by total revenue (not just order count)?

WITH order_items_dedup AS (
    SELECT DISTINCT order_id, order_item_id, product_id, seller_id,
           customer_id, date_id, price, freight_value
    FROM fact_order_items
)
SELECT TOP 10
    p.product_category_name_english AS category,
    SUM(f.price) AS total_revenue,
    COUNT(*) AS total_items_sold
FROM order_items_dedup f
JOIN dim_products p ON f.product_id = p.product_id
GROUP BY p.product_category_name_english
ORDER BY total_revenue DESC;
/*Insight
Health & Beauty generated the highest total revenue (1,258,681 BRL from 9,670 items)
despite not having the highest number of items sold. In contrast, Bed & Bath Table
sold the largest number of items (11,115) but generated noticeably less revenue
(1,036,988 BRL). This indicates that revenue is influenced not only by sales volume
but also by the average selling price of products.*/


-- Q2. How does monthly revenue trend over time? Is there a clear seasonal pattern?

WITH order_items_dedup AS (
    SELECT DISTINCT order_id, order_item_id, product_id, seller_id,
           customer_id, date_id, price, freight_value
    FROM fact_order_items
)
SELECT
    d.year,
    d.month,
    d.month_name,
    SUM(f.price) AS total_revenue
FROM order_items_dedup f
JOIN dim_date d ON f.date_id = d.date_id
GROUP BY d.year, d.month, d.month_name
ORDER BY d.year, d.month;
/*Insight
Monthly revenue showed a clear upward trend from early 2017 through the first half of 2018,
indicating continuous business growth. Revenue peaked around November 2017 (1,010,271 BRL)
and remained consistently strong throughout most of 2018. September 2016 (267 BRL), December 2016 
(~11 BRL), and September 2018 (145 BRL) show near-zero revenue, which almost certainly reflects
incomplete data at the very start and very end of the dataset's time range, rather than an actual drop in sales.
October 2016 (49,507 BRL), while still well below the 2017-2018 average, is not negligible in the same way
and shouldn't be grouped with the near-zero months.These edge months should be excluded or flagged
when this data is charted in Power BI, so they don't visually distort the overall growth trend.*/


-- Q3. What is the Average Order Value (AOV), and does it vary significantly across product categories?

WITH order_items_dedup AS (
    SELECT DISTINCT order_id, order_item_id, product_id, seller_id,
           customer_id, date_id, price, freight_value
    FROM fact_order_items
)
SELECT
    p.product_category_name_english AS category,
    ROUND(SUM(f.price) / COUNT(DISTINCT f.order_id), 2) AS average_order_value
FROM order_items_dedup f
JOIN dim_products p ON f.product_id = p.product_id
GROUP BY p.product_category_name_english
ORDER BY average_order_value DESC;
/*Insight
The Computers category recorded the highest Average Order Value (AOV), significantly
outperforming all other product categories, followed by small home appliances and
home appliances more broadly. This indicates that customers purchasing technology
and premium home appliance products tend to spend considerably more per order than
customers in other categories.*/


-- Q4. What are the top 10 Brazilian states by total sales?

WITH order_items_dedup AS (
    SELECT DISTINCT order_id, order_item_id, product_id, seller_id,
           customer_id, date_id, price, freight_value
    FROM fact_order_items
)
SELECT TOP 10
    c.customer_state,
    SUM(f.price) AS total_revenue,
    COUNT(DISTINCT f.order_id) AS total_orders
FROM order_items_dedup f
JOIN dim_customers c ON f.customer_id = c.customer_id
GROUP BY c.customer_state
ORDER BY total_revenue DESC;
/*Insight
The state SP generated the highest total revenue (5.2M BRL from 41,375 orders),
nearly triple the second-place state RJ (1.82M BRL, 12,762 orders). This makes SP
the company's strongest market by a wide margin, and suggests sales are heavily
concentrated in a single region rather than spread evenly across the country.*/


-- Q5. Is there a significant difference in average delivery time across Brazilian states?

SELECT
    c.customer_state,
    ROUND(AVG(DATEDIFF(DAY, o.order_purchase_timestamp, o.order_delivered_customer_date)), 2) AS avg_delivery_days
FROM dbo.olist_orders_dataset o
JOIN dim_customers c ON o.customer_id = c.customer_id
WHERE o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state
ORDER BY avg_delivery_days DESC;
/*Insight
There is a noticeable variation in average delivery time across states. The longest
average delivery time was recorded in RR (29 days), followed by AP (27 days) and AM
(26 days). In contrast, SP had the shortest average delivery time at 8 days. This
wide gap suggests that delivery performance differs significantly between regions.*/


-- Q6. On average, does the company deliver orders before or after the estimated delivery date?

SELECT
    ROUND(AVG(DATEDIFF(DAY, o.order_delivered_customer_date, o.order_estimated_delivery_date)), 2) AS avg_delivery_difference_days
FROM dbo.olist_orders_dataset o
WHERE o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL;
/*Insight
On average, orders were delivered 11 days before the estimated delivery date. This
indicates that the company's delivery operations generally outperform customer
expectations, with most orders arriving earlier than promised.*/


-- Q7. Is there a correlation between delivery delays and customer review scores?

SELECT
    r.review_score,
    ROUND(AVG(DATEDIFF(DAY, o.order_estimated_delivery_date, o.order_delivered_customer_date)), 2) AS avg_delivery_delay_days
FROM dbo.olist_orders_dataset o
JOIN dbo.olist_order_reviews_dataset r ON o.order_id = r.order_id
WHERE o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY r.review_score
ORDER BY r.review_score;
/*Insight
Orders with higher review scores were generally delivered earlier than the estimated
delivery date. Customers who gave 5-star reviews received their orders approximately
13 days before the estimated delivery date, while 1-star reviews were associated
with deliveries only 4 days before the estimated date. This suggests a positive
relationship between faster deliveries and higher customer satisfaction.*/


-- Q8. What is the distribution of customer review scores (1 to 5 stars) across all orders?

SELECT
    review_score,
    COUNT(*) AS total_reviews
FROM dbo.olist_order_reviews_dataset
GROUP BY review_score
ORDER BY review_score;
/*Insight
Customer satisfaction is generally high. The majority of customers gave 5-star
ratings, followed by 4-star ratings. Low ratings (1 and 2 stars) are much less
frequent, indicating that most customers had a positive shopping experience.*/


-- Q9. Does the payment method (e.g. installments) have any relationship with customer satisfaction?

SELECT
    p.payment_type,
    ROUND(AVG(CAST(r.review_score AS FLOAT)), 2) AS avg_review_score,
    COUNT(DISTINCT p.order_id) AS total_orders
FROM dbo.olist_order_payments_dataset p
JOIN dbo.olist_order_reviews_dataset r ON p.order_id = r.order_id
GROUP BY p.payment_type
ORDER BY avg_review_score DESC;
/*Insight
Customer satisfaction is very similar across the main payment methods. Debit card
payments have the highest average review score (4.17, 1,521 orders), followed
closely by boleto and credit card (both 4.09, though credit card accounts for the
vast majority of orders at 75,910), and voucher slightly lower (4.00, 3,829 orders).
A fifth category, "not_defined," shows a much lower score (1.67), but it only covers
3 orders - far too small a sample to draw any conclusion from, so it's excluded from
the comparison. Across the four real payment methods, the scores are close enough
that payment method has little meaningful impact on customer satisfaction.*/


-- Q10. Who are the top 10 sellers by total revenue generated?

WITH order_items_dedup AS (
    SELECT DISTINCT order_id, order_item_id, product_id, seller_id,
           customer_id, date_id, price, freight_value
    FROM fact_order_items
)
SELECT TOP 10
    s.seller_id,
    ROUND(SUM(f.price), 2) AS total_revenue,
    COUNT(DISTINCT f.order_id) AS total_orders
FROM order_items_dedup f
JOIN dim_sellers s ON f.seller_id = s.seller_id
GROUP BY s.seller_id
ORDER BY total_revenue DESC;
/*Insight
Order volume and revenue rank don't move together in a straight line. The clearest
example: the 2nd-highest seller generated 222,776 BRL from just 358 orders, while
the 3rd-highest seller generated less revenue (200,472 BRL) from 1,806 orders - about
five times as many. This indicates that higher sales volume does not always mean
higher revenue, as some sellers achieve stronger results by selling fewer, higher-value
items rather than by selling more units.*/


-- Q11. Do the highest-selling sellers necessarily have higher customer review scores?

WITH order_items_dedup AS (
    SELECT DISTINCT order_id, order_item_id, product_id, seller_id,
           customer_id, date_id, price, freight_value
    FROM fact_order_items
),
order_review_dedup AS (
    SELECT order_id, AVG(CAST(review_score AS FLOAT)) AS review_score
    FROM dbo.olist_order_reviews_dataset
    GROUP BY order_id
)
SELECT TOP 10
    f.seller_id,
    ROUND(SUM(f.price), 2) AS total_revenue,
    ROUND(AVG(r.review_score), 2) AS avg_review_score
FROM order_items_dedup f
LEFT JOIN order_review_dedup r ON f.order_id = r.order_id
GROUP BY f.seller_id
ORDER BY total_revenue DESC;
/*Insight
The results show that higher revenue does not necessarily mean higher customer
satisfaction. Among the top 10 sellers by revenue, average review scores range from
3.34 to 4.34 - a meaningful spread. Notably, the seller with the 5th-highest revenue
has the lowest average review score (3.34) in the group, while a seller further down
the revenue ranking (4th) has the highest score (4.34). Sales performance and
customer satisfaction are clearly not the same thing and should be tracked as
separate metrics when evaluating sellers.*/


-- Q12. Based on all the above findings, if the company could improve just one area next year, what does the data point to?
/*Insight
The data points most clearly to delivery performance as the single highest-leverage
area for improvement. Three separate findings converge on this:
(1) Q7 shows a direct link between delivery delay and review score - customers whose
    orders arrived closer to the estimated date rated their experience far lower
    (1-star reviews averaged only 4 days early vs. 13 days early for 5-star reviews).
(2) Q5 shows delivery time is extremely uneven across regions (8 days in SP vs. up
    to 29 days in the North), meaning the experience is inconsistent depending on
    where the customer lives.
(3) Q4 shows sales are heavily concentrated in SP - so the states with the worst
    delivery times are also the ones the company has the most room to grow into,
    and poor delivery is likely holding that growth back.
Revenue and category-level findings (Q1-Q3, Q10-Q11) are useful for marketing and
seller management, but they describe *what* is selling, not *why* satisfaction
varies. Delivery is the one lever that shows up consistently across geography,
satisfaction, and growth potential at the same time - which is why it stands out
as the top priority over any single category or seller-level fix.*/
