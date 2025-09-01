-- 1. Monthly late rate overall and by ship_mode in 2025‑04 to 2025‑06.
WITH monthly_late_overall AS (
    SELECT 
        DATE_TRUNC('month', order_date) AS month,
        SUM(late_delivery) / COUNT(*) AS late_rate
    FROM purchase_orders
    WHERE order_date >= '2025-04-01' AND order_date < '2025-07-01'
    GROUP BY month
),
monthly_late_ship_mode AS (
    SELECT 
        DATE_TRUNC('month', order_date) AS month,
        ship_mode,
        SUM(late_delivery) / COUNT(*) AS late_rate
    FROM purchase_orders
    WHERE order_date >= '2025-04-01' AND order_date < '2025-07-01'
    GROUP BY month, ship_mode
)
SELECT * FROM monthly_late_overall
UNION ALL
SELECT * FROM monthly_late_ship_mode
ORDER BY month, ship_mode;


-- 2. Top 5 suppliers by volume with their late_rate in the same window.
WITH filtered_purchase_orders AS (
    SELECT
        po.supplier_id,
        po.qty,
        d.late_delivery
    FROM purchase_orders po
    LEFT JOIN deliveries d ON po.order_id = d.order_id
    WHERE po.order_date >= '2025-04-01' AND po.order_date < '2025-07-01'
),
late_supplier_volume AS (
    SELECT
        supplier_id,
        SUM(qty) AS total_qty,
        SUM(late_delivery) / COUNT(*) AS late_rate
    FROM filtered_purchase_orders
    GROUP BY supplier_id
),
SELECT * FROM late_supplier_volume
ORDER BY total_qty DESC
LIMIT 5;


-- 3. For each order: supplier trailing 90‑day late rate strictly before order_date (windowed).
WITH supplier_late_rate AS (
    SELECT
        po.order_id,
        po.supplier_id,
        po.order_date,
        SUM(d.late_delivery) OVER (PARTITION BY po.supplier_id ORDER BY po.order_date 
                                   RANGE BETWEEN INTERVAL '90' DAY PRECEDING AND INTERVAL '1' DAY PRECEDING) AS late_count,
        COUNT(d.late_delivery) OVER (PARTITION BY po.supplier_id ORDER BY po.order_date 
                                     RANGE BETWEEN INTERVAL '90' DAY PRECEDING AND INTERVAL '1' DAY PRECEDING) AS total_count
    FROM purchase_orders po
    LEFT JOIN deliveries d ON po.order_id = d.order_id
)
SELECT
    order_id,
    supplier_id,
    order_date,
    CASE 
        WHEN total_count = 0 THEN NULL
        ELSE late_count::FLOAT / total_count
    END AS trailing_90_day_late_rate
FROM supplier_late_rate;


-- 4. Detect overlapping price windows per (supplier_id, sku).
WITH ranked_prices AS (
    SELECT
        supplier_id,
        sku,
        valid_from,
        valid_to,
        price_per_uom,
        currency,
        ROW_NUMBER() OVER (PARTITION BY supplier_id, sku ORDER BY valid_from, valid_to) AS rn
    FROM prices
), overlaps AS (
    SELECT
        p1.supplier_id,
        p1.sku,
        p1.valid_from AS p1_from,
        p1.valid_to   AS p1_to,
        p2.valid_from AS p2_from,
        p2.valid_to   AS p2_to,
        p1.price_per_uom AS p1_price,
        p2.price_per_uom AS p2_price,
        p1.currency AS p1_currency,
        p2.currency AS p2_currency
    FROM priced p1
    JOIN priced p2
      ON p1.supplier_id = p2.supplier_id
     AND p1.sku = p2.sku
     AND p1.rn < p2.rn
    WHERE p2.valid_from <= p1.valid_to
)
SELECT *
FROM overlaps
ORDER BY supplier_id, sku, p1_from;


