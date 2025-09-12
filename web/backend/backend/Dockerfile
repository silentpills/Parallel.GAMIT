# syntax=docker/dockerfile:1
FROM python:3.11
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ARG USER_ID_TO_SAVE_FILES
ARG GROUP_ID_TO_SAVE_FILES

# Install system dependencies
RUN apt-get update && apt-get install -y \
    supervisor \
    redis-server \
    libpq-dev \
    python3-dev \
    build-essential \
    libffi-dev \
    libssl-dev \
    gdal-bin \
    libgdal-dev

# Create user
RUN groupadd -g ${GROUP_ID_TO_SAVE_FILES} dummy-user && \
    useradd -u ${USER_ID_TO_SAVE_FILES} -g dummy-user -m dummy-user

# Install uv using the recommended installer and add it to the PATH
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"

# Install/upgrade pip
# RUN pip install --upgrade pip

WORKDIR /code
COPY . /code/
RUN mkdir -p /var/log/gunicorn && chmod 755 /var/log/gunicorn

# Now install requirements using uv
RUN uv pip install --system --no-cache-dir -r requirements.txt && \
    cd backend_django_project && python manage.py migrate

COPY ./supervisord.conf /etc/supervisor/conf.d/supervisord.conf

CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]