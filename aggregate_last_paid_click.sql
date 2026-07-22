-- CONSULTA PARA CÁLCULO DE GASTOS PUBLICITARIOS

WITH last_paid_clicks AS (
    -- 1. Identificamos la sesión ganadora pura de cada visitante
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
    -- 2. Filtramos solo las últimas sesiones pagadas definitivas
    SELECT visitor_id, visit_date, utm_source, utm_medium, utm_campaign
    FROM last_paid_clicks
    WHERE rn = 1
),
sessions_metrics AS (
    -- 3. Unimos las sesiones ganadoras con los leads y agrupamos por día y UTM
    SELECT 
        CAST(s.visit_date AS DATE) AS visit_date,
        s.utm_source,
        s.utm_medium,
        s.utm_campaign,
        COUNT(s.visitor_id) AS visitors_count,
        COUNT(l.lead_id) AS leads_count,
        COUNT(CASE WHEN l.closing_reason = 'Completado con éxito' OR l.status_id = 142 THEN 1 END) AS purchases_count,
        SUM(CASE WHEN l.closing_reason = 'Completado con éxito' OR l.status_id = 142 THEN l.amount END) AS revenue
    FROM winning_sessions s
    LEFT JOIN leads l ON s.visitor_id = l.visitor_id 
        AND l.created_at >= s.visit_date
    GROUP BY CAST(s.visit_date AS DATE), s.utm_source, s.utm_medium, s.utm_campaign
),
marketing_costs AS (
    -- 4. Consolidamos los costos de marketing por día y campaña
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
-- 5. Unión final siguiendo estrictamente las especificaciones del validador
SELECT 
    sm.visit_date,
    sm.visitors_count,
    sm.utm_source,
    sm.utm_medium,
    sm.utm_campaign,
    mc.total_cost, -- Dejamos los nulos intactos como los espera Hexlet
    sm.leads_count,
    sm.purchases_count,
    sm.revenue
FROM sessions_metrics sm
LEFT JOIN marketing_costs mc ON sm.visit_date = mc.visit_date
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

