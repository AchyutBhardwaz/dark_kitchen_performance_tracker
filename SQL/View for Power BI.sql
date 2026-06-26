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