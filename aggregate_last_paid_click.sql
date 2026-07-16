-- Resumen diario de gastos de marketing, clics, leads y retornos bajo Last Paid

WITH last_paid_clicks AS (
    SELECT 
        s.visitor_id,
        CAST(s.visit_date AS DATE) AS visit_date,
        s.source AS utm_source,
        s.medium AS utm_medium,
        s.campaign AS utm_campaign,
        l.lead_id,
        l.amount,
        l.closing_reason,
        l.status_id,
        ROW_NUMBER() OVER (
            PARTITION BY s.visitor_id 
            ORDER BY s.visit_date DESC
        ) AS rn
    FROM sessions s
    LEFT JOIN leads l ON s.visitor_id = l.visitor_id 
        AND l.created_at >= s.visit_date
    WHERE s.medium IN ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
),
sessions_metrics AS (
    SELECT 
        visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        COUNT(visitor_id) AS visitors_count,
        COUNT(lead_id) AS leads_count,
        COUNT(CASE WHEN closing_reason = 'Completado con éxito' OR status_id = 142 THEN 1 END) AS purchases_count,
        FLOOR(SUM(CASE WHEN closing_reason = 'Completado con éxito' OR status_id = 142 THEN amount END)) AS revenue
    FROM last_paid_clicks
    WHERE rn = 1
    GROUP BY visit_date, utm_source, utm_medium, utm_campaign
),
marketing_costs AS (
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
SELECT 
    sm.visit_date,
    sm.visitors_count,
    sm.utm_source,
    sm.utm_medium,
    sm.utm_campaign,
    COALESCE(mc.total_cost, 0) AS total_cost,
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
