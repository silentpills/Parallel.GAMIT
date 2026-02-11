import logging

from celery import shared_task
from django.core.cache import cache

from . import utils

logger = logging.getLogger('django')


@shared_task
def update_gaps_status():
    """One-shot task triggered manually via the UpdateGapsStatus API endpoint."""
    utils.StationMetaUtils.update_gaps_status_for_all_station_meta_needed()


@shared_task(bind=True)
def update_gaps_status_periodic(self):
    """Periodic task that replaces the standalone polling script.

    Uses a Redis lock to prevent concurrent runs. The lock is released
    in a finally block so stale locks cannot accumulate (unlike the old
    polling script which required a separate 'delete block' endpoint).
    """
    lock_timeout = 60 * 60  # 1 hour
    acquired = cache.add('update_gaps_status_lock', 'locked', timeout=lock_timeout)
    if not acquired:
        logger.debug("update_gaps_status_periodic: lock held, skipping run.")
        return

    try:
        utils.StationMetaUtils.update_gaps_status_for_all_station_meta_needed()
    finally:
        cache.delete('update_gaps_status_lock')
