
CREATE OR ALTER FUNCTION dbo.fn_DiasHabiles (@Inicio DATETIME2, @Fin DATETIME2)
RETURNS TABLE
AS
RETURN
WITH L0 AS (SELECT 1 AS c FROM (VALUES (1),(1),(1),(1),(1),(1),(1),(1),(1),(1)) v(c)),
     L1 AS (SELECT 1 AS c FROM L0 a CROSS JOIN L0 b),  
     L2 AS (SELECT 1 AS c FROM L1 a CROSS JOIN L1 b),  
     Dias AS (
        SELECT TOP (CASE WHEN DATEDIFF(DAY, CAST(@Inicio AS date), CAST(@Fin AS date)) > 0
                         THEN DATEDIFF(DAY, CAST(@Inicio AS date), CAST(@Fin AS date)) ELSE 0 END)
               DATEADD(DAY, CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS int),
                       CAST(@Inicio AS date)) AS Fecha          
        FROM L2
     )
SELECT COUNT(*) AS DiasHabiles
FROM Dias d
WHERE DATEDIFF(DAY, CAST('19000101' AS date), d.Fecha) % 7 < 5  
  AND NOT EXISTS (SELECT 1 FROM dbo.TDiaFestivo f
                  WHERE f.Activo = 1 AND CAST(f.Fecha AS date) = d.Fecha);