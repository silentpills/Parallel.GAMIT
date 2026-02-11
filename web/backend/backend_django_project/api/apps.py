from django.apps import AppConfig


class ApiConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'api'

    def ready(self):

        from django.conf import settings
        from django.core.exceptions import ImproperlyConfigured

        if int(getattr(settings, 'MAX_SIZE_IMAGE_MB', None)) > 75:
            raise ImproperlyConfigured(
                "MAX_SIZE_IMAGE_MB must be equal or less than 75 MB")

        if int(getattr(settings, 'MAX_SIZE_FILE_MB', None)) > 75:
            raise ImproperlyConfigured(
                "MAX_SIZE_FILE_MB must be equal or less than 75 MB")
