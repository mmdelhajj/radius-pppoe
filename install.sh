#!/bin/bash
################################################################################
# ProRADIUS4 - Automated Installation Script
# ISP Billing and RADIUS Management System
#
# This script will install and configure:
# - Python 3.8+ with Django 4.1.13
# - MySQL/MariaDB database
# - FreeRADIUS 3.0 server
# - Nginx web server
# - Gunicorn WSGI server
# - All required dependencies
#
# Usage: sudo bash install.sh
################################################################################

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
DB_NAME="proradius4"
DB_USER="proradius"
DB_PASS=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
RADIUS_SECRET=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
DJANGO_SECRET=$(openssl rand -base64 50 | tr -d "=+/")
APP_DIR="/home/proradius4"
DOMAIN="proradius.local"  # Change this to your domain

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}   ProRADIUS4 - ISP Billing & RADIUS Management System${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root (use sudo)${NC}"
   exit 1
fi

echo -e "${YELLOW}[*] Detecting system...${NC}"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
    echo -e "${GREEN}✓ Detected: $PRETTY_NAME${NC}"
else
    echo -e "${RED}Cannot detect operating system${NC}"
    exit 1
fi

# Update system
echo -e "${YELLOW}[*] Updating system packages...${NC}"
apt-get update -qq

# Install required system packages
echo -e "${YELLOW}[*] Installing system dependencies...${NC}"
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
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
    > /dev/null 2>&1

echo -e "${GREEN}✓ System dependencies installed${NC}"

# Create application user
echo -e "${YELLOW}[*] Creating application user...${NC}"
if ! id -u proradius > /dev/null 2>&1; then
    useradd -m -s /bin/bash proradius
    echo -e "${GREEN}✓ User 'proradius' created${NC}"
else
    echo -e "${GREEN}✓ User 'proradius' already exists${NC}"
fi

# Create application directory
echo -e "${YELLOW}[*] Creating application directories...${NC}"
mkdir -p $APP_DIR
mkdir -p $APP_DIR/logs
mkdir -p $APP_DIR/media
mkdir -p $APP_DIR/staticfiles
chown -R proradius:proradius $APP_DIR

# Configure MySQL
echo -e "${YELLOW}[*] Configuring MySQL database...${NC}"
systemctl start mysql
systemctl enable mysql > /dev/null 2>&1

mysql -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null || true
mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';" 2>/dev/null || true
mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

echo -e "${GREEN}✓ MySQL database configured${NC}"
echo -e "${BLUE}  Database: $DB_NAME${NC}"
echo -e "${BLUE}  User: $DB_USER${NC}"
echo -e "${BLUE}  Password: $DB_PASS${NC}"

# Import database schema
if [ -f "database/schema.sql" ]; then
    echo -e "${YELLOW}[*] Importing database schema...${NC}"
    mysql $DB_NAME < database/schema.sql
    echo -e "${GREEN}✓ Database schema imported${NC}"
fi

# Create Python virtual environment
echo -e "${YELLOW}[*] Creating Python virtual environment...${NC}"
python3 -m venv $APP_DIR/venv
source $APP_DIR/venv/bin/activate

# Install Python packages
echo -e "${YELLOW}[*] Installing Python dependencies...${NC}"
cat > /tmp/requirements.txt <<EOF
Django==4.1.13
mysqlclient==2.2.0
gunicorn==21.2.0
python-dotenv==1.0.0
requests==2.31.0
pillow==10.0.0
celery==5.3.1
redis==4.6.0
paramiko==3.3.1
pytz==2023.3
EOF

pip install --upgrade pip -qq
pip install -r /tmp/requirements.txt -qq

echo -e "${GREEN}✓ Python dependencies installed${NC}"

# Copy application files
echo -e "${YELLOW}[*] Copying application files...${NC}"
if [ -d "backend" ]; then
    cp -r backend/* $APP_DIR/ 2>/dev/null || true
fi
if [ -d "frontend" ]; then
    cp -r frontend/* $APP_DIR/ 2>/dev/null || true
fi

# Create Django settings with generated secrets
echo -e "${YELLOW}[*] Configuring Django settings...${NC}"
if [ -f "$APP_DIR/proradius4/settings.py" ]; then
    sed -i "s/SECRET_KEY = .*/SECRET_KEY = '$DJANGO_SECRET'/" $APP_DIR/proradius4/settings.py
    sed -i "s/'PASSWORD': .*/'PASSWORD': '$DB_PASS',/" $APP_DIR/proradius4/settings.py
    sed -i "s/'NAME': .*/'NAME': '$DB_NAME',/" $APP_DIR/proradius4/settings.py
    sed -i "s/'USER': .*/'USER': '$DB_USER',/" $APP_DIR/proradius4/settings.py
else
    # Use the settings from our repository
    mkdir -p $APP_DIR/proradius4
    cp backend/settings.py $APP_DIR/proradius4/settings.py
    sed -i "s/SECRET_KEY = .*/SECRET_KEY = '$DJANGO_SECRET'/" $APP_DIR/proradius4/settings.py
    sed -i "s/'PASSWORD': .*/'PASSWORD': '$DB_PASS',/" $APP_DIR/proradius4/settings.py
fi

# Django migrations
echo -e "${YELLOW}[*] Running Django migrations...${NC}"
cd $APP_DIR
python manage.py makemigrations 2>/dev/null || true
python manage.py migrate --noinput

# Create Django superuser
echo -e "${YELLOW}[*] Creating Django superuser...${NC}"
echo "from django.contrib.auth import get_user_model; User = get_user_model(); User.objects.filter(username='admin').exists() or User.objects.create_superuser('admin', 'admin@$DOMAIN', 'admin123')" | python manage.py shell

# Collect static files
python manage.py collectstatic --noinput -clear

echo -e "${GREEN}✓ Django application configured${NC}"

# Configure FreeRADIUS
echo -e "${YELLOW}[*] Configuring FreeRADIUS...${NC}"

# Configure SQL module
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

# Enable SQL module
ln -sf /etc/freeradius/3.0/mods-available/sql /etc/freeradius/3.0/mods-enabled/sql

# Configure clients
cat > /etc/freeradius/3.0/clients.conf <<EOF
client localhost {
    ipaddr = 127.0.0.1
    secret = $RADIUS_SECRET
    require_message_authenticator = no
    nas_type = other
}
EOF

# Restart FreeRADIUS
systemctl restart freeradius
systemctl enable freeradius > /dev/null 2>&1

echo -e "${GREEN}✓ FreeRADIUS configured and started${NC}"

# Configure Gunicorn
echo -e "${YELLOW}[*] Configuring Gunicorn...${NC}"
cat > /etc/systemd/system/proradius4.service <<EOF
[Unit]
Description=ProRADIUS4 Gunicorn Service
After=network.target mysql.service

[Service]
Type=notify
User=proradius
Group=proradius
WorkingDirectory=$APP_DIR
Environment="PATH=$APP_DIR/venv/bin"
ExecStart=$APP_DIR/venv/bin/gunicorn \\
    --workers 16 \\
    --bind 127.0.0.1:8000 \\
    --timeout 300 \\
    --access-logfile $APP_DIR/logs/gunicorn-access.log \\
    --error-logfile $APP_DIR/logs/gunicorn-error.log \\
    --log-level info \\
    proradius4.wsgi:application

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start proradius4
systemctl enable proradius4 > /dev/null 2>&1

echo -e "${GREEN}✓ Gunicorn service configured${NC}"

# Configure Nginx
echo -e "${YELLOW}[*] Configuring Nginx...${NC}"
cat > /etc/nginx/sites-available/proradius4 <<EOF
upstream proradius4 {
    server 127.0.0.1:8000;
}

server {
    listen 80;
    server_name $DOMAIN;

    client_max_body_size 100M;

    access_log $APP_DIR/logs/nginx-access.log;
    error_log $APP_DIR/logs/nginx-error.log;

    location /static/ {
        alias $APP_DIR/staticfiles/;
        expires 30d;
    }

    location /media/ {
        alias $APP_DIR/media/;
        expires 30d;
    }

    location / {
        proxy_pass http://proradius4;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
    }
}
EOF

ln -sf /etc/nginx/sites-available/proradius4 /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl restart nginx
systemctl enable nginx > /dev/null 2>&1

echo -e "${GREEN}✓ Nginx configured${NC}"

# Set proper permissions
chown -R proradius:proradius $APP_DIR

# Display installation summary
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}   Installation Completed Successfully!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}📊 System Information:${NC}"
echo -e "   Application Directory: $APP_DIR"
echo -e "   Domain: http://$DOMAIN"
echo ""
echo -e "${BLUE}🔐 Database Credentials:${NC}"
echo -e "   Database: $DB_NAME"
echo -e "   User: $DB_USER"
echo -e "   Password: $DB_PASS"
echo ""
echo -e "${BLUE}🌐 Django Admin:${NC}"
echo -e "   URL: http://$DOMAIN/admin"
echo -e "   Username: admin"
echo -e "   Password: admin123"
echo -e "   ${YELLOW}⚠ CHANGE THIS PASSWORD IMMEDIATELY!${NC}"
echo ""
echo -e "${BLUE}🔄 RADIUS Server:${NC}"
echo -e "   Secret: $RADIUS_SECRET"
echo -e "   Port: 1812 (Auth), 1813 (Acct)"
echo ""
echo -e "${BLUE}📝 Important Files:${NC}"
echo -e "   Settings: $APP_DIR/proradius4/settings.py"
echo -e "   Logs: $APP_DIR/logs/"
echo -e "   FreeRADIUS Config: /etc/freeradius/3.0/"
echo ""
echo -e "${BLUE}🛠 Service Management:${NC}"
echo -e "   systemctl status proradius4    # Check Django app status"
echo -e "   systemctl status nginx         # Check Nginx status"
echo -e "   systemctl status freeradius    # Check RADIUS status"
echo -e "   systemctl status mysql         # Check MySQL status"
echo ""
echo -e "${YELLOW}⚠ Next Steps:${NC}"
echo -e "   1. Change default admin password"
echo -e "   2. Configure your domain in /etc/nginx/sites-available/proradius4"
echo -e "   3. Update Django ALLOWED_HOSTS in settings.py"
echo -e "   4. Configure SSL certificate (recommended: certbot)"
echo -e "   5. Add your NAS devices in the admin panel"
echo ""
echo -e "${GREEN}✓ Installation complete! Access your panel at http://$DOMAIN${NC}"
echo ""

# Save credentials to file
cat > $APP_DIR/INSTALLATION_INFO.txt <<EOF
ProRADIUS4 Installation Information
Generated: $(date)

Database:
  Name: $DB_NAME
  User: $DB_USER
  Password: $DB_PASS

Django Admin:
  URL: http://$DOMAIN/admin
  Username: admin
  Password: admin123

RADIUS Server:
  Secret: $RADIUS_SECRET
  Auth Port: 1812
  Acct Port: 1813

Application Directory: $APP_DIR
EOF

chmod 600 $APP_DIR/INSTALLATION_INFO.txt
chown proradius:proradius $APP_DIR/INSTALLATION_INFO.txt

echo -e "${BLUE}ℹ Installation details saved to: $APP_DIR/INSTALLATION_INFO.txt${NC}"
echo ""
