-- CONSULTA PARA CÁLCULO DE GASTOS PUBLICITARIOS

WITH last_paid_clicks AS (
    -- 1. Identificamos la sesión ganadora pura por cada visitante de forma aislada
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
    -- 2. Filtramos únicamente los clics ganadores definitivos
    SELECT visitor_id, visit_date, utm_source, utm_medium, utm_campaign
    FROM last_paid_clicks
    WHERE rn = 1
),
visitors_agg AS (
    -- 3. Contamos los visitantes únicos diarios por campaña de forma aislada
    SELECT 
        visit_date, utm_source, utm_medium, utm_campaign,
        COUNT(visitor_id) AS visitors_count
    FROM winning_sessions
    GROUP BY visit_date, utm_source, utm_medium, utm_campaign
),
leads_agg AS (
    -- 4. Contamos los leads e ingresos atribuidos de forma aislada
    SELECT 
        s.visit_date, s.utm_source, s.utm_medium, s.utm_campaign,
        COUNT(l.lead_id) AS leads_count,
        COUNT(CASE WHEN l.closing_reason = 'Completado con éxito' OR l.status_id = 142 THEN l.lead_id END) AS purchases_count,
        CAST(SUM(CASE WHEN l.closing_reason = 'Completado con éxito' OR l.status_id = 142 THEN l.amount END) AS INTEGER) AS revenue
    FROM winning_sessions s
    INNER JOIN leads l ON s.visitor_id = l.visitor_id AND l.created_at >= s.visit_date
    GROUP BY s.visit_date, s.utm_source, s.utm_medium, s.utm_campaign
),
marketing_costs AS (
    -- 5. Consolidamos los costos diarios de pauta publicitaria
    SELECT 
        campaign_date AS visit_date, utm_source, utm_medium, utm_campaign,
        SUM(daily_spent) AS total_cost
    FROM (
        SELECT campaign_date, utm_source, utm_medium, utm_campaign, daily_spent FROM ya_ads
        UNION ALL
        SELECT campaign_date, utm_source, utm_medium, utm_campaign, daily_spent FROM vk_ads
    ) ads
    GROUP BY campaign_date, utm_source, utm_medium, utm_campaign
),
base_universo AS (
    -- 6. Creamos el universo completo de llaves combinando todas las tablas para el FULL JOIN
    SELECT visit_date, utm_source, utm_medium, utm_campaign FROM visitors_agg
    UNION
    SELECT visit_date, utm_source, utm_medium, utm_campaign FROM leads_agg
    UNION
    SELECT visit_date, utm_source, utm_medium, utm_campaign FROM marketing_costs
)
-- 7. Consulta final unificando las piezas y formateando estrictamente la fecha
SELECT 
    TO_CHAR(b.visit_date, 'YYYY-MM-DD') AS visit_date, -- Fuerza el formato limpio libre de horas
    COALESCE(v.visitors_count, 0) AS visitors_count,
    b.utm_source,
    b.utm_medium,
    b.utm_campaign,
    CAST(c.total_cost AS INTEGER) AS total_cost,
    COALESCE(l.leads_count, 0) AS leads_count,
    COALESCE(l.purchases_count, 0) AS purchases_count,
    l.revenue
FROM base_universo b
LEFT JOIN visitors_agg v 
    ON b.visit_date = v.visit_date AND b.utm_source = v.utm_source AND b.utm_medium = v.utm_medium AND b.utm_campaign = v.utm_campaign
LEFT JOIN leads_agg l 
    ON b.visit_date = l.visit_date AND b.utm_source = l.utm_source AND b.utm_medium = l.utm_medium AND b.utm_campaign = l.utm_campaign
LEFT JOIN marketing_costs c 
    ON b.visit_date = c.visit_date AND b.utm_source = c.utm_source AND b.utm_medium = c.utm_medium AND b.utm_campaign = c.utm_campaign
ORDER BY 
    visit_date ASC,
    visitors_count DESC,
    utm_source ASC,
    utm_medium ASC,
    utm_campaign ASC,
    revenue DESC NULLS LAST;
