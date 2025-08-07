select * from dbo.raw_sales_large;
select * from dbo.products_large;
select * from dbo.freequent_buyer_per_month;


-----1.	Find total number of unique products sold by each merchant.
select s.merchant_id, count(distinct s.product_id) as unique_product from 
dbo.raw_sales_large s
group by merchant_id;


-------Get the merchant-wise top 3 selling product categories based on revenue.

  SELECT *
FROM (
    SELECT 
        s.merchant_id, 
        p.category, 
        SUM(TRY_CAST(s.amount AS DECIMAL(18,2))) AS total_revenue,
        RANK() OVER (
            PARTITION BY s.merchant_id 
            ORDER BY SUM(TRY_CAST(s.amount AS DECIMAL(18,2))) DESC
        ) AS rnk 
    FROM dbo.raw_sales_large s
    JOIN dbo.products_large p
        ON s.product_id = p.product_id
    GROUP BY s.merchant_id, p.category
) AS t
WHERE rnk <= 3;

-----List all transactions where product category is 'Electronics' and amount > ₹2000.
select s.transaction_id, s.amount, p.category from dbo.raw_sales_large as s
join dbo.products_large p
on s.product_id = p.product_id 
where 
try_cast(s.amount as decimal(18,2))>2000 and p.category = 'Electronics';

-----Find merchants who sold more than 10 unique products in the 'Grocery' category.

select s.merchant_id, p.category, count(distinct s.product_id ) as unique_product from dbo.raw_sales_large s
join dbo.products_large p
on s.product_id= p.product_id
where p.category = 'grocery'
group by s.merchant_id, p.category
HAVING COUNT(DISTINCT s.product_id) > 10;

--------Find the product that has the highest total revenue across all merchants.

select 
top 1
product_id , sum(try_cast(amount as decimal(18,2))) as total_revenue
from dbo.raw_sales_large 
group by product_id
ORDER BY 
    total_revenue DESC;

------	Which merchant has the highest average transaction value per day?
WITH daily_totals AS(

select merchant_id , 
try_cast(transaction_date as date ) as txn_date,
sum(try_cast(amount as decimal(18,2))) as daily_total
from dbo.raw_sales_large 
group by merchant_id , try_cast(transaction_date as date))

SELECT TOP 1
    merchant_id,
    AVG(daily_total) AS avg_per_day
FROM 
    daily_totals
GROUP BY 
    merchant_id
ORDER BY 
    avg_per_day DESC;
	------------------without CTE---------------------------------

select top 1
merchant_id, 
avg(daily_amount) as average_daily_amount_per_day
from (
select merchant_id, 
	try_cast(transaction_date as date) as txn_date,
	sum(cast(amount as decimal(18,2)))as daily_amount 

from dbo.raw_sales_large 
group by merchant_id, try_cast(transaction_date as date)
) as daily_totals
group by merchant_id 
order by
average_daily_amount_per_day desc;

-----------	For each product category, find the date on which it had maximum sales revenue-----------
select 
txn_date, total_amount, category
from (
select
p.category,
try_cast(s.transaction_date as date) as txn_date,
sum(try_cast(s.amount as decimal(18,2)))as total_amount,
row_number() over(partition by p.category order by sum(try_cast(s.amount as decimal(18,2)))desc ) as rn
from dbo.raw_sales_large s
join dbo.products_large p
on s.product_id = p.product_id
    WHERE TRY_CAST(s.transaction_date AS DATE) IS NOT NULL  -- FILTER NULL DATES

group by p.category , try_cast(s.transaction_date as date)
) as ranked 
where 
rn=1;

----------	List product IDs that appear in the top 5% of revenue generators.
----------(Hint: Use subquery with percentile logic)
-- Step 1: Calculate total revenue per product
SELECT product_id, SUM(TRY_CAST(amount AS DECIMAL(18,2))) AS total_revenue
INTO #product_revenue
FROM dbo.raw_sales_large
GROUP BY product_id;

-- Step 2: Find the revenue threshold for top 5%
SELECT TOP 1 
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY total_revenue) 
    OVER () AS revenue_threshold
