from __future__ import annotations

from collections import Counter, defaultdict
from datetime import UTC, datetime, timedelta
from functools import lru_cache
from statistics import fmean, median
from typing import Any

from app.core.registro import obtener_logger
from app.services.supabase_service import ServicioSupabase, obtener_supabase


registro = obtener_logger(__name__)


class ServicioAnalitica:
    def __init__(self) -> None:
        self.supabase: ServicioSupabase = obtener_supabase()

    def resumen(self, days: int = 30) -> dict[str, Any]:
        """Prefiere agregar en Postgres; si la migracion 004 no esta aplicada,
        cae en el calculo en Python de siempre."""
        try:
            respuesta = self.supabase.admin.rpc("metricas_resumen", {"dias": days}).execute()
            datos = respuesta.data
            if isinstance(datos, dict) and isinstance(datos.get("kpis"), dict):
                return datos
            registro.warning("metricas_resumen devolvio algo inesperado; se calcula en Python")
        except Exception as exc:
            registro.warning(
                "metricas_resumen no disponible; se calcula en Python",
                extra={"detalle": str(exc)[:200]},
            )
        return self._resumen_en_python(days)

    def _resumen_en_python(self, days: int = 30) -> dict[str, Any]:
        since = datetime.now(UTC) - timedelta(days=days)
        response = (
            self.supabase.admin.table("questions")
            .select("id,user_id,question,normalized_question,status,latency_ms,retrieval_ms,generation_ms,top_similarity,created_at")
            .gte("created_at", since.isoformat())
            .order("created_at", desc=True)
            .limit(10000)
            .execute()
        )
        rows = response.data or []
        answered = [row for row in rows if row["status"] == "answered"]
        latencies = [row["latency_ms"] for row in rows if row.get("latency_ms") is not None]
        daily: dict[str, dict[str, Any]] = defaultdict(lambda: {"count": 0, "latencies": []})
        for row in rows:
            day = str(row["created_at"])[:10]
            daily[day]["count"] += 1
            if row.get("latency_ms") is not None:
                daily[day]["latencies"].append(row["latency_ms"])

        recurrent = Counter(row["normalized_question"] for row in rows if row.get("normalized_question"))
        display_question: dict[str, str] = {}
        for row in reversed(rows):
            display_question[row.get("normalized_question", "")] = row.get("question", "")

        user_count = self.supabase.admin.table("profiles").select("id", count="exact").execute().count or 0
        document_count = (
            self.supabase.admin.table("documents").select("id", count="exact").eq("status", "active").execute().count or 0
        )
        open_alerts = (
            self.supabase.admin.table("alerts").select("id", count="exact").eq("status", "open").execute().count or 0
        )
        def mediana(campo: str) -> int:
            valores = [row[campo] for row in rows if row.get(campo) is not None]
            return round(median(valores)) if valores else 0

        total_p50 = mediana("latency_ms")
        busqueda_p50 = mediana("retrieval_ms")
        generacion_p50 = mediana("generation_ms")

        def percentil95(valores: list[int]) -> int:
            if not valores:
                return 0
            ordenados = sorted(valores)
            indice = min(len(ordenados) - 1, int(round(0.95 * (len(ordenados) - 1))))
            return ordenados[indice]

        return {
            "period_days": days,
            "timing": {
                "total_p50": total_p50,
                "retrieval_p50": busqueda_p50,
                "generation_p50": generacion_p50,
                "other_p50": max(total_p50 - busqueda_p50 - generacion_p50, 0),
            },
            "kpis": {
                "questions": len(rows),
                "answer_rate": round(len(answered) * 100 / len(rows), 1) if rows else 0,
                "average_latency_ms": round(fmean(latencies)) if latencies else 0,
                "p95_latency_ms": percentil95(latencies),
                "users": user_count,
                "documents": document_count,
                "open_alerts": open_alerts,
            },
            "daily": [
                {
                    "date": day,
                    "questions": values["count"],
                    "average_latency_ms": round(fmean(values["latencies"])) if values["latencies"] else 0,
                }
                for day, values in sorted(daily.items())
            ],
            "recurrent_questions": [
                {"question": display_question[key], "count": count}
                for key, count in recurrent.most_common(10)
            ],
            "recent_questions": rows[:20],
        }


@lru_cache
def obtener_servicio_analitica() -> ServicioAnalitica:
    return ServicioAnalitica()
