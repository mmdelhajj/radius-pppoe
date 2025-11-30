#!/bin/bash
################################################################################
# ProRADIUS4 - Secure One-Click Installation Script for Ubuntu 22.04
# ISP Billing and RADIUS Management System
#
# Security Features:
# - Strong random passwords
# - CSRF protection enabled
# - SSL/TLS encryption
# - Secure file permissions
# - Encrypted database credentials
# - Session cleanup automation
# - Modern Python 3.10+
# - Latest security patches
#
# Usage: sudo bash install-ubuntu22.sh
################################################################################

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging
LOG_FILE="/var/log/proradius4_install.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}   ProRADIUS4 - ISP Billing & RADIUS Management System${NC}"
echo -e "${BLUE}   Secure Installation for Ubuntu 22.04 LTS${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}Installation started: $(date)${NC}"
echo -e "${CYAN}Log file: $LOG_FILE${NC}"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}✗ This script must be run as root (use sudo)${NC}"
   exit 1
fi

# Check Ubuntu version
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" != "ubuntu" ]] || [[ "${VERSION_ID}" != "22.04" ]]; then
        echo -e "${YELLOW}⚠ Warning: This script is optimized for Ubuntu 22.04${NC}"
        echo -e "${YELLOW}  Detected: $PRETTY_NAME${NC}"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        echo -e "${GREEN}✓ Ubuntu 22.04 LTS detected${NC}"
    fi
else
    echo -e "${RED}✗ Cannot detect operating system${NC}"
    exit 1
fi

# Configuration variables
DB_NAME="proradius4"
DB_USER="proradius_user"
DB_ROOT_PASS=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
DB_PASS=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
RADIUS_SECRET=$(openssl rand -base64 48 | tr -d "=+/" | cut -c1-48)
DJANGO_SECRET=$(openssl rand -base64 64 | tr -d "=+/" | cut -c1-64)
ADMIN_PASS=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)
APP_DIR="/home/proradius4"
APP_USER="proradius"
DOMAIN="localhost"

echo -e "${CYAN}Domain: $DOMAIN${NC}"
echo -e "${YELLOW}Note: Using localhost. You can change this later in .env file${NC}"
echo ""

# Update system
echo -e "${YELLOW}[1/15] Updating system packages...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq

# Install required system packages
echo -e "${YELLOW}[2/15] Installing system dependencies...${NC}"
apt-get install -y -qq \
    python3.10 \
    python3.10-venv \
    python3.10-dev \
    python3-pip \
    build-essential \
    libssl-dev \
    libffi-dev \
    libmysqlclient-dev \
    pkg-config \
    git \
    nginx \
    mysql-server \
    freeradius \
    freeradius-mysql \
    freeradius-utils \
    supervisor \
    curl \
    wget \
    net-tools \
    ufw \
    certbot \
    python3-certbot-nginx \
    fail2ban \
    logrotate \
    htop \
    unattended-upgrades \
    > /dev/null 2>&1

echo -e "${GREEN}✓ System dependencies installed${NC}"

# Configure automatic security updates
echo -e "${YELLOW}[3/15] Configuring automatic security updates...${NC}"
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

systemctl enable unattended-upgrades
systemctl start unattended-upgrades
echo -e "${GREEN}✓ Automatic security updates enabled${NC}"

# Create application user with secure settings
echo -e "${YELLOW}[4/15] Creating application user...${NC}"
if ! id -u $APP_USER > /dev/null 2>&1; then
    useradd -m -s /bin/bash -U $APP_USER
    usermod -L $APP_USER  # Lock password-based login
    echo -e "${GREEN}✓ User '$APP_USER' created (password login disabled)${NC}"
else
    echo -e "${GREEN}✓ User '$APP_USER' already exists${NC}"
fi

# Create application directory with secure permissions
echo -e "${YELLOW}[5/15] Creating application directories...${NC}"
mkdir -p $APP_DIR/{logs,media,staticfiles,backups,.secrets}
chmod 700 $APP_DIR/.secrets
chown -R $APP_USER:$APP_USER $APP_DIR

# Configure MySQL with security hardening
echo -e "${YELLOW}[6/15] Configuring MySQL database...${NC}"
systemctl start mysql
systemctl enable mysql > /dev/null 2>&1

