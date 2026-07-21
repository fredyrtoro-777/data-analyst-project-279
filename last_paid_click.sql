WITH paid_sessions AS (
    SELECT 
        visitor_id,
        visit_date,
        source AS utm_source,
        medium AS utm_medium,
        campaign AS utm_campaign,
        -- Enumeramos las visitas de cada usuario de la más reciente a la más antigua
        ROW_NUMBER() OVER (
            PARTITION BY visitor_id 
            ORDER BY visit_date DESC
        ) AS rn
    FROM sessions
    -- Filtro estricto de solo canales pagados
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
    -- El lead debe crearse en el momento o después de la visita atribuida
    AND l.created_at >= ps.visit_date
-- Nos quedamos únicamente con el ÚLTIMO clic pagado de cada visitante
WHERE ps.rn = 1
-- Orden requerido por el proyecto
ORDER BY 
    l.amount DESC NULLS LAST,
    ps.visit_date ASC,
    ps.utm_source ASC,
    ps.utm_medium ASC,
    ps.utm_campaign ASC;
