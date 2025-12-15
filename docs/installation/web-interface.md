# Web Interface Setup

The Parallel.GAMIT web interface provides a visual way to manage station metadata, view RINEX data, and monitor processing. It consists of a Django backend and React frontend, deployed via Docker Compose.

## Prerequisites

- Docker and Docker Compose installed
- PostgreSQL database configured (see [Database Setup](database-setup.md))
- Network access between Docker containers and database

## Configuration Files

### 1. Root `.env` File

Create a `.env` file in the project root:

```bash
# Docker/Web UI Settings
APP_PORT=8080
MEDIA_FOLDER_HOST_PATH=/path/to/media
USER_ID_TO_SAVE_FILES=1000
GROUP_ID_TO_SAVE_FILES=1000
VITE_API_URL=http://localhost:8080

# PostgreSQL Connection
POSTGRES_HOST=your-db-host
POSTGRES_PORT=5432
POSTGRES_DB=pgamit
POSTGRES_USER=pgamit
POSTGRES_PASSWORD=your_secure_password

# Django Settings
DJANGO_SECRET_KEY=generate-a-secure-key-here
DJANGO_DEBUG=False
```

### 2. Backend Configuration

Create `gnss_data.cfg` in `web/backend/backend/` following the example in `configuration_files/gnss_data.cfg`.

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

## Running Django Migrations

After the database schema is loaded, run migrations to add web UI tables:

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
cd web/backend/backend/backend_django_project/
python manage.py test --keepdb
```

## Environment Variables Reference

| Variable | Description | Required |
|----------|-------------|----------|
| `APP_PORT` | Port where app is served | Yes |
| `MEDIA_FOLDER_HOST_PATH` | Path for uploaded media files | Yes |
| `USER_ID_TO_SAVE_FILES` | UID for file ownership | Yes |
| `GROUP_ID_TO_SAVE_FILES` | GID for file ownership | Yes |
| `VITE_API_URL` | Frontend API URL | Yes |
| `POSTGRES_HOST` | Database hostname | Yes |
| `POSTGRES_PORT` | Database port (default: 5432) | No |
| `POSTGRES_DB` | Database name | Yes |
| `POSTGRES_USER` | Database username | Yes |
| `POSTGRES_PASSWORD` | Database password | Yes |
| `DJANGO_SECRET_KEY` | Django secret key | Yes |
| `DJANGO_DEBUG` | Enable debug mode | No |
