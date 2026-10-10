

CREATE OR ALTER VIEW dbo.vw_DashboardSolicitud
AS
SELECT
    s.Id                    AS SolicitudId,
    s.Folio,
    s.ClienteId,

    va.Id                   AS VersionActualId,
    va.NumeroVersion        AS NumeroVersionActual,
    nv.TotalVersiones,
    va.Estatus              AS EstatusActual,      -- int -> EstatusSolicitud en C#

    ig.TipoMercado,                                -- int -> TipoMercado en C# (inmutable)
    ig.NombreProyecto,

    ap.FechaApertura,                              -- paso a Abierto en la v1
    ci.FechaCierre,                                -- paso a Finalizada/Rechazado en la versión actual

    CASE
        WHEN ap.FechaApertura IS NULL THEN 'SinAbrir'    -- nunca salió de Borrador
        WHEN va.Estatus IN (14, 15)    THEN 'Cerrada'     -- Finalizada, Rechazado (supuesto 4)
        WHEN va.Estatus = 4            THEN 'NoFactible'  -- no cuenta como cierre
        ELSE                                'EnCurso'
    END                     AS Situacion

FROM dbo.TSolicitud s

-- Versión actual. Ver índice UX_TSolicitudVersion_Actual abajo: sin él,
-- dos versiones con EsActual = 1 duplicarían la solicitud en todos los conteos.
JOIN dbo.TSolicitudVersion va
    ON  va.SolicitudId = s.Id
    AND va.EsActual = 1

-- TipoMercado es inmutable, así que la versión actual basta.
LEFT JOIN dbo.TSolicitudInfoGeneral ig
    ON ig.SolicitudVersionId = va.Id

CROSS APPLY (
    SELECT COUNT(*) AS TotalVersiones
    FROM dbo.TSolicitudVersion v
    WHERE v.SolicitudId = s.Id
) nv

-- Apertura: primera vez que la v1 entró a Abierto.
OUTER APPLY (
    SELECT MIN(h.FechaInicio) AS FechaApertura
    FROM dbo.TSolicitudVersion v1
    JOIN dbo.TSolicitudEstatusHistorial h
        ON h.SolicitudVersionId = v1.Id
    WHERE v1.SolicitudId   = s.Id
      AND v1.NumeroVersion = 1
      AND h.EstatusNuevo   = 1            -- Abierto
) ap

-- Cierre: la transición hacia el estatus terminal en el que está hoy la versión actual.
OUTER APPLY (
    SELECT MAX(h.FechaInicio) AS FechaCierre
    FROM dbo.TSolicitudEstatusHistorial h
    WHERE h.SolicitudVersionId = va.Id
      AND h.EstatusNuevo       = va.Estatus
      AND va.Estatus IN (14, 15)
) ci;
GO

/* ---------------------------------------------------------------------
   ZONA HORARIA (solo si las fechas se guardan en UTC)
   Reemplaza en el SELECT:
     ap.FechaApertura  por
       CAST(ap.FechaApertura AT TIME ZONE 'UTC'
            AT TIME ZONE 'Central Standard Time (Mexico)' AS datetime2) AS FechaApertura
   y lo mismo para ci.FechaCierre. Hacerlo aquí lo resuelve una sola vez
   para todos los SP (agrupación por mes y días hábiles contra festivos).
   --------------------------------------------------------------------- */


/* ---------------------------------------------------------------------
   ÍNDICES DE SOPORTE
   EF ya crea índices sobre las FK; estos cubren los filtros de la vista.
   --------------------------------------------------------------------- */

-- Garantiza una sola versión actual por solicitud (integridad + conteos correctos).
-- Si falla al crearlo, ya hay datos duplicados que corregir primero.
CREATE UNIQUE INDEX UX_TSolicitudVersion_Actual
    ON dbo.TSolicitudVersion (SolicitudId)
    WHERE EsActual = 1;

CREATE INDEX IX_TSolicitudVersion_Solicitud_Numero
    ON dbo.TSolicitudVersion (SolicitudId, NumeroVersion)
    INCLUDE (EsActual, Estatus);

CREATE INDEX IX_TSolicitudEstatusHistorial_Version_Estatus
    ON dbo.TSolicitudEstatusHistorial (SolicitudVersionId, EstatusNuevo)
    INCLUDE (FechaInicio);
GO


/* ---------------------------------------------------------------------
   VALIDACIÓN RÁPIDA
   0001, 0002 y 0009 cuentan toda solicitud abierta, incluidas NoFactible.
   Solo 0003 las excluye.
   --------------------------------------------------------------------- */
DECLARE @Anio int = YEAR(SYSDATETIME());

-- 0) Distribución general: revisa que no haya 'SinAbrir' inesperadas
SELECT Situacion, COUNT(*) AS Solicitudes
FROM dbo.vw_DashboardSolicitud
GROUP BY Situacion;

-- 1) U-REQ-0001 · Procesadas en el año
SELECT COUNT(*) AS Procesadas
FROM dbo.vw_DashboardSolicitud
WHERE FechaApertura >= DATEFROMPARTS(@Anio, 1, 1)
  AND FechaApertura <  DATEFROMPARTS(@Anio + 1, 1, 1);

-- 2) U-REQ-0002 · RFQ por mercado (1 Hot · 2 HVAC · 3 AUTO · 4 TANKCAR)
SELECT TipoMercado, COUNT(*) AS Solicitudes
FROM dbo.vw_DashboardSolicitud
WHERE FechaApertura >= DATEFROMPARTS(@Anio, 1, 1)
  AND FechaApertura <  DATEFROMPARTS(@Anio + 1, 1, 1)
GROUP BY TipoMercado
ORDER BY Solicitudes DESC;

-- 3) U-REQ-0009 · Volumen por mes, año actual y anterior
SELECT YEAR(FechaApertura)  AS Anio,
       MONTH(FechaApertura) AS Mes,
       COUNT(*)             AS Solicitudes
FROM dbo.vw_DashboardSolicitud
WHERE FechaApertura >= DATEFROMPARTS(@Anio - 1, 1, 1)
  AND FechaApertura <  DATEFROMPARTS(@Anio + 1, 1, 1)
GROUP BY YEAR(FechaApertura), MONTH(FechaApertura)
ORDER BY Anio, Mes;

-- 4) U-REQ-0003 · Muestra del cálculo de semanas (requiere dbo.fn_DiasHabiles)
SELECT TOP (20)
       v.Folio, v.TotalVersiones, v.Situacion, v.FechaApertura, v.FechaCierre,
       dh.DiasHabiles,
       CAST(dh.DiasHabiles / 5.0 AS decimal(6, 1)) AS Semanas
FROM dbo.vw_DashboardSolicitud v
CROSS APPLY dbo.fn_DiasHabiles(v.FechaApertura, ISNULL(v.FechaCierre, SYSDATETIME())) dh
WHERE v.Situacion IN ('Cerrada', 'EnCurso')
ORDER BY dh.DiasHabiles DESC;