INTO #threshold
FROM #product_revenue;

-- Step 3: Select product IDs with revenue above the 95th percentile
SELECT pr.product_id, pr.total_revenue
FROM #product_revenue pr
JOIN #threshold t ON pr.total_revenue >= t.revenue_threshold;

-- Clean up temp tables (optional)
DROP TABLE #product_revenue;
DROP TABLE #threshold;



-------	Using ROW_NUMBER(), get the top 2 most expensive transactions per merchant---------------
with ranked_txn as(
select 
merchant_id, product_id , amount, 

rank()over(partition by merchant_id order by try_cast(amount as decimal(18,2)) desc )
as rn
from dbo.raw_sales_large 
)
select 
merchant_id,
product_id,
amount 
from ranked_txn
where rn <=2;


-------to find top 3 products by revenue within each category.

with ranked_product as
(
select s.product_id, s.transaction_id, p.category,
rank()over(
            PARTITION BY p.category 
            ORDER BY TRY_CAST(s.amount AS DECIMAL(18,2)) DESC
        ) AS rn
from dbo.raw_sales_large s
join dbo.products_large p
on s.product_id = p.product_id 
)
select product_id, transaction_id , category 
from ranked_product 
where rn <=3;

----------find out if a merchant’s daily sales increased or decreased compared to the previous day.

WITH daily_sales AS (
    SELECT 
        merchant_id,
		try_cast(transaction_date AS DATE) AS sales_date,
        SUM(TRY_CAST(amount AS DECIMAL(18,2))) AS total_sales
    FROM dbo.raw_sales_large
    GROUP BY merchant_id, TRY_CAST(transaction_date as DATE)
),
sales_comparison AS (
    SELECT 
        merchant_id,
        sales_date,
        total_sales,
        LAG(total_sales) OVER (PARTITION BY merchant_id ORDER BY sales_date) AS previous_day_sales
    FROM daily_sales
)
SELECT 
    merchant_id,
    sales_date,
    total_sales,
    previous_day_sales,
    CASE 
        WHEN previous_day_sales IS NULL THEN 'No previous data'
        WHEN total_sales > previous_day_sales THEN 'Increased'
        WHEN total_sales < previous_day_sales THEN 'Decreased'
        ELSE 'No Change'
    END AS sales_trend
FROM sales_comparison
ORDER BY merchant_id, sales_date;


-----------	Use DENSE_RANK() to list top spending customers 



WITH merchant_revenue AS (
    SELECT 
        merchant_id,
        SUM(TRY_CAST(amount AS DECIMAL(18,2))) AS total_revenue
    FROM dbo.raw_sales_large
    GROUP BY merchant_id
),

ranked_merchants AS (
    SELECT 
        merchant_id,
        total_revenue,
        DENSE_RANK() OVER (ORDER BY total_revenue DESC) AS revenue_rank
    FROM merchant_revenue
)


SELECT *
FROM ranked_merchants
WHERE revenue_rank <= 5  -- Change 5 to get top N merchants
ORDER BY revenue_rank;


---13.	Find duplicate transactions (same amount, merchant, date, and product).

SELECT merchant_id, product_id, transaction_id, amount, 
COUNT(*) AS duplicate_count
FROM dbo.raw_sales_large 
GROUP BY
	merchant_id, product_id, transaction_id, amount 
	HAVING COUNT(*)> 1;	


--------------find transactions where product_id doesn’t exist in products table.

SELECT * FROM dbo.raw_sales_large s
LEFT JOIN 
dbo.products_large p
ON s.product_id = p.product_id 
WHERE 
p.product_id IS NULL;


------------find rows where amount is negative or zero (if any), and flag them.

SELECT *,
CASE WHEN TRY_CAST( amount AS DECIMAL(18,2)) <= 0 THEN 'Invalid'
ELSE 'Valid'
END AS amount_flag
FROM dbo.raw_sales_large
WHERE TRY_CAST(amount AS DECIMAL(18,2)) <= 0;