# Guia de despliegue

Esta guia cubre el despliegue local con observabilidad y el despliegue en AWS
de la UI, el backend, PostgreSQL y el stack opcional de observabilidad.

## Alcance

La aplicacion se compone de:

- `expense-control-ui`: frontend Next.js.
- `expense-control-back`: backend Go.
- PostgreSQL: RDS en AWS, Postgres container en local.
- Observabilidad: Grafana, Prometheus, Loki, Tempo y OpenTelemetry Collector.

En AWS, la observabilidad es opcional con `enable_observability`. Si esta
apagada, la aplicacion sigue funcionando y los contenedores usan CloudWatch
Logs. Si esta encendida, backend y frontend mandan logs a Loki, el backend
manda trazas al Collector y Prometheus scrapea `/api/metrics` por DNS interno.

## Local

1. Prepara el backend:

```bash
cd expense-control-back
cp .env.example .env
make create-keys
```

1. Si quieres ver trazas localmente, agrega estas variables a
   `expense-control-back/.env`:

```dotenv
OTEL_EXPORTER_OTLP_ENDPOINT=expense-control-otel-collector:4317
OTEL_TRACES_SAMPLER_RATIO=1
```

1. Levanta backend, base de datos y Adminer:

```bash
docker network create expense-control-network
docker compose -f expense-control-back/.docker/compose.yml up -d --build
```

Ese compose ahora espera a PostgreSQL y aplica migraciones automaticamente
antes de arrancar el backend. No necesitas correr `make migrate-up` para un
arranque local normal.

1. Levanta observabilidad:

```bash
docker compose --env-file observability/local/.env.example -f observability/local/compose.yml up -d
```

1. Abre Grafana:

```text
http://localhost:3001
user: admin
password: admin
```

Comprobaciones locales:

- Logs en Loki: usa una query como `{service="expense-control-back"}`.
- Trazas en Tempo: busca el servicio `expense-control-back`.
- Metricas en Prometheus: revisa el target `expense-control-back`.
- Correlacion log-trace: los logs del backend incluyen `trace_id` cuando la
  request esta instrumentada.

Notas locales:

- `/api/health` y `/api/metrics` no generan trazas ni logs HTTP de request.
- Promtail lee logs desde Docker; en Linux necesita acceso a
  `/var/run/docker.sock` y `/var/lib/docker/containers`.
- El frontend local no esta incluido en el compose del backend. Si lo corres
  con `npm run dev`, sus logs quedan en tu terminal, no en Loki.
- Si aparecen servicios de observabilidad al levantar solo el backend, no es
  cache del YAML: limpia orphans con
  `docker compose -p docker -f expense-control-back/.docker/compose.yml down --remove-orphans`.

## AWS: prerequisitos

Necesitas:

- Terraform instalado.
- AWS CLI autenticado contra la cuenta correcta.
- Permisos para crear VPC, ALB, ECS, ECR, RDS, EFS, Cloud Map, IAM,
  CloudWatch Logs, Secrets Manager, ACM y Route 53.
- Un bucket S3 para estado remoto, creado con `infra/bootstrap`.
- Secretos de aplicacion en AWS Secrets Manager.

Secretos requeridos:

- `auth_session_secret_arn`: secreto plano para `AUTH_SESSION_SECRET`.
- `jwt_access_private_key_secret_arn`: PEM privado para access token.
- `jwt_access_public_key_secret_arn`: PEM publico para access token.
- `jwt_refresh_private_key_secret_arn`: PEM privado para refresh token.
- `jwt_refresh_public_key_secret_arn`: PEM publico para refresh token.

Los secretos JWT deben guardar el contenido PEM plano, no JSON ni valores
escapados. Deben conservar los saltos de linea y encabezados como
`-----BEGIN RSA PRIVATE KEY-----` o `-----BEGIN PUBLIC KEY-----`.

La password de PostgreSQL la genera RDS. La password admin de Grafana la genera
Terraform cuando `enable_observability = true`.

## AWS: bootstrap del estado remoto

1. Crea variables desde el ejemplo:

```bash
cp infra/bootstrap/terraform.tfvars.example infra/bootstrap/terraform.tfvars
```

1. Ajusta bucket y region.

2. Aplica bootstrap:

```bash
cd infra/bootstrap
terraform init
terraform plan -out=plan.out
terraform apply plan.out
```

## AWS: configurar entorno

El codigo actual vive en `infra/live/dev`, pero `environment` es variable. Para
produccion usa `environment = "prod"` y un backend state separado.

Ejemplo de `backend.hcl` para prod:

