select * from dim_brand;
select * from dim_delivery_zone;
select * from dim_platform;
select * from dim_time_slot;
select * from fact_orders;

select distinct order_status
from fact_orders;

-- Brand Metrics Summary

SELECT 
    b.brand_name,
    COUNT(o.order_id) AS total_orders,
    ROUND(SUM(o.gross_revenue), 2) AS total_gross_revenue,
    ROUND(SUM(discount_applied), 2) AS total_discount,
    ROUND(SUM(o.gross_revenue - o.discount_applied),
            2) AS total_net_revenue,
    ROUND(AVG(o.gross_revenue), 2) AS avg_order_value,
    ROUND(AVG(o.gross_revenue - o.discount_applied),
            2) AS avg_net_revenue
FROM
    fact_orders o
        JOIN
    dim_brand b ON o.brand_id = b.brand_id
WHERE
    o.order_status = 'Delivered'
GROUP BY b.brand_name
ORDER BY total_gross_revenue DESC;

-- Which brand has the highest number of cancelled or returned orders

SELECT 
    b.brand_name,
    SUM(CASE
        WHEN o.order_status != 'Delivered' THEN 1
        ELSE 0
    END) AS canceled_refunded_order,
    COUNT(o.order_id) AS total_order,
    ROUND(SUM(CASE
                WHEN o.order_status != 'Delivered' THEN 1
                ELSE 0
            END) * 100.0 / COUNT(o.order_id),
            2) AS cancel_refund_pct
FROM
    fact_orders o
        JOIN
    dim_brand b ON o.brand_id = b.brand_id
GROUP BY b.brand_name;

-- If a brand has massive total orders but a high cancel_refund_pct,
-- it means marketing is doing a great job bringing people in,
-- but the kitchen operations or delivery fleet is failing them.


-- What is the average packing cost vs. average food cost for each brand?

SELECT 
    b.brand_name,
    -- 1. Operational Cost Baseline (Delivered Only)
    ROUND(AVG(CASE WHEN o.order_status = 'Delivered' THEN o.food_cost END), 2) AS avg_delivered_food_cost,
    ROUND(AVG(CASE WHEN o.order_status = 'Delivered' THEN o.packing_cost END), 2) AS avg_delivered_packing_cost,
    
    -- 2. Total Financial Leakage (Canceled/Returned Waste)
    ROUND(SUM(CASE WHEN o.order_status != 'Delivered' THEN o.food_cost + o.packing_cost ELSE 0 END), 2) AS total_cancelled_waste_loss
FROM fact_orders o
JOIN dim_brand b ON o.brand_id = b.brand_id
GROUP BY b.brand_name
ORDER BY avg_delivered_food_cost DESC;


-- Highlights if a brand is overspending on premium packaging for low-ticket menu items.

/* UNIT ECONOMICS PER BRAND PER TIME SLOT
	INTERMEDIATE LEVEL */

WITH unit_econ AS (
  SELECT
    b.brand_name,
    t.slot_name,
    ROUND(SUM(o.gross_revenue),2) AS gross_revenue,
    ROUND(SUM(o.gross_revenue - o.discount_applied),2) AS net_revenue,
    ROUND(SUM((o.gross_revenue - o.discount_applied) * o.platform_commission_pct),2) AS commission_paid,
    ROUND(SUM(o.food_cost + o.packing_cost + o.delivery_cost_brand),2) AS variable_cost,
    ROUND(SUM(o.gross_revenue - o.discount_applied)
      - SUM((o.gross_revenue - o.discount_applied) * o.platform_commission_pct)
      - SUM(o.food_cost + o.packing_cost + o.delivery_cost_brand),2) AS contribution_margin
  FROM fact_orders o
  JOIN dim_brand b ON o.brand_id = b.brand_id
  JOIN dim_time_slot t ON o.time_slot_id = t.time_slot_id
  WHERE o.order_status = 'Delivered'
  GROUP BY b.brand_name, t.slot_name
)
SELECT *,
  ROUND(contribution_margin / NULLIF(net_revenue, 0) * 100.0, 2) AS cm_pct,
  DENSE_RANK() OVER (PARTITION BY brand_name ORDER BY
    contribution_margin / NULLIF(net_revenue, 0) DESC) AS slot_rank
FROM unit_econ;



-- Multi-dimensional grain analysis (Brand + Platform + Time Slot)

SELECT 
    b.brand_name,
    p.platform_name,
    t.slot_name,
    SUM(CASE
        WHEN o.order_status != 'Delivered' THEN 1
        ELSE 0
    END) AS canceled_refunded_order,
    COUNT(o.order_id) AS total_order,
    ROUND(SUM(CASE
                WHEN o.order_status != 'Delivered' THEN 1
                ELSE 0
            END) * 100.0 / COUNT(o.order_id),
            2) AS cancel_refund_pct
FROM
    fact_orders o
        JOIN
    dim_brand b ON o.brand_id = b.brand_id
		JOIN
	dim_platform p ON o.platform_id = p.platform_id
		JOIN
	dim_time_slot t ON o.time_slot_id = t.time_slot_id
GROUP BY b.brand_name, p.platform_id, t.slot_name;


-- How does the Contribution Margin % (CM%) behave on Weekends vs. Weekdays?

