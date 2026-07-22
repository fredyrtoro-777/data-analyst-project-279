-- CONSULTA PARA CÁLCULO DE GASTOS PUBLICITARIOS

WITH last_paid_clicks AS (
    -- 1. Identificamos la sesión pagada ganadora por visitante
    SELECT 
        visitor_id,
        CAST(visit_date AS DATE) AS visit_date,
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
    -- 2. Filtramos únicamente los últimos clics pagados ganadores
    SELECT visitor_id, visit_date, utm_source, utm_medium, utm_campaign
    FROM last_paid_clicks
    WHERE rn = 1
),
sessions_metrics AS (
    -- 3. Agrupamos métricas de tráfico y conversiones por fecha y etiquetas
    SELECT 
        s.visit_date,
        s.utm_source,
        s.utm_medium,
        s.utm_campaign,
        COUNT(DISTINCT s.visitor_id) AS visitors_count,
        COUNT(DISTINCT l.lead_id) AS leads_count,
        COUNT(DISTINCT CASE WHEN l.closing_reason = 'Completado con éxito' OR l.status_id = 142 THEN l.lead_id END) AS purchases_count,
        CAST(SUM(CASE WHEN l.closing_reason = 'Completado con éxito' OR l.status_id = 142 THEN l.amount END) AS INTEGER) AS revenue
    FROM winning_sessions s
    LEFT JOIN leads l ON s.visitor_id = l.visitor_id 
        AND l.created_at >= s.visit_date
    GROUP BY s.visit_date, s.utm_source, s.utm_medium, s.utm_campaign
),
marketing_costs AS (
    -- 4. Consolidamos los costos diarios de Yandex y VK
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
-- 5. Unión e integración total usando FULL JOIN para capturar el 100% de la actividad publicitaria
SELECT 
    COALESCE(sm.visit_date, mc.visit_date) AS visit_date,
    COALESCE(sm.visitors_count, 0) AS visitors_count,
    COALESCE(sm.utm_source, mc.utm_source) AS utm_source,
    COALESCE(sm.utm_medium, mc.utm_medium) AS utm_medium,
    COALESCE(sm.utm_campaign, mc.utm_campaign) AS utm_campaign,
    CAST(mc.total_cost AS INTEGER) AS total_cost,
    COALESCE(sm.leads_count, 0) AS leads_count,
    COALESCE(sm.purchases_count, 0) AS purchases_count,
    sm.revenue
FROM sessions_metrics sm
FULL JOIN marketing_costs mc 
    ON sm.visit_date = mc.visit_date
    AND sm.utm_source = mc.utm_source
    AND sm.utm_medium = mc.utm_medium
    AND sm.utm_campaign = mc.utm_campaign
ORDER BY 
    visit_date ASC,
    visitors_count DESC,
    utm_source ASC,
    utm_medium ASC,
    utm_campaign ASC,
    revenue DESC NULLS LAST;
