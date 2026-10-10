public async Task<DashboardResumenDto> HandlerResumen(DashboardFiltro filtro, CancellationToken ct)
{
    var desde = new DateTime(filtro.Anio, 1, 1);
    var hasta = desde.AddYears(1);
    var desdeAnterior = desde.AddYears(-1);

    var q = _context.DashboardSolicitudes.AsQueryable();
    if (filtro.TipoMercado is not null) q = q.Where(x => x.TipoMercado == filtro.TipoMercado);

    // 0001
    var procesadas = await q.CountAsync(x => x.FechaApertura >= desde && x.FechaApertura < hasta, ct);

    // 0002 — sin filtro de mercado
    var conteos = await _context.DashboardSolicitudes
        .Where(x => x.FechaApertura >= desde && x.FechaApertura < hasta)
        .GroupBy(x => x.TipoMercado)
        .Select(g => new { Mercado = g.Key, Total = g.Count() })
        .OrderByDescending(x => x.Total)
        .ToListAsync(ct);

    var totalMercados = conteos.Sum(x => x.Total);   // no uses 'procesadas': esa sí trae el filtro
    var porMercado = conteos
        .Select(x => new MercadoConteoDto(x.Mercado, x.Total,
            totalMercados == 0 ? 0 : Math.Round(x.Total * 100m / totalMercados, 1)))
        .ToList();

    // 0009
    var porMes = await q
        .Where(x => x.FechaApertura >= desdeAnterior && x.FechaApertura < hasta)
        .GroupBy(x => new { x.FechaApertura!.Value.Year, x.FechaApertura!.Value.Month })
        .Select(g => new { g.Key.Year, g.Key.Month, Total = g.Count() })
        .ToListAsync(ct);

    var primera = await _context.DashboardSolicitudes.MinAsync(x => x.FechaApertura, ct);

    // KPI 0003
    var cerradas = _context.DashboardTiempos.Where(x =>
        x.FechaApertura >= desde && x.FechaApertura < hasta &&
        x.Situacion == SituacionSolicitud.Cerrada);
    if (filtro.TipoMercado is not null) cerradas = cerradas.Where(x => x.TipoMercado == filtro.TipoMercado);
    var promedioDias = await cerradas.AverageAsync(x => (double?)x.DiasHabiles, ct);

    return new DashboardResumenDto(
        procesadas,
        promedioDias is null ? null : Math.Round(promedioDias.Value / 5, 1),
        porMercado,
        Serie(filtro.Anio),
        Serie(filtro.Anio - 1));

    int?[] Serie(int anioSerie)
    {
        var hoy = DateTime.Today;   // misma zona horaria que las fechas de la vista
        var serie = new int?[12];
        for (var mes = 1; mes <= 12; mes++)
        {
            var inicioMes = new DateTime(anioSerie, mes, 1);
            var antesDelSistema = primera is null ||
                inicioMes < new DateTime(primera.Value.Year, primera.Value.Month, 1);
            var noCerrado = inicioMes.AddMonths(1) > hoy;   // mes en curso o futuro

            serie[mes - 1] = antesDelSistema || noCerrado
                ? null
                : porMes.FirstOrDefault(p => p.Year == anioSerie && p.Month == mes)?.Total ?? 0;
        }
        return serie;
    }
}