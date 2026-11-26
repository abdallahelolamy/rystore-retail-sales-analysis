SELECT COUNT(order_id) AS Total_Completed_Orders, ROUND(SUM(net_subtotal), 2) AS Net_Revenue,
ROUND(SUM(total_amount), 2) AS Total_Sales_Incl_VAT,
ROUND(SUM(net_subtotal) / COUNT(order_id), 2) AS Average_Order_Value
FROM orders WHERE is_revenue = 1;
GO

SELECT p.category, ROUND(SUM(oi.line_net_amount), 2) AS Net_Revenue,
ROUND(SUM(oi.quantity * p.unit_cost), 2) AS Total_COGS,
ROUND(SUM(oi.line_net_amount) - SUM(oi.quantity * p.unit_cost), 2) AS Gross_Profit,
ROUND((SUM(oi.line_net_amount) - SUM(oi.quantity * p.unit_cost)) * 100.0 / SUM(oi.line_net_amount), 2) AS Gross_Margin_Pct
FROM order_items oi JOIN orders o ON oi.order_id = o.order_id JOIN products p ON oi.product_id = p.product_id
WHERE o.is_revenue = 1 GROUP BY p.category ORDER BY Gross_Profit DESC;
GO

SELECT s.store_name, s.city, s.store_format, COUNT(o.order_id) AS Total_Orders,
ROUND(SUM(o.net_subtotal), 2) AS Net_Revenue, ROUND(AVG(o.net_subtotal), 2) AS Store_AOV
FROM orders o JOIN stores s ON o.store_id = s.store_id
WHERE o.is_revenue = 1 GROUP BY s.store_name, s.city, s.store_format ORDER BY Net_Revenue DESC;
GO

SELECT TOP 10 p.product_name, p.category, SUM(oi.quantity) AS Units_Sold,
ROUND(SUM(oi.line_net_amount), 2) AS Product_Revenue
FROM order_items oi JOIN orders o ON oi.order_id = o.order_id JOIN products p ON oi.product_id = p.product_id
WHERE o.is_revenue = 1 GROUP BY p.product_name, p.category ORDER BY Product_Revenue DESC;
GO

SELECT sup.supplier_name, sup.lead_time_days, COUNT(*) AS Total_Active_SKUs_In_Stores,
SUM(i.below_reorder) AS SKUs_Below_Reorder,
ROUND(SUM(i.below_reorder) * 100.0 / COUNT(*), 2) AS Stockout_Risk_Pct
FROM inventory i JOIN products p ON i.product_id = p.product_id JOIN suppliers sup ON p.supplier_id = sup.supplier_id
GROUP BY sup.supplier_name, sup.lead_time_days HAVING SUM(i.below_reorder) > 0
ORDER BY Stockout_Risk_Pct DESC, sup.lead_time_days DESC;
GO

/* السؤال 16: حساب معدل النمو الشهري (MoM Growth %) باستخدام CTE ودالة LAG() */
WITH MonthlySales AS (
SELECT FORMAT(order_date, 'yyyy-MM') AS Year_Month, ROUND(SUM(net_subtotal), 2) AS Net_Revenue
FROM orders WHERE is_revenue = 1 GROUP BY FORMAT(order_date, 'yyyy-MM')
)
SELECT Year_Month, Net_Revenue, LAG(Net_Revenue) OVER (ORDER BY Year_Month) AS Prev_Month_Revenue,
ROUND((Net_Revenue - LAG(Net_Revenue) OVER (ORDER BY Year_Month)) * 100.0 / NULLIF(LAG(Net_Revenue) OVER (ORDER BY Year_Month), 0), 2) AS MoM_Growth_Pct
FROM MonthlySales ORDER BY Year_Month;
GO

 --السؤال 17: استخراج أفضل 3 منتجات مبيعاً داخل كل فرع على حدة 
--(Top 3 per Store) باستخدام DENSE_RANK() 
WITH StoreProductPerf AS (
SELECT s.store_name, p.product_name, ROUND(SUM(oi.line_net_amount), 2) AS Product_Revenue,
ROUND(SUM(SUM(oi.line_net_amount)) OVER (PARTITION BY s.store_name), 2) AS Store_Total_Revenue,
DENSE_RANK() OVER (PARTITION BY s.store_name ORDER BY SUM(oi.line_net_amount) DESC) AS Rank_In_Store
FROM order_items oi JOIN orders o ON oi.order_id = o.order_id JOIN stores s ON o.store_id = s.store_id JOIN products p ON oi.product_id = p.product_id
WHERE o.is_revenue = 1 GROUP BY s.store_name, p.product_name
)
SELECT store_name, Rank_In_Store, product_name, Product_Revenue,
ROUND(Product_Revenue * 100.0 / Store_Total_Revenue, 2) AS Pct_Of_Store_Revenue
FROM StoreProductPerf WHERE Rank_In_Store <= 3 ORDER BY store_name, Rank_In_Store;


