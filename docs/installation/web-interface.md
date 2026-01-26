# Web Interface Setup

The Parallel.GAMIT web interface provides a visual way to manage station metadata, view RINEX data, and monitor processing. It consists of a Django backend and React frontend, deployed via Docker Compose.

## Prerequisites

- Docker and Docker Compose installed
- PostgreSQL database configured (see [Database Setup](database-setup.md))
- Network access between Docker containers and database

## Configuration Files

### 1. Root `.env` File

Copy the example file and edit it:

```bash
cp .env.example .env
```

Key settings to configure:

```bash
# PostgreSQL Connection
# Use host.docker.internal for local setup (Docker reaching host PostgreSQL)
# Use hostname/IP for remote database
POSTGRES_HOST=host.docker.internal
POSTGRES_PORT=5432
POSTGRES_DB=pgamit
POSTGRES_USER=pgamit
POSTGRES_PASSWORD=your_secure_password

# Django Settings - generate a secure secret key:
#   python3 -c "import secrets; print(secrets.token_urlsafe(50))"
DJANGO_SECRET_KEY=<paste-generated-key-here>
DJANGO_DEBUG=False

# Docker/Web UI Settings
APP_PORT=8080
VITE_API_URL=http://localhost:8080

# Directory on host for uploaded station images and files
# This folder will be mounted into the container
MEDIA_FOLDER_HOST_PATH=/home/username/pgamit-media

# File ownership (run 'id' to find your UID/GID)
USER_ID_TO_SAVE_FILES=1000
GROUP_ID_TO_SAVE_FILES=1000
```

Create the media directory:

```bash
mkdir -p ~/pgamit-media
```

### 2. Backend Configuration (Optional)

The `gnss_data.cfg` file in `configuration_files/` is used by the PGAMIT CLI for processing jobs. For the web interface, all database settings come from the `.env` file, so `gnss_data.cfg` is not required for Docker deployment.

If you plan to use the CLI alongside the web interface, copy and configure it:

```bash
cp configuration_files/gnss_data.cfg ~/gnss_data.cfg
```

### 3. Frontend Environment

The frontend uses `VITE_API_URL` from the root `.env` file. This should match the URL users will access the app at.

## Deployment

Build and start the containers:

```bash
docker compose up --build -d
```

This starts two containers:
- `gnss-backend`: Django REST API
- `gnss-frontend`: React/Vite frontend

## Creating the Admin User

The Django migrations create a default admin user:

- **Username**: `admin`
- **Password**: `admin`

!!! warning
    Change the default password immediately after first login!

### Creating a Custom Superuser

```bash
# If using Docker:
docker exec -it gnss-backend python manage.py createsuperuser
```

You will be prompted for:
- Username
- Email (optional)
- Password

### Changing the Default Admin Password

```bash
docker exec -it gnss-backend python manage.py changepassword admin
```

## Django Migrations

Django migrations run automatically when the backend container starts. You should see output like:

```
Attempting database migrations...
Operations to perform:
  Apply all migrations: api, auth, contenttypes, sessions
Running migrations:
  ...
Migrations complete.
```

If the database is unavailable at startup, the container will log a warning and continue running. You can manually run migrations later:

```bash
docker exec -it gnss-backend python manage.py migrate
```

## API Documentation

API documentation is available in OpenAPI format at `web/backend/docs/schema.yml`.

To view the interactive API client:

```bash
docker run -p 8081:8080 -e SWAGGER_JSON=/schema.yml \
  -v ${PWD}/web/backend/docs/schema.yml:/schema.yml \
  swaggerapi/swagger-ui
```

Then open `http://localhost:8081` in your browser.

## Testing

Before running tests, create a test database:

1. Create database named `test_{PRODUCTION_DB_NAME}`
2. Run the schema modification script: `db/modify_test_db.py`
3. Set test credentials in `db/.env`

Run tests:

```bash
cd web/backend/backend_django_project/
python manage.py test --keepdb
```

## Environment Variables Reference

| Variable | Description | Required |
|----------|-------------|----------|
| `APP_PORT` | Port where app is served (default: 8080) | Yes |
| `MEDIA_FOLDER_HOST_PATH` | Host directory for uploaded station images and files | Yes |
| `USER_ID_TO_SAVE_FILES` | UID for file ownership (run `id -u` to find) | Yes |
| `GROUP_ID_TO_SAVE_FILES` | GID for file ownership (run `id -g` to find) | Yes |
| `VITE_API_URL` | URL users access the app at | Yes |
| `POSTGRES_HOST` | Database hostname (`host.docker.internal` for local) | Yes |
| `POSTGRES_PORT` | Database port (default: 5432) | No |
| `POSTGRES_DB` | Database name | Yes |
| `POSTGRES_USER` | Database username | Yes |
| `POSTGRES_PASSWORD` | Database password | Yes |
| `DJANGO_SECRET_KEY` | Cryptographic key for Django (generate with `python3 -c "import secrets; print(secrets.token_urlsafe(50))"`) | Yes |
| `DJANGO_DEBUG` | Enable debug mode (default: False) | No |
