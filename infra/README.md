# Infraestructura

La carpeta `infra` quedó ajustada al alcance real del repo:

- `expense-control-ui`: frontend en Next.js desplegado como contenedor.
- `expense-control-back`: backend en Go desplegado como contenedor.
- PostgreSQL administrado en RDS para persistencia.

La guia operativa de despliegue esta en
[`DEPLOYMENT.md`](/home/chelalo/projects/personal/expense-control/expense-control/infra/DEPLOYMENT.md).

## Topología `live/dev`

El entorno `infra/live/dev` ahora crea:

- VPC con subredes públicas y privadas.
- ALB público con enrutamiento por path:
  - `/` hacia el frontend.
  - `/api/*` hacia el backend.
- ECS Fargate para frontend y backend.
- Repositorios ECR para ambas imágenes.
- CloudWatch Logs para ambos servicios.
- RDS PostgreSQL en subredes privadas.
- IAM mínimo para que ECS lea secretos desde Secrets Manager.

La configuración operativa de observabilidad queda separada en
[`observability/`](/home/chelalo/projects/personal/expense-control/expense-control/observability/README.md).
Este stack puede consumir esas plantillas para desplegar observabilidad en AWS
de forma opcional.

## Secretos esperados

Terraform no genera secretos de aplicación. Deben existir en AWS Secrets Manager:

- `auth_session_secret_arn`: secreto plano para `AUTH_SESSION_SECRET`.
- `jwt_access_private_key_secret_arn`: PEM privado del access token.
- `jwt_access_public_key_secret_arn`: PEM público del access token.
- `jwt_refresh_private_key_secret_arn`: PEM privado del refresh token.
- `jwt_refresh_public_key_secret_arn`: PEM público del refresh token.

La contraseña de PostgreSQL la administra RDS automáticamente y se expone como output.

## Flujo sugerido

1. Crear el bucket de estado remoto de Terraform desde `infra/bootstrap`.
2. Configurar `infra/live/dev/backend.hcl`.
3. Copiar `infra/live/dev/terraform.tfvars.example` a `terraform.tfvars` y completar imágenes/ARNs.
4. Aplicar `infra/live/dev`.
5. Publicar imágenes en los repositorios ECR de salida.
6. Subir `frontend_desired_count` y `backend_desired_count` a `1` cuando las imágenes ya existan.

## Integración opcional con observabilidad

Si `enable_observability = true`, este entorno también crea:

- Grafana en ECS Fargate.
- Prometheus en ECS Fargate.
- Loki en ECS Fargate.
- Tempo en ECS Fargate.
- OpenTelemetry Collector en ECS Fargate.
- EFS para persistencia de Grafana, Prometheus, Loki y Tempo.
- Cloud Map para comunicación interna por DNS.
- Un ALB aparte para Grafana restringido por `observability_allowed_cidrs`.
- Los demás servicios de observabilidad quedan sin exposición pública y solo se
  alcanzan desde la VPC.

Cuando ese flag está apagado:

- no se crean recursos de observabilidad;
- frontend y backend siguen funcionando;
- el backend no exporta trazas salvo que le pases un `otel_exporter_otlp_endpoint` externo.

## Acceso a Grafana

Grafana queda detrás de un ALB propio y solo acepta tráfico desde
`observability_allowed_cidrs`.

Para restringirlo a ti, configura tu IP pública como `/32`, por ejemplo:

- `observability_allowed_cidrs = ["203.0.113.10/32"]`

Terraform también genera una contraseña aleatoria para el usuario admin de
Grafana y la expone como output sensible, además de guardarla en Secrets
Manager.

## Notas

- El backend ya no obliga a levantar OTEL para iniciar.
- `/api/metrics` queda bloqueado en el ALB público y Prometheus scrapea al backend por DNS interno.
- El backend en ECS recibe las llaves JWT como secretos y las materializa a archivos dentro del contenedor.
- Los `plan.out` y el servicio `users` venían del proyecto anterior y ya no forman parte de la topología activa.
