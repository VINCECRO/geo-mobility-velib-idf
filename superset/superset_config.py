# superset/superset_config.py
# Custom Superset configuration with PostGIS

import os

# Flask App Builder configuration
ROW_LIMIT = 5000
SUPERSET_WEBSERVER_PORT = 8088

# Flask Secret Key - CHANGE THIS VALUE IN PRODUCTION
SECRET_KEY = os.environ.get("SUPERSET_SECRET_KEY", "change-this-to-a-long-random-string")

# SQLAlchemy Database URI for Superset metadata
SQLALCHEMY_DATABASE_URI = (
    f"postgresql://{os.environ.get('DATABASE_USER', 'superset')}:"
    f"{os.environ.get('DATABASE_PASSWORD', 'superset')}@"
    f"{os.environ.get('DATABASE_HOST', 'postgres-superset')}:"
    f"{os.environ.get('DATABASE_PORT', '5432')}/"
    f"{os.environ.get('DATABASE_DB', 'superset')}"
)

# Redis configuration for caching
REDIS_HOST = os.environ.get("REDIS_HOST", "redis-superset")
REDIS_PORT = os.environ.get("REDIS_PORT", "6379")

CACHE_CONFIG = {
    'CACHE_TYPE': 'RedisCache',
    'CACHE_DEFAULT_TIMEOUT': 300,
    'CACHE_KEY_PREFIX': 'superset_',
    'CACHE_REDIS_HOST': REDIS_HOST,
    'CACHE_REDIS_PORT': REDIS_PORT,
}

DATA_CACHE_CONFIG = {
    'CACHE_TYPE': 'RedisCache',
    'CACHE_DEFAULT_TIMEOUT': 300,
    'CACHE_KEY_PREFIX': 'superset_data_',
    'CACHE_REDIS_HOST': REDIS_HOST,
    'CACHE_REDIS_PORT': REDIS_PORT,
}

# Mapbox API Key (optional - for nice maps
MAPBOX_API_KEY = os.environ.get("MAPBOX_API_KEY", "")

# Feature flags to enable geospatial features
FEATURE_FLAGS = {
    "ENABLE_TEMPLATE_PROCESSING": True,
    "DASHBOARD_NATIVE_FILTERS": True,
    "DASHBOARD_CROSS_FILTERS": True,
    "DASHBOARD_VIRTUALIZATION": True,
    "GLOBAL_ASYNC_QUERIES": False,  # Temporarily disabled
    "VERSIONED_EXPORT": True,
    "ENABLE_EXPLORE_DRAG_AND_DROP": True,
}

# Configuration to allow iframes (if you want to embed Superset)
TALISMAN_ENABLED = False
WTF_CSRF_ENABLED = False

# SQL query timeout
SUPERSET_WEBSERVER_TIMEOUT = 300

# Logging
ENABLE_PROXY_FIX = True

# Allow larger file uploads for custom datasets
DATA_UPLOAD_MAX_MEMORY_SIZE = 524288000  # 500MB

# Jinja template context
JINJA_CONTEXT_ADDONS = {
    'my_custom_function': lambda x: x * 2,
}

# SQL Lab configuration
SQLLAB_ASYNC_TIME_LIMIT_SEC = 300
SQLLAB_TIMEOUT = 300
SUPERSET_WEBSERVER_TIMEOUT = 300

# Enable scheduled queries
SCHEDULED_QUERIES = {
    "ENABLE_SCHEDULED_QUERIES": True,
}

# Languages
LANGUAGES = {
    'en': {'flag': 'us', 'name': 'English'},
    'fr': {'flag': 'fr', 'name': 'French'},
}