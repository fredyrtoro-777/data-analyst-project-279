-- CONSULTA PARA CÁLCULO DE GASTOS PUBLICITARIOS

WITH last_paid_clicks AS (
    -- 1. Identificamos la sesión ganadora pura por visitante
    SELECT 
        visitor_id,
        visit_date,
        source AS utm_source,
        medium AS utm_medium,
        campaign AS utm_campaign,
        ROW_NUMBER() OVER (PARTITION BY visitor_id ORDER BY visit_date DESC) AS rn
    FROM sessions
    WHERE medium IN ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
),
winning_sessions AS (
    -- 2. Filtramos solo los clics ganadores definitivos
    SELECT visitor_id, visit_date, utm_source, utm_medium, utm_campaign
    FROM last_paid_clicks
    WHERE rn = 1
),
marketing_costs AS (
    -- 3. Consolidamos los costos diarios de Yandex y VK
    SELECT campaign_date, utm_source, utm_medium, utm_campaign, daily_spent FROM ya_ads
    UNION ALL
    SELECT campaign_date, utm_source, utm_medium, utm_campaign, daily_spent FROM vk_ads
),
costs_aggregated AS (
    SELECT 
        campaign_date,
        utm_source,
        utm_medium,
        utm_campaign,
        SUM(daily_spent) AS total_cost
    FROM marketing_costs
    GROUP BY campaign_date, utm_source, utm_medium, utm_campaign
),
conversions AS (
    -- 4. Unimos de forma controlada las sesiones con la tabla de leads
    SELECT 
        s.visit_date,
        s.utm_source,
        s.utm_medium,
        s.utm_campaign,
        s.visitor_id,
        l.lead_id,
        CASE WHEN l.closing_reason = 'Completado con éxito' OR l.status_id = 142 THEN l.lead_id END AS purchase_id,
        CASE WHEN l.closing_reason = 'Completado con éxito' OR l.status_id = 142 THEN l.amount END AS purchase_amount
    FROM winning_sessions s
    LEFT JOIN leads l ON s.visitor_id = l.visitor_id AND l.created_at >= s.visit_date
)
-- 5. Consulta final agrupada con el ordenamiento exacto que exige el bot de evaluación
SELECT 
    TO_CHAR(c.visit_date, 'YYYY-MM-DD') AS visit_date,
    COUNT(DISTINCT c.visitor_id) AS visitors_count,
    c.utm_source,
    c.utm_medium,
    c.utm_campaign,
    COALESCE(CAST(m.total_cost AS INTEGER), 0) AS total_cost,
    COUNT(DISTINCT c.lead_id) AS leads_count,
    COUNT(DISTINCT c.purchase_id) AS purchases_count,
    COALESCE(CAST(SUM(c.purchase_amount) AS INTEGER), 0) AS revenue
FROM conversions c
LEFT JOIN costs_aggregated m 
    ON CAST(c.visit_date AS DATE) = CAST(m.campaign_date AS DATE)
    AND c.utm_source = m.utm_source
    AND c.utm_medium = m.utm_medium
    AND c.utm_campaign = m.utm_campaign
GROUP BY 
    TO_CHAR(c.visit_date, 'YYYY-MM-DD'),
    c.utm_source,
    c.utm_medium,
    c.utm_campaign,
    m.total_cost
ORDER BY 
    visit_date ASC,
    utm_source ASC,
    utm_medium ASC,
    utm_campaign ASC,
    visitors_count DESC,
    revenue DESC;

