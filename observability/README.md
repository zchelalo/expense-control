# Observability

Esta carpeta concentra la configuración operativa de observabilidad del
proyecto.

- `local/`: stack local con Docker Compose.
- `aws/`: templates que `infra` usa para desplegar el stack self-hosted en AWS.

## Qué incluye

- Grafana
- Prometheus
- Loki
- Tempo
- OpenTelemetry Collector
- Promtail

## Uso local

1. Configura `expense-control-back/.env` con:
   `OTEL_EXPORTER_OTLP_ENDPOINT=expense-control-otel-collector:4317`
2. Crea la red compartida si no existe:
   `docker network create expense-control-network`
3. Levanta el backend:
   `docker compose -f expense-control-back/.docker/compose.yml up -d`
   En desarrollo, el compose del backend genera llaves JWT locales si faltan.
4. Levanta observabilidad:
   `docker compose --env-file observability/local/.env.example -f observability/local/compose.yml up -d`

Grafana queda en `http://localhost:3001` por defecto.

## Validación local

Prometheus debe ver el backend como `up=1`:

```bash
docker compose --env-file observability/local/.env.example -f observability/local/compose.yml exec -T expense-control-prometheus wget -qO- "http://localhost:9090/api/v1/query?query=up"
```

Para generar una traza y un log de prueba:

```bash
docker compose --env-file observability/local/.env.example -f observability/local/compose.yml exec -T expense-control-prometheus wget -S -O /dev/null http://expense-control-back:8000/api/v1/observability-check || true
```

La respuesta esperada para esa ruta es `404`; se usa porque igual genera log y
traza al pasar por el middleware de la aplicación.

En Grafana:

- `Explore > Prometheus`: consulta `up`.
- `Explore > Loki`: consulta `{service="expense-control-back"}`.
- `Explore > Tempo`: filtra por `Service Name = expense-control-back`.

## Limpieza de contenedores antiguos

Docker Compose no cachea servicios que ya no existan en el YAML, pero tampoco
elimina contenedores en ejecucion que quedaron de una version anterior.
`docker system prune` no borra contenedores activos.

Si ves servicios de observabilidad al levantar solo el backend, limpia los
orphans del compose anterior:

```bash
docker compose -p docker -f expense-control-back/.docker/compose.yml down --remove-orphans
docker compose -p local --env-file observability/local/.env.example -f observability/local/compose.yml down --remove-orphans
```

La red `expense-control-network` es externa para ambos compose. Si no existe,
creala una vez:

```bash
docker network create expense-control-network
```

Luego levanta de nuevo solo lo que necesitas:

```bash
docker compose -f expense-control-back/.docker/compose.yml up -d
docker compose --env-file observability/local/.env -f observability/local/compose.yml up -d
```

## Carácter opcional

Si no levantas este stack:

- El backend sigue funcionando.
- Las métricas siguen expuestas en `/api/metrics`.
- Los logs siguen saliendo por `stdout/stderr`.
- Las trazas simplemente no se exportan.

## AWS / Producción

La aplicación no depende obligatoriamente de esta carpeta para arrancar. En
producción puedes:

- no desplegar observabilidad y dejar `OTEL_EXPORTER_OTLP_ENDPOINT` vacío, o
- desplegar tu propio stack y apuntar el backend a su collector OTLP.

En este repo, el despliegue AWS del stack vive en `infra`, pero sus plantillas
de configuración viven aquí en `observability/aws`.

Si en AWS quieres que solo tú lo veas, habilita observabilidad en Terraform y
define `observability_allowed_cidrs` con tu IP pública en formato `/32`.