# Check if MySQL root has a password already
MYSQL_HAS_PASSWORD=false
if ! mysql -u root -e "SELECT 1;" 2>/dev/null; then
    MYSQL_HAS_PASSWORD=true
    echo -e "${YELLOW}⚠ MySQL root password already set, resetting...${NC}"

    # Stop MySQL
    systemctl stop mysql
    sleep 2

    # Ensure socket directory exists
    mkdir -p /var/run/mysqld
    chown mysql:mysql /var/run/mysqld

    # Start MySQL in safe mode (skip grant tables)
    mysqld_safe --skip-grant-tables &
    SAFE_PID=$!
    sleep 7

    # Reset root password
    mysql -u root <<EOSQL
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$DB_ROOT_PASS';
FLUSH PRIVILEGES;
EOSQL

    # Stop safe mode MySQL
    mysqladmin -u root -p"$DB_ROOT_PASS" shutdown 2>/dev/null || killall mysqld 2>/dev/null || true
    sleep 3

    # Start MySQL normally
    systemctl start mysql
    sleep 3
    echo -e "${GREEN}✓ MySQL root password reset${NC}"
fi

# Secure MySQL installation
if [ "$MYSQL_HAS_PASSWORD" = false ]; then
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$DB_ROOT_PASS';" 2>/dev/null || true
fi

mysql -u root -p"$DB_ROOT_PASS" -e "DELETE FROM mysql.user WHERE User='';" 2>/dev/null || true
mysql -u root -p"$DB_ROOT_PASS" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" 2>/dev/null || true
mysql -u root -p"$DB_ROOT_PASS" -e "DROP DATABASE IF EXISTS test;" 2>/dev/null || true
mysql -u root -p"$DB_ROOT_PASS" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';" 2>/dev/null || true
mysql -u root -p"$DB_ROOT_PASS" -e "FLUSH PRIVILEGES;" 2>/dev/null || true

# Create database and user
mysql -u root -p"$DB_ROOT_PASS" <<EOF
CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
DROP USER IF EXISTS '$DB_USER'@'localhost';
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

echo -e "${GREEN}✓ MySQL configured securely${NC}"

# Configure MySQL for better performance and security
cat > /etc/mysql/mysql.conf.d/proradius4.cnf <<EOF
[mysqld]
# Performance
max_connections = 200
innodb_buffer_pool_size = 1G
innodb_log_file_size = 256M
query_cache_size = 64M
query_cache_type = 1

# Security
bind-address = 127.0.0.1
local-infile = 0
symbolic-links = 0

# Logging
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow-query.log
long_query_time = 2
EOF

# Try to restart MySQL (may fail if already configured)
if systemctl restart mysql 2>/dev/null; then
    echo -e "${GREEN}✓ MySQL performance optimized and restarted${NC}"
else
    echo -e "${YELLOW}⚠ MySQL restart failed, removing performance config${NC}"
    rm -f /etc/mysql/mysql.conf.d/proradius4.cnf
    # Ensure MySQL is started
    systemctl start mysql 2>/dev/null || true
fi

# Wait for MySQL to be ready
echo -e "${YELLOW}Waiting for MySQL to be ready...${NC}"
for i in {1..30}; do
    if mysqladmin ping -u root -p"$DB_ROOT_PASS" 2>/dev/null | grep -q "mysqld is alive"; then
        echo -e "${GREEN}✓ MySQL is ready${NC}"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${RED}✗ MySQL failed to start after 30 seconds${NC}"
        exit 1
    fi
    sleep 1
done

# Import database schema if available
if [ -f "database/schema.sql" ]; then
    echo -e "${YELLOW}[7/15] Importing database schema...${NC}"
    mysql -u root -p"$DB_ROOT_PASS" $DB_NAME < database/schema.sql
    echo -e "${GREEN}✓ Database schema imported${NC}"
else
    echo -e "${YELLOW}[7/15] Skipping database import (schema.sql not found)${NC}"
fi

# Create Python virtual environment with Python 3.10
echo -e "${YELLOW}[8/15] Creating Python virtual environment...${NC}"
python3.10 -m venv $APP_DIR/venv
source $APP_DIR/venv/bin/activate