```hcl
bucket         = "expense-control-terraform-states"
key            = "expense-control/prod/terraform.tfstate"
region         = "us-east-1"
use_lockfile   = true
```

Para inicializar `infra/live/dev`, no ejecutes `terraform init` solo. Usa el
archivo `backend.hcl` para pasar tambien la region del backend S3:

```bash
cd infra/live/dev
terraform init -backend-config=backend.hcl
```

## AWS: deploy exacto de este repo

La configuracion actual de [infra/live/dev/terraform.tfvars](/home/chelalo/projects/personal/expense-control/expense-control/infra/live/dev/terraform.tfvars)
ya quedo preparada para:

- `environment = "dev"`
- `route53_zone_name = "chelalo.me"`
- `app_domain_name = "expense-control-dev.chelalo.me"`
- `frontend_desired_count = 0`
- `backend_desired_count = 0`
- observabilidad AWS desactivada (`enable_observability = false`)

Eso significa que el primer `apply` crea la red, RDS, ALB, Route 53, ACM, ECS
y ECR, pero no intenta levantar contenedores hasta que hayas subido las
imagenes.

Si tambien quieres desplegar Grafana, Prometheus, Loki, Tempo y Collector en
AWS, cambia `enable_observability = true` antes del Paso 1. Si lo dejas como
esta ahora, el despliegue levanta solo app, backend, base de datos y
CloudWatch Logs.

### Paso 1: inicializar y crear infraestructura base

```bash
cd infra/live/dev
terraform init -backend-config=backend.hcl
terraform validate
terraform plan -out=plan.out
terraform apply plan.out
```

### Paso 2: confirmar dominio y repositorios ECR

```bash
terraform output frontend_url
terraform output api_url
terraform output frontend_ecr_repository_url
terraform output backend_ecr_repository_url
```

Espera que `frontend_url` sea:

```text
https://expense-control-dev.chelalo.me
```

Si ACM sigue validando, Route 53 y el certificado pueden tardar unos minutos en
quedar completamente activos, pero no necesitas hacer nada manual porque
Terraform crea los registros DNS de validacion.

### Paso 3: autenticar Docker contra ECR

Desde la raiz del repo:

```bash
cd /home/chelalo/projects/personal/expense-control/expense-control

AWS_REGION=us-east-1
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
```

### Paso 4: build y push del backend

```bash
BACKEND_REPO=$(terraform -chdir=infra/live/dev output -raw backend_ecr_repository_url)

docker build -t expense-control-back:latest ./expense-control-back
docker tag expense-control-back:latest "$BACKEND_REPO:latest"
docker push "$BACKEND_REPO:latest"
```

El backend ya corre migraciones automaticamente al arrancar en ECS. No hace
falta ejecutar `run-migrations.sh` a mano en un redeploy normal.

### Paso 5: build y push del frontend con la URL final

```bash
FRONTEND_REPO=$(terraform -chdir=infra/live/dev output -raw frontend_ecr_repository_url)
FRONTEND_API_URL=$(terraform -chdir=infra/live/dev output -raw api_url)

docker build \
  --build-arg API_URL="$FRONTEND_API_URL" \
  --build-arg NEXT_PUBLIC_API_URL="$FRONTEND_API_URL" \
  -t expense-control-ui:latest \
  ./expense-control-ui

docker tag expense-control-ui:latest "$FRONTEND_REPO:latest"
docker push "$FRONTEND_REPO:latest"
```

### Paso 6: activar frontend y backend

Sube los `desired_count` en el mismo `terraform.tfvars`:

```hcl
frontend_desired_count = 1
backend_desired_count  = 1
```

Si quieres hacerlo sin abrir editor, usa:

```bash
perl -0pi -e 's/frontend_desired_count = 0/frontend_desired_count = 1/' infra/live/dev/terraform.tfvars
perl -0pi -e 's/backend_desired_count  = 0/backend_desired_count  = 1/' infra/live/dev/terraform.tfvars
```

### Paso 7: aplicar el despliegue final

```bash
cd infra/live/dev
terraform plan -out=plan.out
terraform apply plan.out
```

### Paso 8: validar

```bash
terraform output frontend_url
terraform output api_url
terraform output ecs_cluster_name
terraform output backend_service_name
```

Abre:

```text
https://expense-control-dev.chelalo.me
```

Registro y login ya deberian funcionar sin pasos adicionales. Si quieres revisar
logs del backend despues del despliegue:

```bash
aws logs tail /ecs/expense-control-dev-backend --region us-east-1 --since 10m
```

