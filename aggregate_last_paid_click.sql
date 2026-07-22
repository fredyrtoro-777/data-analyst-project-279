-- CONSULTA PARA CÁLCULO DE GASTOS PUBLICITARIOS

WITH last_paid_clicks AS (
    -- 1. Identificamos la sesión pagada ganadora definitiva por cada visitante
    SELECT 
        visitor_id,
        visit_date,
        source AS utm_source,
        medium AS utm_medium,
        campaign AS utm_campaign,
        ROW_NUMBER() OVER (
            PARTITION BY visitor_id 
            ORDER BY visit_date DESC
        ) AS rn
    FROM sessions
    WHERE medium IN ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
),
winning_sessions AS (
    -- 2. Filtramos únicamente las sesiones ganadoras
    SELECT visitor_id, visit_date, utm_source, utm_medium, utm_campaign
    FROM last_paid_clicks
    WHERE rn = 1
),
conversions AS (
    -- 3. Atribuimos los leads e ingresos a las sesiones ganadoras (sin amarrar el día del lead)
    SELECT 
        s.visitor_id,
        CAST(s.visit_date AS DATE) AS visit_date,
        s.utm_source,
        s.utm_medium,
        s.utm_campaign,
        l.lead_id,
        CASE WHEN l.closing_reason = 'Completado con éxito' OR l.status_id = 142 THEN l.lead_id END AS purchase_id,
        CASE WHEN l.closing_reason = 'Completado con éxito' OR l.status_id = 142 THEN l.amount END AS purchase_amount
    FROM winning_sessions s
    LEFT JOIN leads l ON s.visitor_id = l.visitor_id 
        AND l.created_at >= s.visit_date
),
sessions_metrics AS (
    -- 4. Agrupamos visitas, leads y ventas basándonos únicamente en la fecha del clic original
    SELECT 
        visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        COUNT(DISTINCT visitor_id) AS visitors_count,
        COUNT(DISTINCT lead_id) AS leads_count,
        COUNT(DISTINCT purchase_id) AS purchases_count,
        CAST(SUM(purchase_amount) AS INTEGER) AS revenue
    FROM conversions
    GROUP BY visit_date, utm_source, utm_medium, utm_campaign
),
marketing_costs AS (
    -- 5. Consolidamos los costos diarios de las campañas publicitarias
    SELECT 
        campaign_date AS visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        SUM(daily_spent) AS total_cost
    FROM (
        SELECT campaign_date, utm_source, utm_medium, utm_campaign, daily_spent FROM ya_ads
        UNION ALL
        SELECT campaign_date, utm_source, utm_medium, utm_campaign, daily_spent FROM vk_ads
    ) ads
    GROUP BY campaign_date, utm_source, utm_medium, utm_campaign
)
-- 6. Unión final mediante LEFT JOIN (partiendo de las visitas) con ordenamiento oficial
SELECT 
    sm.visit_date,
    sm.visitors_count,
    sm.utm_source,
    sm.utm_medium,
    sm.utm_campaign,
    CAST(mc.total_cost AS INTEGER) AS total_cost,
    sm.leads_count,
    sm.purchases_count,
    sm.revenue
FROM sessions_metrics sm
LEFT JOIN marketing_costs mc 
    ON sm.visit_date = mc.visit_date
    AND sm.utm_source = mc.utm_source
    AND sm.utm_medium = mc.utm_medium
    AND sm.utm_campaign = mc.utm_campaign
ORDER BY 
    sm.visit_date ASC,
    sm.visitors_count DESC,
    sm.utm_source ASC,
    sm.utm_medium ASC,
    sm.utm_campaign ASC,
    sm.revenue DESC NULLS LAST;