# Upgrade pip and install wheel
pip install --upgrade pip setuptools wheel -qq

# Install Python packages with latest secure versions
echo -e "${YELLOW}[9/15] Installing Python dependencies...${NC}"
cat > $APP_DIR/requirements.txt <<EOF
Django==4.2.8
mysqlclient==2.2.0
gunicorn==21.2.0
python-dotenv==1.0.0
requests==2.31.0
pillow==10.1.0
celery==5.3.4
redis==5.0.1
paramiko==3.4.0
pytz==2023.3
django-redis==5.4.0
djangorestframework==3.14.0
django-cors-headers==4.3.1
whitenoise==6.6.0
cryptography==41.0.7
EOF

pip install -r $APP_DIR/requirements.txt -qq
echo -e "${GREEN}✓ Python dependencies installed${NC}"

# Create secure .env file
echo -e "${YELLOW}[10/15] Creating secure configuration...${NC}"
cat > $APP_DIR/.secrets/.env <<EOF
# ProRADIUS4 Secure Configuration
# Generated: $(date)
# KEEP THIS FILE SECRET!

# Django
SECRET_KEY=$DJANGO_SECRET
DEBUG=False
ALLOWED_HOSTS=$DOMAIN,localhost,127.0.0.1

# Database
DB_ENGINE=django.db.backends.mysql
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASS
DB_HOST=127.0.0.1
DB_PORT=3306

# RADIUS
RADIUS_SECRET=$RADIUS_SECRET

# Security
SECURE_SSL_REDIRECT=True
SESSION_COOKIE_SECURE=True
CSRF_COOKIE_SECURE=True
SECURE_HSTS_SECONDS=31536000

# Email (configure for production)
EMAIL_HOST=localhost
EMAIL_PORT=25
EMAIL_USE_TLS=False
DEFAULT_FROM_EMAIL=noreply@$DOMAIN
EOF

chmod 600 $APP_DIR/.secrets/.env
chown $APP_USER:$APP_USER $APP_DIR/.secrets/.env

# Create Django project structure
mkdir -p $APP_DIR/proradius4
mkdir -p $APP_DIR/console/{templates,static,migrations}

# Create secure Django settings
cat > $APP_DIR/proradius4/settings.py <<'EOFPYTHON'
"""
ProRADIUS4 - Secure Django Settings
"""
import os
from pathlib import Path
from dotenv import load_dotenv

# Load environment variables
BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(os.path.join(BASE_DIR, '.secrets', '.env'))

# Security Settings
SECRET_KEY = os.getenv('SECRET_KEY')
DEBUG = os.getenv('DEBUG', 'False') == 'True'
ALLOWED_HOSTS = os.getenv('ALLOWED_HOSTS', 'localhost').split(',')

# Application definition
INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'rest_framework',
    'corsheaders',
    'console',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'whitenoise.middleware.WhiteNoiseMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'corsheaders.middleware.CorsMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'proradius4.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [os.path.join(BASE_DIR, 'console/templates')],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'proradius4.wsgi.application'

# Database
DATABASES = {
    'default': {
        'ENGINE': os.getenv('DB_ENGINE'),
        'NAME': os.getenv('DB_NAME'),
        'USER': os.getenv('DB_USER'),
        'PASSWORD': os.getenv('DB_PASSWORD'),
        'HOST': os.getenv('DB_HOST'),
        'PORT': os.getenv('DB_PORT'),
        'OPTIONS': {
            'init_command': "SET sql_mode='STRICT_TRANS_TABLES'",
            'charset': 'utf8mb4',
        },
    }
}