Ejemplo minimo de variables relevantes:

```hcl
region      = "us-east-1"
environment = "prod"
project     = "Expense Control"
owner       = "Owner"
cost_center = "CC-OWNER-001"

vpc_cidr = "10.0.0.0/16"
azs      = ["us-east-1a", "us-east-1b"]

app_base_url = null
route53_zone_name = "chelalo.me"
app_domain_name   = "expense-control-prod.chelalo.me"

frontend_image = "123456789012.dkr.ecr.us-east-1.amazonaws.com/expense-control-prod-frontend:latest"
backend_image  = "123456789012.dkr.ecr.us-east-1.amazonaws.com/expense-control-prod-backend:latest"

frontend_desired_count = 0
backend_desired_count  = 0

db_name     = "expense_control"
db_username = "expensecontrol"

auth_session_secret_arn            = "arn:aws:secretsmanager:..."
jwt_access_private_key_secret_arn  = "arn:aws:secretsmanager:..."
jwt_access_public_key_secret_arn   = "arn:aws:secretsmanager:..."
jwt_refresh_private_key_secret_arn = "arn:aws:secretsmanager:..."
jwt_refresh_public_key_secret_arn  = "arn:aws:secretsmanager:..."

enable_observability          = true
observability_allowed_cidrs   = ["TU_IP_PUBLICA/32"]
observability_grafana_admin_user = "admin"
otel_traces_sampler_ratio     = 1

additional_allowed_origins = []
```

Si quieres dominio propio, el hosted zone de Route 53 debe existir en la misma
cuenta y `app_domain_name` debe pertenecer a esa zona. Con los valores de
arriba Terraform hace tres cosas:

- solicita un certificado ACM en la misma region del ALB,
- crea los registros DNS de validacion del certificado,
- crea el alias `A` del subdominio hacia el ALB.

Si no quieres dominio propio todavia, deja `route53_zone_name = null` y
`app_domain_name = null`. El stack seguira usando el DNS publico del ALB por
HTTP.

Para obtener tu IP publica:

```bash
curl https://checkip.amazonaws.com
```

## AWS: primer apply

El primer apply debe crear ECR antes de que existan las imagenes. Usa
`frontend_desired_count = 0` y `backend_desired_count = 0`.

```bash
cd infra/live/dev
terraform init -backend-config=backend.hcl
terraform validate
terraform plan -out=plan.out
terraform apply plan.out
```

Si configuraste `app_domain_name`, este apply tambien dejara listo el
certificado y el listener HTTPS. La validacion DNS de ACM suele tardar pocos
minutos, asi que espera a que el `apply` termine y luego verifica:

```bash
terraform output frontend_url
terraform output app_domain_name
```

Toma los outputs:

```bash
terraform output frontend_ecr_repository_url
terraform output backend_ecr_repository_url
```

## AWS: build y push de imagenes

Desde la raiz del repo, autentica Docker contra ECR:

```bash
AWS_REGION=us-east-1
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
```

Backend:

```bash
BACKEND_REPO=$(terraform -chdir=infra/live/dev output -raw backend_ecr_repository_url)

docker build -t expense-control-back:latest ./expense-control-back
docker tag expense-control-back:latest "$BACKEND_REPO:latest"
docker push "$BACKEND_REPO:latest"
```

La imagen del backend incluye las migraciones SQL y el comando
`run-migrations.sh`. La task backend de ECS ahora arranca con
`AUTO_RUN_MIGRATIONS=true`, asi que aplica migraciones automaticamente antes de
levantar el servidor.

Si necesitas forzarlas manualmente, por ejemplo despues de diagnosticar una
base nueva o una task antigua, usa:

```bash
CLUSTER=$(terraform -chdir=infra/live/dev output -raw ecs_cluster_name)
BACKEND_SERVICE=$(terraform -chdir=infra/live/dev output -raw backend_service_name 2>/dev/null || echo "expense-control-dev-backend")

aws ecs update-service \
  --region "$AWS_REGION" \
  --cluster "$CLUSTER" \
  --service "$BACKEND_SERVICE" \
  --force-new-deployment

aws ecs wait services-stable \
  --region "$AWS_REGION" \
  --cluster "$CLUSTER" \
  --services "$BACKEND_SERVICE"

BACKEND_TASK=$(aws ecs list-tasks \
  --region "$AWS_REGION" \
  --cluster "$CLUSTER" \
  --service-name "$BACKEND_SERVICE" \
  --desired-status RUNNING \
  --query 'taskArns[0]' \
  --output text)

aws ecs execute-command \
  --region "$AWS_REGION" \
  --cluster "$CLUSTER" \
  --task "$BACKEND_TASK" \
  --container backend \
  --interactive \
  --command "run-migrations.sh"
```

