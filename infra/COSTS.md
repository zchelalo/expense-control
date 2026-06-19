# Costos Estimados

Estimado actualizado al 2026-06-18 para la configuracion actual de [`infra/live/dev/terraform.tfvars`](/home/chelalo/projects/personal/expense-control/expense-control/infra/live/dev/terraform.tfvars).

Region asumida: `us-east-1`.

## Stack actual sin observabilidad

Supuestos:

- `frontend_desired_count = 1`
- `backend_desired_count = 1`
- `frontend_cpu = 256`, `frontend_memory = 512`
- `backend_cpu = 512`, `backend_memory = 1024`
- `db_instance_class = db.t3.micro`
- `db_allocated_storage = 20`
- Un ALB publico
- 4 IPv4 publicas facturables: 2 del ALB y 1 por cada tarea ECS
- 6 secretos en Secrets Manager: 5 de app + 1 master secret de RDS

| Componente | Estimado mensual (USD) |
| --- | ---: |
| ECS Fargate frontend | 9.01 |
| ECS Fargate backend | 18.02 |
| RDS PostgreSQL `db.t3.micro` | 13.14 |
| RDS gp3 `20 GB` | 2.30 |
| ALB principal | 16.43 |
| IPv4 publicas | 14.60 |
| Secrets Manager | 2.40 |
| **Total base** | **75.90** |

Total practico esperado con algo de trafico y logs: `80-90 USD/mes`.

## Sobrecosto de observabilidad

Supuestos adicionales:

- `enable_observability = true`
- 5 servicios extra: Grafana, Prometheus, Loki, Tempo y OTEL Collector
- Un ALB publico adicional para Grafana
- 7 IPv4 publicas extra: 2 del ALB de observabilidad y 1 por cada tarea
- 1 secreto adicional para Grafana
- Cloud Map privado
- EFS para persistencia de Grafana, Prometheus, Loki y Tempo

| Componente | Estimado mensual (USD) |
| --- | ---: |
| Fargate Grafana | 9.01 |
| Fargate Prometheus | 18.02 |
| Fargate Loki | 18.02 |
| Fargate Tempo | 18.02 |
| Fargate OTEL Collector | 9.01 |
| ALB observabilidad | 16.43 |
| IPv4 publicas extra | 25.55 |
| Secrets Manager extra | 0.40 |
| Cloud Map | 1.00 |
| EFS | 0.30 por GB |
| **Subtotal observabilidad sin EFS** | **115.46** |

Totales orientativos:

- Stack completo con observabilidad y `10 GB` en EFS: `194.36 USD/mes`
- Stack completo con observabilidad y `50 GB` en EFS: `206.36 USD/mes`

## Formulas rapidas

Fargate Linux/x86:

- `costo_cpu_mes = vcpu * 3600 * 730 * 0.000011244`
- `costo_mem_mes = gb_ram * 3600 * 730 * 0.000001235`

ALB:

- `costo_base_alb_mes = 0.0225 * 730`
- No incluye LCUs variables por trafico

IPv4 publica:

- `costo_ipv4_mes = cantidad_ipv4 * 0.005 * 730`

RDS PostgreSQL:

- `costo_rds_mes = 0.018 * 730 + (gb_storage * 0.115)`

EFS Standard:

- `costo_efs_mes = gb_usados * 0.30`

## Que no esta incluido

- Transferencia de salida a Internet
- LCUs variables del ALB
- Ingestion y almacenamiento variable de CloudWatch Logs
- ECR por crecimiento de imagenes
- Snapshots extra, respaldos manuales o almacenamiento S3 auxiliar

## Notas

- `db_max_allocated_storage = 100` no se cobra completo desde el inicio; solo se paga lo realmente usado.
- Como ya existe la hosted zone `chelalo.me`, el subdominio no agrega un costo relevante por si mismo.
- El certificado publico de ACM para el dominio de la app no tiene costo.
- En la configuracion actual no hay una politica de retencion fuerte en Loki o Tempo; si crecen logs o trazas, EFS crecera y con ello el costo.

## Fuentes oficiales

- AWS Fargate Pricing: <https://aws.amazon.com/fargate/pricing/>
- Amazon RDS for PostgreSQL Pricing: <https://aws.amazon.com/rds/postgresql/pricing/>
- Elastic Load Balancing Pricing: <https://aws.amazon.com/elasticloadbalancing/pricing/>
- Amazon EFS Pricing: <https://aws.amazon.com/efs/pricing/>
- Amazon VPC Pricing: <https://aws.amazon.com/vpc/pricing/>
- AWS Secrets Manager Pricing: <https://aws.amazon.com/secrets-manager/pricing/>
- Amazon Route 53 Pricing: <https://aws.amazon.com/route53/pricing/>
- AWS Cloud Map Pricing: <https://aws.amazon.com/cloud-map/pricing/>

## Recalculo rapido si cambia tamaños

1. Ajusta CPU, memoria, `desired_count` o tamaños de base de datos en `terraform.tfvars`.
2. Recalcula Fargate por tarea usando las formulas anteriores.
3. Recalcula RDS con la clase real y el almacenamiento configurado.
4. Suma IPv4 publicas reales, ALBs, secretos y EFS según servicios activos.