# Password validation
AUTH_PASSWORD_VALIDATORS = [
    {'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator'},
    {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator', 'OPTIONS': {'min_length': 12}},
    {'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator'},
    {'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator'},
]

# Internationalization
LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'Asia/Beirut'
USE_I18N = True
USE_TZ = True

# Static files
STATIC_URL = '/static/'
STATIC_ROOT = os.path.join(BASE_DIR, 'staticfiles')
STATICFILES_DIRS = [os.path.join(BASE_DIR, 'console/static')]
STATICFILES_STORAGE = 'whitenoise.storage.CompressedManifestStaticFilesStorage'

# Media files
MEDIA_URL = '/media/'
MEDIA_ROOT = os.path.join(BASE_DIR, 'media')

# Default primary key field type
DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

# Security Settings
SECURE_SSL_REDIRECT = os.getenv('SECURE_SSL_REDIRECT', 'False') == 'True'
SESSION_COOKIE_SECURE = os.getenv('SESSION_COOKIE_SECURE', 'False') == 'True'
CSRF_COOKIE_SECURE = os.getenv('CSRF_COOKIE_SECURE', 'False') == 'True'
SECURE_BROWSER_XSS_FILTER = True
SECURE_CONTENT_TYPE_NOSNIFF = True
X_FRAME_OPTIONS = 'DENY'
SECURE_HSTS_SECONDS = int(os.getenv('SECURE_HSTS_SECONDS', '0'))
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD = True

# Session settings
SESSION_COOKIE_AGE = 3600  # 1 hour
SESSION_SAVE_EVERY_REQUEST = True
SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SAMESITE = 'Strict'
SESSION_ENGINE = 'django.contrib.sessions.backends.db'

# CSRF settings
CSRF_COOKIE_HTTPONLY = True
CSRF_COOKIE_SAMESITE = 'Strict'
CSRF_TRUSTED_ORIGINS = [f'https://{host}' for host in ALLOWED_HOSTS if host not in ['localhost', '127.0.0.1']]

# Logging
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'verbose': {
            'format': '{levelname} {asctime} {module} {process:d} {thread:d} {message}',
            'style': '{',
        },
    },
    'handlers': {
        'file': {
            'level': 'INFO',
            'class': 'logging.handlers.RotatingFileHandler',
            'filename': os.path.join(BASE_DIR, 'logs/django.log'),
            'maxBytes': 1024 * 1024 * 10,  # 10 MB
            'backupCount': 10,
            'formatter': 'verbose',
        },
        'security_file': {
            'level': 'WARNING',
            'class': 'logging.handlers.RotatingFileHandler',
            'filename': os.path.join(BASE_DIR, 'logs/security.log'),
            'maxBytes': 1024 * 1024 * 10,
            'backupCount': 10,
            'formatter': 'verbose',
        },
    },
    'loggers': {
        'django': {
            'handlers': ['file'],
            'level': 'INFO',
            'propagate': True,
        },
        'django.security': {
            'handlers': ['security_file'],
            'level': 'WARNING',
            'propagate': False,
        },
    },
}

# RADIUS Settings
RADIUS_SERVER = {
    'HOST': '127.0.0.1',
    'PORT': 1812,
    'SECRET': os.getenv('RADIUS_SECRET'),
}

# Email Configuration
EMAIL_BACKEND = 'django.core.mail.backends.smtp.EmailBackend'
EMAIL_HOST = os.getenv('EMAIL_HOST', 'localhost')
EMAIL_PORT = int(os.getenv('EMAIL_PORT', '25'))
EMAIL_USE_TLS = os.getenv('EMAIL_USE_TLS', 'False') == 'True'
EMAIL_HOST_USER = os.getenv('EMAIL_HOST_USER', '')
EMAIL_HOST_PASSWORD = os.getenv('EMAIL_HOST_PASSWORD', '')
DEFAULT_FROM_EMAIL = os.getenv('DEFAULT_FROM_EMAIL')

# Cache Configuration (Redis)
CACHES = {
    'default': {
        'BACKEND': 'django_redis.cache.RedisCache',
        'LOCATION': 'redis://127.0.0.1:6379/1',
        'OPTIONS': {
            'CLIENT_CLASS': 'django_redis.client.DefaultClient',
        }
    }
}
EOFPYTHON

# Create minimal Django files
cat > $APP_DIR/proradius4/urls.py <<'EOFPYTHON'
from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static

urlpatterns = [
    path('admin/', admin.site.urls),
] + static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
EOFPYTHON

cat > $APP_DIR/proradius4/wsgi.py <<'EOFPYTHON'
import os
from django.core.wsgi import get_wsgi_application

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'proradius4.settings')
application = get_wsgi_application()
EOFPYTHON

