# docker-cicd-pipeline-template

A production-ready CI/CD pipeline template for Docker-based applications.
Designed for teams running Jenkins, Ansible, and HashiCorp Vault on either
on-premises infrastructure or cloud VMs. No Kubernetes required.

---

## Stack

| Layer              | Tool                           |
|--------------------|--------------------------------|
| Source control     | Bitbucket / GitHub             |
| CI server          | Jenkins                        |
| Artifact registry  | Nexus (or any Docker registry) |
| Deploy agent       | Ansible                        |
| Secrets management | HashiCorp Vault                |
| Runtime            | Docker Compose on Linux VMs    |
| Database           | PostgreSQL (swappable)         |

---

## Repo Structure

```
├── Jenkinsfile                            # Pipeline definition
└── deploy/
    ├── docker-compose.yml                 # Service definitions
    ├── docker-compose.env.template        # Secrets placeholder — populated by Ansible
    ├── ansible/
    │   ├── deploy.yml                     # Deploy playbook
    │   ├── rollback.yml                   # Rollback playbook
    │   └── inventory/
    │       ├── prod                       # Production hosts
    │       └── staging                    # Staging hosts
    └── scripts/
        └── smoke-test.sh                  # Post-deploy health validation
```

---

## Pipeline Stages

```
Source repo → Build image → Push to registry → Deploy → Smoke test → Notify / Rollback
```

1. **Checkout** — Webhook triggers Jenkins on every push to main
2. **Build image** — Docker image built and tagged with Jenkins build number
3. **Push to registry** — Versioned image pushed to internal Docker registry
4. **Deploy** — Ansible pulls secrets from Vault, writes `.env`, restarts containers
5. **Smoke test** — Health endpoint, DB connectivity, and container status validated
6. **Notify / Rollback** — Build marked success or automatic rollback to prior image tag

---

## What This Solves

| Before                                    | After                                              |
|-------------------------------------------|----------------------------------------------------|
| Manual SSH deploys                        | Ansible-driven, pipeline-triggered                 |
| Config files edited directly on server    | All config tracked in source control               |
| Secrets in plaintext `.env` files on disk | Secrets in Vault, injected at deploy time          |
| No rollback process                       | Automatic rollback to prior build on failure       |
| No deploy audit trail                     | Timestamped log per deploy, rollback, smoke test   |
| No post-deploy validation                 | Smoke test catches bad deploys before users do     |

---

## Audit Log

All pipeline events write to `/var/log/app/deployments.log` in unified format:

```
2026-05-12T01:00:00 | portal          | tag=42 | host=docker-01 | user=deploy
2026-05-12T01:00:30 | SMOKE-TEST-PASS | host=docker-01 | app=localhost:8080 | db=localhost
2026-05-12T01:05:00 | ROLLBACK        | tag=41 | host=docker-01 | user=deploy
```

---

## Switching Database Engines

PostgreSQL is the default. To switch to another engine update these files:

| File                           | What to change                                       |
|--------------------------------|------------------------------------------------------|
| `docker-compose.yml`           | `image:`, environment variables, healthcheck command |
| `docker-compose.env.template`  | Variable names to match your DB engine               |
| `deploy/ansible/deploy.yml`    | Vault secret path, variable names, default port      |
| `deploy/ansible/rollback.yml`  | Vault secret path, variable names, default port      |
| `deploy/scripts/smoke-test.sh` | DB connectivity check command                        |

**Reference commands by engine:**

```bash
# PostgreSQL (default)
pg_isready -h ${DB_HOST} -U ${DB_USER}

# MySQL / MariaDB
mysqladmin ping -h ${DB_HOST}

# MSSQL
/opt/mssql-tools/bin/sqlcmd -S ${DB_HOST} -U ${DB_USER} -P ${DB_PASSWORD} -Q "SELECT 1"

# Oracle
sqlplus -S ${DB_USER}/${DB_PASSWORD}@${DB_HOST} <<< "SELECT 1 FROM DUAL;"
```

---

## Setup

### 1. Jenkins Prerequisites

Install plugins:
- Bitbucket Branch Source
- Ansible
- Pipeline
- HashiCorp Vault

Add credentials in Jenkins (`Manage Jenkins → Credentials`):
- `nexus-creds` — Docker registry username/password
- `vault-approle` — Vault AppRole role_id and secret_id

### 2. HashiCorp Vault

Store database credentials at:
```
secret/company/prod/app/db
```

With keys:
```
db_host
db_port
db_name
db_user
db_password
```

### 3. Update Placeholders

Replace `company.internal` with your internal domain across all files:

```bash
find . -type f | xargs grep -l "company.internal" | xargs sed -i 's/company.internal/yourdomain.internal/g'
```

### 4. Update Inventory Files

Add your Docker host(s) to:
- `deploy/ansible/inventory/prod`
- `deploy/ansible/inventory/staging`

### 5. Configure Jenkinsfile

Update environment variables at the top of `Jenkinsfile`:
```groovy
REGISTRY   = "your-registry.internal"
IMAGE_NAME = "${REGISTRY}/your-app-name"
```

---

## Secrets Handling

No credentials are ever stored in this repository.

- All secrets live in HashiCorp Vault
- Ansible pulls secrets at deploy time using AppRole authentication
- `.env` is written to the host at deploy time and never committed
- `docker-compose.env.template` contains only placeholder variable names

---

## Author

**Dan Bodily** — Senior Platform & DevSecOps Engineer  
[github.com/dan-bodily](https://github.com/dan-bodily) · [LinkedIn](https://www.linkedin.com/in/danielbodily/)