-- 5. Attach valid price at order date, normalize to EUR (assume USD→EUR = 0.92), compute order_value_eur.
WITH po_with_prices AS (
    SELECT
        po.*,
        pr.price_per_uom,
        pr.currency AS price_currency
        pr.valid_from,
        pr.valid_to,
        ROW_NUMBER() OVER (PARTITION BY o.order_id ORDER BY p.valid_from DESC NULLS LAST) AS rn
    FROM purchase_orders po
    LEFT JOIN prices pr 
           ON po.sku = pr.sku
          AND po.order_date BETWEEN pr.valid_from AND pr.valid_to
)
SELECT
    order_id,
    order_date,
    supplier_id,
    sku,
    qty,
    COALESCE(price_per_uom, unit_price) AS chosen_price,
    COALESCE(price_currency, currency) AS chosen_price_currency,
    CASE 
        WHEN COALESCE(price_currency, currency) = 'USD' THEN COALESCE(price_per_uom, unit_price) * 0.92
        ELSE COALESCE(price_per_uom, unit_price)
    END AS chosen_price_eur,
    (CASE WHEN COALESCE(price_currency, currency) = 'USD' THEN COALESCE(price_per_uom, unit_price) * 0.92
          ELSE COALESCE(price_per_uom, unit_price)
     END) * qty AS order_value_eur
FROM po_with_prices
WHERE rn = 1;


-- 6. Flag price anomalies via z on ln(price_eur) per series; return top 10 |z|.
WITH normalized_prices AS (
    SELECT
        *,
        CASE 
            WHEN currency = 'USD' THEN price_per_uom * 0.92
            ELSE price_per_uom
        END AS price_per_uom_eur
    FROM prices
), WITH price_stats AS (
    SELECT
        supplier_id,
        sku,
        AVG(LN(price_per_uom_eur)) AS mean_log_price,
        STDDEV(LN(price_per_uom_eur)) AS stddev_log_price
    FROM normalized_prices
    GROUP BY supplier_id, sku
), WITH price_anomalies AS (
    SELECT
        *,
        CASE
            WHEN stddev_log_price IS NULL OR stddev_log_price = 0 THEN NULL
            ELSE (LN(price_per_uom_eur) - mean_log_price) / stddev_log_price
        END AS z_score
    FROM price_stats
)
SELECT * FROM price_anomalies
WHERE z_score IS NOT NULL
ORDER BY ABS(z_score) DESC
LIMIT 10;


-- 7. Incoterm × distance buckets: average delay_days and count in validation window.
WITH filtered_purchase_orders AS (
    SELECT
        po.incoterm,
        po.distance_km,
        d.delay_days
    FROM purchase_orders po
    LEFT JOIN deliveries d ON po.order_id = d.order_id
    WHERE po.order_date >= '2025-04-01' AND po.order_date < '2025-07-01'
), WITH distance_buckets AS (
    SELECT
        incoterm,
        distance_km,
        delay_days,
        CASE 
            WHEN distance < 200 THEN '<200km'
            WHEN distance BETWEEN 200 AND 550 THEN '200-550km'
            WHEN distance BETWEEN 551 AND 850 THEN '550-850km'
            WHEN distance BETWEEN 851 AND 1200 THEN '850-1200km'
            ELSE '>1200km'
        END AS distance_bucket
    FROM filtered_purchase_orders
), WITH incoterm_delay_stats AS (
    SELECT
        incoterm,
        distance_bucket,
        AVG(delay_days) AS avg_delay_days,
        COUNT(*) AS order_count
    FROM distance_buckets
    GROUP BY incoterm, distance_bucket
)
SELECT * FROM incoterm_delay_stats
ORDER BY incoterm, distance_bucket;


--8. Bonus: with predictions(order_id, p_late), bucket top 10% as high risk and compare late_rate vs. low risk.
WITH filtered_purchase_orders AS (
    SELECT
        po.order_id,
        po.order_date,
        d.late_delivery
    FROM purchase_orders po
    LEFT JOIN deliveries d ON po.order_id = d.order_id
), WITH predictions_with_late AS (
    SELECT
        p.order_id,
        p.p_late,
        f.late_delivery
    FROM predictions p
    JOIN filtered_purchase_orders f ON p.order_id = f.order_id
), WITH threshold AS (
    SELECT
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY p_late) AS p_late_threshold
    FROM predictions_with_late
), WITH risk_groups AS (
    SELECT
        pwl.*,
        CASE 
            WHEN pwl.p_late >= t.p_late_threshold THEN 'high_risk'
            ELSE 'low_risk'
        END AS risk_group
    FROM predictions_with_late pwl, threshold t
), WITH risk_stats AS (
    SELECT
        risk_group,
        SUM(late_delivery) / COUNT(*) AS late_rate
    FROM risk_groups
    GROUP BY risk_group
)
SELECT * FROM risk_stats;