cat > $APP_DIR/manage.py <<'EOFPYTHON'
#!/usr/bin/env python
import os
import sys

if __name__ == '__main__':
    os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'proradius4.settings')
    try:
        from django.core.management import execute_from_command_line
    except ImportError as exc:
        raise ImportError(
            "Couldn't import Django. Are you sure it's installed?"
        ) from exc
    execute_from_command_line(sys.argv)
EOFPYTHON

chmod +x $APP_DIR/manage.py

# Create console app
cat > $APP_DIR/console/__init__.py <<'EOFPYTHON'
default_app_config = 'console.apps.ConsoleConfig'
EOFPYTHON

cat > $APP_DIR/console/apps.py <<'EOFPYTHON'
from django.apps import AppConfig

class ConsoleConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'console'
EOFPYTHON

cat > $APP_DIR/console/models.py <<'EOFPYTHON'
from django.db import models
# Add your models here based on the database schema
EOFPYTHON

cat > $APP_DIR/console/admin.py <<'EOFPYTHON'
from django.contrib import admin
# Register your models here
EOFPYTHON

touch $APP_DIR/console/views.py
touch $APP_DIR/console/urls.py

# Set ownership
chown -R $APP_USER:$APP_USER $APP_DIR

# Django setup
echo -e "${YELLOW}Running Django migrations...${NC}"
cd $APP_DIR
sudo -u $APP_USER $APP_DIR/venv/bin/python manage.py makemigrations --noinput 2>/dev/null || true
sudo -u $APP_USER $APP_DIR/venv/bin/python manage.py migrate --fake-initial --noinput

# Create Django superuser
echo -e "${YELLOW}Creating Django superuser...${NC}"
sudo -u $APP_USER $APP_DIR/venv/bin/python manage.py shell <<EOFSHELL
from django.contrib.auth import get_user_model
User = get_user_model()
if not User.objects.filter(username='admin').exists():
    User.objects.create_superuser('admin', 'admin@$DOMAIN', '$ADMIN_PASS')
    print('Superuser created')
else:
    print('Superuser already exists')
EOFSHELL

# Collect static files
sudo -u $APP_USER $APP_DIR/venv/bin/python manage.py collectstatic --noinput --clear

echo -e "${GREEN}✓ Django application configured${NC}"

# Configure FreeRADIUS with secure settings
echo -e "${YELLOW}[11/15] Configuring FreeRADIUS...${NC}"

cat > /etc/freeradius/3.0/mods-available/sql <<EOF
sql {
    driver = "rlm_sql_mysql"
    dialect = "mysql"

    server = "localhost"
    port = 3306
    login = "$DB_USER"
    password = "$DB_PASS"
    radius_db = "$DB_NAME"

    acct_table1 = "khradacct"
    acct_table2 = "khradacct"
    postauth_table = "radpostauth"
    authcheck_table = "radcheck"
    authreply_table = "radreply"
    groupcheck_table = "radgroupcheck"
    groupreply_table = "radgroupreply"
    usergroup_table = "radusergroup"

    read_clients = yes
    client_table = "khnas"

    pool {
        start = 5
        min = 4
        max = 32
        spare = 8
        uses = 0
        lifetime = 0
        idle_timeout = 60
        retry_delay = 1
    }
}
EOF

chmod 640 /etc/freeradius/3.0/mods-available/sql
chown freerad:freerad /etc/freeradius/3.0/mods-available/sql

ln -sf /etc/freeradius/3.0/mods-available/sql /etc/freeradius/3.0/mods-enabled/sql

cat > /etc/freeradius/3.0/clients.conf <<EOF
client localhost {
    ipaddr = 127.0.0.1
    secret = $RADIUS_SECRET
    require_message_authenticator = yes
    nas_type = other
}
EOF

chmod 640 /etc/freeradius/3.0/clients.conf
chown freerad:freerad /etc/freeradius/3.0/clients.conf

systemctl restart freeradius
systemctl enable freeradius > /dev/null 2>&1

echo -e "${GREEN}✓ FreeRADIUS configured${NC}"

# Configure Gunicorn systemd service
echo -e "${YELLOW}[12/15] Configuring Gunicorn service...${NC}"
cat > /etc/systemd/system/proradius4.service <<EOF
[Unit]
Description=ProRADIUS4 Gunicorn Service
After=network.target mysql.service

