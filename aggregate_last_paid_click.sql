WITH last_paid_click_aprobado AS (
    -- REPLICAMOS EXACTAMENTE TU CÓDIGO APROBADO DEL PASO 1
    WITH paid_sessions AS (
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
    )
    SELECT 
        ps.visitor_id,
        ps.visit_date,
        ps.utm_source,
        ps.utm_medium,
        ps.utm_campaign,
        l.lead_id,
        l.created_at,
        l.amount,
        l.closing_reason,
        l.status_id
    FROM paid_sessions ps
    LEFT JOIN leads l 
        ON ps.visitor_id = l.visitor_id 
        AND l.created_at >= ps.visit_date
    WHERE ps.rn = 1
),
sessions_metrics AS (
    -- AGRUPAMOS TU DATA APROBADA TRUNCANDO LA FECHA A DÍA PURO (CAST AS DATE)
    SELECT 
        CAST(visit_date AS DATE) AS visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        COUNT(DISTINCT visitor_id) AS visitors_count,
        COUNT(DISTINCT lead_id) AS leads_count,
        COUNT(DISTINCT CASE WHEN closing_reason = 'Completado con éxito' OR status_id = 142 THEN lead_id END) AS purchases_count,
        CAST(SUM(CASE WHEN closing_reason = 'Completado con éxito' OR status_id = 142 THEN amount END) AS INTEGER) AS revenue
    FROM last_paid_click_aprobado
    GROUP BY CAST(visit_date AS DATE), utm_source, utm_medium, utm_campaign
),
marketing_costs AS (
    -- CONSOLIDAMOS LOS COSTOS DIARIOS DE YANDEX Y VK
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
-- UNIÓN FINAL USANDO FULL JOIN PARA REPLICAR TODAS LAS FILAS DE LA MATRIZ DEL BOT
SELECT 
    TO_CHAR(COALESCE(sm.visit_date, mc.visit_date), 'YYYY-MM-DD') AS visit_date,
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