Frontend:

```bash
FRONTEND_REPO=$(terraform -chdir=infra/live/dev output -raw frontend_ecr_repository_url)
FRONTEND_API_URL=$(terraform -chdir=infra/live/dev output -raw api_url)

docker build \
  --build-arg API_URL="$FRONTEND_API_URL" \
  --build-arg NEXT_PUBLIC_API_URL="$FRONTEND_API_URL" \
  -t expense-control-ui:latest \
  ./expense-control-ui
docker tag expense-control-ui:latest "$FRONTEND_REPO:latest"
docker push "$FRONTEND_REPO:latest"
```

## AWS: levantar servicios

Sube los desired counts:

```hcl
frontend_desired_count = 1
backend_desired_count  = 1
```

Aplica de nuevo:

```bash
terraform plan -out=plan.out
terraform apply plan.out
```

Outputs utiles:

```bash
terraform output frontend_url
terraform output api_url
terraform output observability_grafana_url
terraform output -raw observability_grafana_admin_password
```

## Observabilidad en AWS

Cuando `enable_observability = true`:

- Grafana queda publico detras de un ALB restringido por
  `observability_allowed_cidrs`.
- Prometheus, Loki, Tempo y OTel Collector quedan sin ALB publico.
- El backend manda trazas a `otel-collector` por Cloud Map.
- Frontend y backend mandan logs a Loki via FireLens.
- Prometheus scrapea `/api/metrics` del backend por DNS interno.
- El ALB publico de la app bloquea `/api/metrics`.

En Grafana:

- Logs: datasource `Loki`.
- Trazas: datasource `Tempo`.
- Metricas: datasource `Prometheus`.
- Para backend, los logs incluyen `trace_id` y se pueden enlazar con Tempo.

Limitaciones actuales:

- El backend solo instrumenta requests HTTP entrantes. No hay spans manuales
  por caso de uso ni spans de base de datos.
- El frontend emite logs estructurados en produccion, pero no genera trazas
  OpenTelemetry propias.
- El stack corre con una tarea por servicio. Para alta disponibilidad real,
  hay que ajustar replicas, storage y politicas de retencion.

## Variables importantes

- `environment`: `dev`, `staging` o `prod`; afecta nombres, tags y runtime.
- `app_base_url`: URL publica final. Si queda `null`, se usa el DNS del ALB.
- `route53_zone_name`: zona publica de Route 53 donde existe tu dominio.
- `app_domain_name`: subdominio completo que apuntara al ALB. Si se define,
  Terraform habilita HTTPS y redirige HTTP a HTTPS.
- `frontend_image` y `backend_image`: imagenes completas en ECR.
- `frontend_desired_count` y `backend_desired_count`: usa `0` antes de subir
  imagenes y `1` o mas despues.
- `enable_observability`: crea o no crea Grafana, Prometheus, Loki, Tempo y
  Collector.
- `observability_allowed_cidrs`: IPs autorizadas para entrar a Grafana.
- `otel_traces_sampler_ratio`: `1` conserva todas las trazas; `0.1` conserva
  alrededor del 10%.
- `additional_allowed_origins`: origenes extra permitidos por CORS.

## Consideraciones para produccion

- Usa `route53_zone_name` y `app_domain_name` para evitar dejar el login sobre
  HTTP. Si expones la aplicacion por dominio propio, el frontend ya detecta
  HTTPS y activa cookies seguras de sesion.
- Para prod, cambia RDS a una postura menos destructiva: `deletion_protection`
  y snapshots finales. El stack actual esta optimizado para iterar.
- Revisa costos antes de dejar observabilidad encendida: ECS, EFS, ALB, RDS y
  CloudWatch generan costo continuo.
- Si tu IP cambia, actualiza `observability_allowed_cidrs` y aplica Terraform.
- Mantén versionados `.terraform.lock.hcl` y no subas `terraform.tfvars`,
  `plan.out`, `.terraform/` ni `tfstate`.

## Validacion rapida

```bash
terraform -chdir=infra/bootstrap validate
terraform -chdir=infra/live/dev validate
terraform -chdir=infra fmt -check -recursive
docker compose -f expense-control-back/.docker/compose.yml config
docker compose --env-file observability/local/.env.example -f observability/local/compose.yml config
GOCACHE=/tmp/go-build go test ./...
```
