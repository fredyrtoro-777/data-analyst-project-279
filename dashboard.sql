-- Consulta Cálculo de los gastos publicitarios


WITH last_paid_clicks AS (
    -- 1. Identificamos la sesión ganadora pura de cada visitante de forma aislada
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
    -- 2. Filtramos solo las últimas sesiones pagadas definitivas
    SELECT visitor_id, visit_date, utm_source, utm_medium, utm_campaign
    FROM last_paid_clicks
    WHERE rn = 1
),
sessions_metrics AS (
    -- 3. Ahora sí, unimos las sesiones ganadoras con los leads y agrupamos
    SELECT 
        s.visit_date,
        s.utm_source,
        s.utm_medium,
        s.utm_campaign,
        COUNT(s.visitor_id) AS visitors_count,
        COUNT(l.lead_id) AS leads_count,
        COUNT(CASE WHEN l.closing_reason = 'Completado con éxito' OR l.status_id = 142 THEN 1 END) AS purchases_count,
        FLOOR(SUM(CASE WHEN l.closing_reason = 'Completado con éxito' OR l.status_id = 142 THEN l.amount END)) AS revenue
    FROM winning_sessions s
    LEFT JOIN leads l ON s.visitor_id = l.visitor_id 
        AND l.created_at >= s.visit_date
    GROUP BY s.visit_date, s.utm_source, s.utm_medium, s.utm_campaign
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
-- 5. Unión final usando FULL JOIN corrigiendo el nombre del campo a mc.utm_campaign
SELECT 
    COALESCE(sm.visit_date, mc.visit_date) AS visit_date,
    COALESCE(sm.utm_source, mc.utm_source) AS utm_source,
    COALESCE(sm.utm_medium, mc.utm_medium) AS utm_medium,
    COALESCE(sm.utm_campaign, mc.utm_campaign) AS utm_campaign,
    COALESCE(sm.visitors_count, 0) AS visitors_count,
    COALESCE(mc.total_cost, 0) AS total_cost,
    COALESCE(sm.leads_count, 0) AS leads_count,
    COALESCE(sm.purchases_count, 0) AS purchases_count,
    COALESCE(sm.revenue, 0) AS revenue
FROM sessions_metrics sm
FULL JOIN marketing_costs mc ON sm.visit_date = mc.visit_date
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

-- CONSULTA CÁLCULO DEL # DE DÍAS REQUERIDOS PARA LLEGAR AL 90% DE VENTAS

WITH last_paid_clicks AS (
    -- 1. Identificamos la última sesión pagada ganadora por visitante
    SELECT 
        visitor_id,
        visit_date,
        ROW_NUMBER() OVER (
            PARTITION BY visitor_id 
            ORDER BY visit_date DESC
        ) AS rn
    FROM sessions
    WHERE medium IN ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
),
winning_sessions AS (
    SELECT visitor_id, visit_date 
    FROM last_paid_clicks 
    WHERE rn = 1
),
conversion_intervals AS (
    -- 2. Calculamos la diferencia exacta en días hasta que el lead se cierra con éxito
    SELECT 
        (l.created_at::date - s.visit_date::date) AS days_to_close
    FROM winning_sessions s
    INNER JOIN leads l ON s.visitor_id = l.visitor_id
    WHERE l.closing_reason = 'Completado con éxito' OR l.status_id = 142
),
days_distribution AS (
    -- 3. Agrupamos por días y contamos cuántas ventas se cerraron en ese tiempo
    SELECT 
        days_to_close,
        COUNT(*) AS closed_leads_count
    FROM conversion_intervals
    WHERE days_to_close >= 0 -- Filtro de seguridad para descartar inconsistencias de fechas
    GROUP BY days_to_close
)
-- 4. Calculamos el porcentaje acumulado para hallar el percentil 90
SELECT 
    days_to_close,
    closed_leads_count,
    ROUND(
        (SUM(closed_leads_count) OVER (ORDER BY days_to_close) * 100.0) / 
        SUM(closed_leads_count) OVER (), 2
    ) AS accumulated_percentage
FROM days_distribution
ORDER BY days_to_close;