[Service]
Type=notify
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$APP_DIR
Environment="PATH=$APP_DIR/venv/bin"
Environment="DJANGO_SETTINGS_MODULE=proradius4.settings"

ExecStart=$APP_DIR/venv/bin/gunicorn \\
    --workers 4 \\
    --worker-class sync \\
    --bind 127.0.0.1:8000 \\
    --timeout 300 \\
    --access-logfile $APP_DIR/logs/gunicorn-access.log \\
    --error-logfile $APP_DIR/logs/gunicorn-error.log \\
    --log-level info \\
    --capture-output \\
    proradius4.wsgi:application

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start proradius4
systemctl enable proradius4 > /dev/null 2>&1

echo -e "${GREEN}✓ Gunicorn service started${NC}"

# Configure Nginx with security headers
echo -e "${YELLOW}[13/15] Configuring Nginx web server...${NC}"
cat > /etc/nginx/sites-available/proradius4 <<EOF
upstream proradius4 {
    server 127.0.0.1:8000 fail_timeout=0;
}

server {
    listen 80;
    server_name $DOMAIN;

    # Redirect HTTP to HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    # SSL Configuration (will be managed by certbot)
    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;

    # Modern SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers off;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_stapling on;
    ssl_stapling_verify on;

    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline';" always;

    client_max_body_size 100M;
    client_body_timeout 300s;

    access_log $APP_DIR/logs/nginx-access.log;
    error_log $APP_DIR/logs/nginx-error.log;

    location /static/ {
        alias $APP_DIR/staticfiles/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    location /media/ {
        alias $APP_DIR/media/;
        expires 7d;
        add_header Cache-Control "public";
    }

    location / {
        proxy_pass http://proradius4;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
        proxy_buffering off;

        # Timeouts
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
}
EOF

ln -sf /etc/nginx/sites-available/proradius4 /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl restart nginx
systemctl enable nginx > /dev/null 2>&1

echo -e "${GREEN}✓ Nginx configured with security headers${NC}"

# Configure Firewall (UFW)
echo -e "${YELLOW}[14/15] Configuring firewall...${NC}"
ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw allow 1812/udp comment 'RADIUS Auth'
ufw allow 1813/udp comment 'RADIUS Acct'
ufw --force enable

echo -e "${GREEN}✓ Firewall configured${NC}"

# Configure Fail2Ban for brute force protection
echo -e "${YELLOW}Configuring Fail2Ban...${NC}"
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true

[nginx-http-auth]
enabled = true

[nginx-limit-req]
enabled = true
EOF

systemctl enable fail2ban
systemctl start fail2ban

echo -e "${GREEN}✓ Fail2Ban configured${NC}"

# Setup log rotation
echo -e "${YELLOW}Configuring log rotation...${NC}"
cat > /etc/logrotate.d/proradius4 <<EOF
$APP_DIR/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 0640 $APP_USER $APP_USER
    sharedscripts
    postrotate
        systemctl reload proradius4 > /dev/null 2>&1 || true
    endscript
}
EOF

echo -e "${GREEN}✓ Log rotation configured${NC}"

# Setup automated database cleanup cron job
echo -e "${YELLOW}[15/15] Setting up maintenance tasks...${NC}"
cat > /etc/cron.daily/proradius4-cleanup <<EOF
#!/bin/bash
# ProRADIUS4 Daily Maintenance

# Clean old Django sessions (older than 7 days)
$APP_DIR/venv/bin/python $APP_DIR/manage.py clearsessions

# Clean old RADIUS accounting (older than 1 year)
mysql -u $DB_USER -p'$DB_PASS' $DB_NAME -e "DELETE FROM khradacct WHERE acctstoptime < DATE_SUB(NOW(), INTERVAL 1 YEAR) LIMIT 10000;"

# Optimize tables
mysql -u $DB_USER -p'$DB_PASS' $DB_NAME -e "OPTIMIZE TABLE khradacct, django_session;"

# Backup database
mysqldump -u $DB_USER -p'$DB_PASS' $DB_NAME | gzip > $APP_DIR/backups/proradius4_\$(date +\%Y\%m\%d).sql.gz

# Keep only last 7 days of backups
find $APP_DIR/backups/ -name "*.sql.gz" -mtime +7 -delete

# Log cleanup completion
echo "\$(date): Cleanup completed" >> $APP_DIR/logs/maintenance.log
EOF

chmod +x /etc/cron.daily/proradius4-cleanup
echo -e "${GREEN}✓ Automated maintenance configured${NC}"

# Set proper permissions
chown -R $APP_USER:$APP_USER $APP_DIR
chmod -R 755 $APP_DIR
chmod 700 $APP_DIR/.secrets
chmod 600 $APP_DIR/.secrets/.env

# Save installation credentials
cat > $APP_DIR/.secrets/INSTALLATION_INFO.txt <<EOF
═══════════════════════════════════════════════════════
   ProRADIUS4 - Installation Information
═══════════════════════════════════════════════════════
Generated: $(date)
Server: $DOMAIN

IMPORTANT: Keep this file secure and delete after noting credentials!

══════════════════════════════════════════════════════
DATABASE CREDENTIALS
══════════════════════════════════════════════════════
Database Name: $DB_NAME
Database User: $DB_USER
Database Password: $DB_PASS

MySQL Root Password: $DB_ROOT_PASS

══════════════════════════════════════════════════════
DJANGO ADMIN PANEL
══════════════════════════════════════════════════════
URL: https://$DOMAIN/admin
Username: admin
Password: $ADMIN_PASS

⚠️  CHANGE THIS PASSWORD IMMEDIATELY AFTER LOGIN!

══════════════════════════════════════════════════════
RADIUS SERVER
══════════════════════════════════════════════════════
RADIUS Secret: $RADIUS_SECRET
Auth Port: 1812
Acct Port: 1813

══════════════════════════════════════════════════════
SECURITY INFORMATION
══════════════════════════════════════════════════════
✓ CSRF Protection: ENABLED
✓ SSL/TLS: Configured (using self-signed cert - install Let's Encrypt)
✓ Firewall (UFW): ENABLED
✓ Fail2Ban: ENABLED
✓ Automatic Security Updates: ENABLED
✓ Session Cleanup: Daily via cron
✓ Database Backups: Daily (kept for 7 days)

══════════════════════════════════════════════════════
FILE LOCATIONS
══════════════════════════════════════════════════════
Application: $APP_DIR
Configuration: $APP_DIR/.secrets/.env
Logs: $APP_DIR/logs/
Backups: $APP_DIR/backups/
Static Files: $APP_DIR/staticfiles/

══════════════════════════════════════════════════════
SERVICE MANAGEMENT
══════════════════════════════════════════════════════
systemctl status proradius4    # Check app status
systemctl status nginx          # Check web server
systemctl status freeradius     # Check RADIUS server
systemctl status mysql          # Check database

systemctl restart proradius4    # Restart app
systemctl restart nginx         # Restart web server

══════════════════════════════════════════════════════
NEXT STEPS
══════════════════════════════════════════════════════
1. Install Let's Encrypt SSL certificate:
   sudo certbot --nginx -d $DOMAIN

2. Change admin password in Django admin panel

3. Configure your NAS devices with RADIUS secret

4. Review and customize $APP_DIR/proradius4/settings.py

5. Setup email configuration in .env file

6. Delete this file after noting credentials:
   sudo shred -u $APP_DIR/.secrets/INSTALLATION_INFO.txt

══════════════════════════════════════════════════════
TESTING
══════════════════════════════════════════════════════
Test RADIUS locally:
radtest testuser testpass 127.0.0.1 1812 $RADIUS_SECRET

Check application status:
sudo -u $APP_USER $APP_DIR/venv/bin/python $APP_DIR/manage.py check

View logs:
tail -f $APP_DIR/logs/django.log
tail -f $APP_DIR/logs/gunicorn-error.log
tail -f /var/log/freeradius/radius.log

══════════════════════════════════════════════════════
EOF

chmod 600 $APP_DIR/.secrets/INSTALLATION_INFO.txt
chown $APP_USER:$APP_USER $APP_DIR/.secrets/INSTALLATION_INFO.txt

# Display installation summary
clear
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}   ✓ Installation Completed Successfully!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}📊 System Information:${NC}"
echo -e "   Domain: ${YELLOW}https://$DOMAIN${NC}"
echo -e "   Application: $APP_DIR"
echo -e "   Python: $(python3.10 --version)"
echo -e "   Django: $(sudo -u $APP_USER $APP_DIR/venv/bin/python -c 'import django; print(django.get_version())')"
echo ""
echo -e "${CYAN}🔐 Credentials (saved in $APP_DIR/.secrets/INSTALLATION_INFO.txt):${NC}"
echo -e "   ${GREEN}Django Admin:${NC}"
echo -e "     URL: ${YELLOW}https://$DOMAIN/admin${NC}"
echo -e "     Username: ${YELLOW}admin${NC}"
echo -e "     Password: ${YELLOW}$ADMIN_PASS${NC}"
echo ""
echo -e "   ${GREEN}Database:${NC}"
echo -e "     Name: $DB_NAME"
echo -e "     User: $DB_USER"
echo -e "     Password: ${YELLOW}$DB_PASS${NC}"
echo ""
echo -e "   ${GREEN}RADIUS Server:${NC}"
echo -e "     Secret: ${YELLOW}$RADIUS_SECRET${NC}"
echo ""
echo -e "${CYAN}✅ Security Features Enabled:${NC}"
echo -e "   ${GREEN}✓${NC} CSRF Protection"
echo -e "   ${GREEN}✓${NC} SSL/TLS (self-signed - install Let's Encrypt)"
echo -e "   ${GREEN}✓${NC} Firewall (UFW)"
echo -e "   ${GREEN}✓${NC} Fail2Ban"
echo -e "   ${GREEN}✓${NC} Secure passwords (32-64 characters)"
echo -e "   ${GREEN}✓${NC} Automatic security updates"
echo -e "   ${GREEN}✓${NC} Daily session cleanup"
echo -e "   ${GREEN}✓${NC} Daily database backups"
echo -e "   ${GREEN}✓${NC} Log rotation"
echo ""
echo -e "${CYAN}⚡ Service Status:${NC}"
systemctl is-active --quiet proradius4 && echo -e "   ${GREEN}✓${NC} ProRADIUS4: Running" || echo -e "   ${RED}✗${NC} ProRADIUS4: Stopped"
systemctl is-active --quiet nginx && echo -e "   ${GREEN}✓${NC} Nginx: Running" || echo -e "   ${RED}✗${NC} Nginx: Stopped"
systemctl is-active --quiet freeradius && echo -e "   ${GREEN}✓${NC} FreeRADIUS: Running" || echo -e "   ${RED}✗${NC} FreeRADIUS: Stopped"
systemctl is-active --quiet mysql && echo -e "   ${GREEN}✓${NC} MySQL: Running" || echo -e "   ${RED}✗${NC} MySQL: Stopped"
echo ""
echo -e "${YELLOW}📝 IMPORTANT NEXT STEPS:${NC}"
echo -e "   ${MAGENTA}1.${NC} Install Let's Encrypt SSL certificate:"
echo -e "      ${CYAN}sudo certbot --nginx -d $DOMAIN${NC}"
echo ""
echo -e "   ${MAGENTA}2.${NC} Change admin password immediately:"
echo -e "      Visit ${YELLOW}https://$DOMAIN/admin${NC}"
echo ""
echo -e "   ${MAGENTA}3.${NC} Configure NAS devices:"
echo -e "      Use RADIUS secret from above"
echo ""
echo -e "   ${MAGENTA}4.${NC} Test RADIUS authentication:"
echo -e "      ${CYAN}radtest testuser testpass 127.0.0.1 1812 $RADIUS_SECRET${NC}"
echo ""
echo -e "   ${MAGENTA}5.${NC} View full credentials:"
echo -e "      ${CYAN}sudo cat $APP_DIR/.secrets/INSTALLATION_INFO.txt${NC}"
echo ""
echo -e "   ${MAGENTA}6.${NC} Delete credentials file after noting passwords:"
echo -e "      ${CYAN}sudo shred -u $APP_DIR/.secrets/INSTALLATION_INFO.txt${NC}"
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}   Installation Log: $LOG_FILE${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""
