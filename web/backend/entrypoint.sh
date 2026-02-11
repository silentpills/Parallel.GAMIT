#!/bin/bash

echo "Attempting database migrations..."
if python /code/backend_django_project/manage.py migrate --noinput; then
    echo "Migrations complete."
else
    echo "WARNING: Migrations failed (database may not be available yet)."
    echo "The application will start, but you may need to run migrations manually:"
    echo "  docker exec -it gnss-backend python /code/backend_django_project/manage.py migrate"
fi

echo "Starting application..."
exec "$@"