WITH contribution_margin_cte AS (
    SELECT 
        t.day_type,
        (o.gross_revenue - o.discount_applied) AS net_revenue,
        (o.gross_revenue - o.discount_applied) - 
        (((o.gross_revenue - o.discount_applied) * o.platform_commission_pct) + o.food_cost + o.packing_cost + o.delivery_cost_brand) AS contribution_margin
    FROM fact_orders o
    JOIN dim_time_slot t 
    ON o.time_slot_id = t.time_slot_id
    WHERE o.order_status = 'Delivered'
)
SELECT
    day_type,
    COUNT(*) AS total_orders,
    ROUND(SUM(contribution_margin), 2) AS total_margin,
    ROUND(AVG(contribution_margin), 2) AS avg_margin_per_order,
    ROUND(SUM(contribution_margin) * 100.0 / NULLIF(SUM(net_revenue), 0), 2) AS Weighted_cm_pct
FROM contribution_margin_cte
GROUP BY day_type;

-- Operational Recommendation:
-- We should allocate 60% of our performance marketing budget exclusively to Friday-Sunday campaigns, 
-- as our physical kitchen spaces yield disproportionately higher cash velocity during weekend spikes.


/* Rolling 30-Day CM Trend per Brand
	ADVANCED LEVEL */

SELECT 
    b.brand_name,
    o.orders_date,
    ROUND(SUM((o.gross_revenue - o.discount_applied) - 
        ((o.gross_revenue - o.discount_applied) * o.platform_commission_pct) - 
        (o.food_cost + o.packing_cost + o.delivery_cost_brand)),2) AS cm_by_date,
    ROUND(SUM(
        SUM((o.gross_revenue - o.discount_applied) - 
            ((o.gross_revenue - o.discount_applied) * o.platform_commission_pct) - 
            (o.food_cost + o.packing_cost + o.delivery_cost_brand))
    ) OVER (
        PARTITION BY b.brand_name 
        ORDER BY o.orders_date 
        RANGE BETWEEN INTERVAL 29 DAY PRECEDING AND CURRENT ROW
    ),2) AS rolling_30d_contribution_margin

FROM fact_orders o
JOIN dim_brand b ON o.brand_id = b.brand_id
WHERE o.order_status = 'Delivered'
GROUP BY b.brand_name, o.orders_date;

-- Month on Month Growth

SELECT 
    brand_name,
    DATE_FORMAT(orders_date, '%b-%Y') AS month_group, 
    ROUND(SUM(gross_revenue), 2) AS total_revenue,
    ROUND(
        LAG(SUM(gross_revenue), 1, SUM(gross_revenue)) OVER (
            PARTITION BY brand_name 
            ORDER BY DATE_FORMAT(orders_date, '%Y-%m')
        ), 
        2
    ) AS previous_month,
    ROUND(
        SUM(gross_revenue) - LAG(SUM(gross_revenue), 1, SUM(gross_revenue)) OVER (
            PARTITION BY brand_name 
            ORDER BY DATE_FORMAT(orders_date, '%Y-%m')
        ), 
        2
    ) AS MOM_growth
FROM fact_orders o
JOIN dim_brand b ON o.brand_id = b.brand_id
WHERE order_status = 'Delivered'
GROUP BY brand_name, DATE_FORMAT(orders_date, '%Y-%m'), DATE_FORMAT(orders_date, '%b-%Y')
ORDER BY brand_name, DATE_FORMAT(orders_date, '%Y-%m');



CREATE VIEW vw_brand_unit_economics AS
SELECT 
	o.order_id,
	b.brand_id,
    b.brand_name,
    t.time_slot_id,
    t.slot_name,
    t.day_type,
    d.zone_id,
    d.zone_name,
    d.distance_km_band,
    d.avg_delivery_time_min,
    p.platform_id,
    p.platform_name,
    p.commission_rate,
    o.orders_date,
    o.gross_revenue,
    o.discount_applied,
    ROUND(o.gross_revenue - o.discount_applied,2) AS net_revenue,
    ROUND((o.gross_revenue - o.discount_applied) * o.platform_commission_pct,2) AS platform_commission,
    ROUND(o.food_cost + o.packing_cost + o.delivery_cost_brand,2) AS variable_cost,
    ROUND((o.gross_revenue - o.discount_applied)
		- ((o.gross_revenue - o.discount_applied) * o.platform_commission_pct)
        - (o.food_cost + o.packing_cost + o.delivery_cost_brand),2) AS contribution_margin,
	ROUND(((o.gross_revenue - o.discount_applied)
		- ((o.gross_revenue - o.discount_applied) * o.platform_commission_pct)
        - (o.food_cost + o.packing_cost + o.delivery_cost_brand)) * 100.0 / NULLIF((o.gross_revenue - o.discount_applied),0),2)
        AS contribution_margin_pct
FROM fact_orders o
JOIN dim_brand b ON o.brand_id = b.brand_id
JOIN dim_time_slot t ON o.time_slot_id = t.time_slot_id
JOIN dim_delivery_zone d ON o.zone_id = d.zone_id
JOIN dim_platform p ON o.platform_id = p.platform_id
WHERE o.order_status = 'Delivered';