/* السؤال 18: تقسيم العملاء بنموذج RFM (Recency, Frequency, Monetary) باستخدام NTILE(4) */
WITH CustomerRFM AS (
SELECT c.customer_id, c.first_name + ' ' + c.last_name AS Customer_Name,
DATEDIFF(DAY, MAX(o.order_date), '2025-12-31') AS Recency_Days,
COUNT(o.order_id) AS Frequency_Orders, SUM(o.net_subtotal) AS Monetary_Spend
FROM customers c JOIN orders o ON c.customer_id = o.customer_id
WHERE o.is_revenue = 1 GROUP BY c.customer_id, c.first_name, c.last_name
),
RFMScores AS (
SELECT *, NTILE(4) OVER (ORDER BY Recency_Days DESC) AS R_Score,
NTILE(4) OVER (ORDER BY Frequency_Orders ASC) AS F_Score,
NTILE(4) OVER (ORDER BY Monetary_Spend ASC) AS M_Score
FROM CustomerRFM
)
SELECT CASE WHEN R_Score = 4 AND F_Score >= 3 AND M_Score >= 3 THEN 'Champions (VIP)'
WHEN R_Score <= 2 AND M_Score >= 3 THEN 'At-Risk High Spenders'
WHEN F_Score >= 3 THEN 'Loyal Regulars' ELSE 'Standard Customers' END AS RFM_Segment,
COUNT(*) AS Customers_Count, ROUND(AVG(CAST(Recency_Days AS FLOAT)), 1) AS Avg_Recency_Days,
ROUND(AVG(CAST(Frequency_Orders AS FLOAT)), 1) AS Avg_Orders, ROUND(AVG(Monetary_Spend), 2) AS Avg_Total_Spend
FROM RFMScores
GROUP BY CASE WHEN R_Score = 4 AND F_Score >= 3 AND M_Score >= 3 THEN 'Champions (VIP)'
WHEN R_Score <= 2 AND M_Score >= 3 THEN 'At-Risk High Spenders'
WHEN F_Score >= 3 THEN 'Loyal Regulars' ELSE 'Standard Customers' END
ORDER BY Avg_Total_Spend DESC;
GO

/* السؤال 19: تحليل سلة المشتريات (Market Basket Analysis) - أكثر 10 أزواج منتجات تُشترى معاً (Self-Join) */
SELECT TOP 10 p1.product_name AS Product_A, p2.product_name AS Product_B,
COUNT(DISTINCT oi1.order_id) AS Times_Bought_Together
FROM order_items oi1
JOIN order_items oi2 ON oi1.order_id = oi2.order_id AND oi1.product_id < oi2.product_id
JOIN orders o ON oi1.order_id = o.order_id
JOIN products p1 ON oi1.product_id = p1.product_id
JOIN products p2 ON oi2.product_id = p2.product_id
WHERE o.is_revenue = 1 GROUP BY p1.product_name, p2.product_name ORDER BY Times_Bought_Together DESC;
GO

/* السؤال 20: حساب أيام تغطية المخزون المتبقية (Days of Supply) لاكتشاف الأصناف التي ستنفد قبل وصول المورد */
WITH DailySalesRate AS (
SELECT o.store_id, oi.product_id, SUM(oi.quantity) / 365.0 AS Avg_Daily_Units_Sold
FROM order_items oi JOIN orders o ON oi.order_id = o.order_id
WHERE o.is_revenue = 1 GROUP BY o.store_id, oi.product_id
)
SELECT TOP 15 st.store_name, p.product_name, sup.supplier_name, i.stock_on_hand, i.stock_on_order,
ROUND(d.Avg_Daily_Units_Sold, 2) AS Avg_Daily_Sales,
ROUND(i.stock_on_hand / NULLIF(d.Avg_Daily_Units_Sold, 0), 1) AS Days_Of_Stock_Left,
sup.lead_time_days AS Supplier_Lead_Time_Days
FROM inventory i
JOIN DailySalesRate d ON i.store_id = d.store_id AND i.product_id = d.product_id
JOIN stores st ON i.store_id = st.store_id JOIN products p ON i.product_id = p.product_id JOIN suppliers sup ON p.supplier_id = sup.supplier_id
WHERE (i.stock_on_hand / NULLIF(d.Avg_Daily_Units_Sold, 0)) < sup.lead_time_days AND i.stock_on_order = 0
ORDER BY Days_Of_Stock_Left ASC;
GO



