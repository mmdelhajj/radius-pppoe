# ProRADIUS4 - ISP Billing & RADIUS Management System

Complete ISP management solution combining billing, RADIUS authentication, IPTV management, and customer portal.

## Features

### Core ISP Management
- **Customer Management**: Complete subscriber lifecycle management
- **Multi-tenant Support**: Hierarchical reseller system with commission tracking
- **Service Packages**: Flexible bandwidth plans with FUP (Fair Usage Policy)
- **PPPoE Authentication**: Integration with FreeRADIUS for PPPoE/Hotspot
- **Real-time Session Monitoring**: Track active connections and bandwidth usage

### Billing System
- **Automated Invoicing**: Generate recurring invoices automatically
- **Multiple Payment Methods**: Cash, bank transfer, credit card support
- **Transaction Logging**: Complete financial audit trail
- **Credit Management**: Customer balance and credit limit tracking
- **Commission System**: Automatic reseller commission calculation

### IPTV Management
- **Channel Management**: Organize channels by categories
- **EPG Integration**: Electronic Program Guide support
- **Multi-device Support**: MAC address and device ID binding
- **Package Management**: Create bundled IPTV packages
- **Subscription Control**: Automatic expiry management

### Network Management
- **NAS Device Management**: Support for MikroTik, Cisco, and generic RADIUS
- **Bandwidth Control**: Dynamic speed limiting via RADIUS
- **Quota Management**: Daily/monthly data caps with automatic cutoff
- **Online Users**: Real-time session tracking
- **Connection History**: Complete accounting logs

### Support System
- **Ticket Management**: Customer support ticket system
- **Internal Notes**: Staff communication tools
- **Priority Levels**: Urgent, high, medium, low
- **Assignment System**: Route tickets to specific staff
- **Status Tracking**: Open, in progress, resolved, closed

### Reporting
- **Revenue Reports**: Daily, monthly, yearly financial summaries
- **Usage Reports**: Bandwidth consumption analysis
- **Customer Reports**: Active, expired, suspended accounts
- **Payment Reports**: Transaction history and pending invoices
- **Top Users**: Identify highest bandwidth consumers

## Technology Stack

- **Backend**: Django 4.1.13 (Python 3.8+)
- **Database**: MySQL 5.7 / MariaDB 10.3+
- **RADIUS**: FreeRADIUS 3.0
- **Web Server**: Nginx 1.18+
- **WSGI Server**: Gunicorn with 16 workers
- **Frontend**: Bootstrap 4, jQuery, DataTables
- **Cache**: Redis (optional)
- **Task Queue**: Celery (optional)

## System Requirements

### Minimum Requirements
- **OS**: Ubuntu 20.04 LTS or Debian 11+
- **CPU**: 2 cores
- **RAM**: 4 GB
- **Storage**: 20 GB SSD
- **Network**: 100 Mbps

### Recommended for Production
- **OS**: Ubuntu 22.04 LTS
- **CPU**: 4+ cores
- **RAM**: 8+ GB
- **Storage**: 50+ GB SSD (RAID 1)
- **Network**: 1 Gbps

## Quick Installation

### One-Line Installer

```bash
sudo bash install.sh
```

This will automatically:
1. Install all required packages
2. Configure MySQL database
3. Set up FreeRADIUS server
4. Configure Nginx and Gunicorn
5. Create initial admin user
6. Generate secure random passwords

### Manual Installation

#### 1. Install System Dependencies

```bash
apt-get update
apt-get install -y python3 python3-pip python3-venv \
    mysql-server nginx freeradius freeradius-mysql \
    freeradius-utils build-essential libmysqlclient-dev
```

#### 2. Create Database

```bash
mysql -e "CREATE DATABASE proradius4 CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE USER 'proradius'@'localhost' IDENTIFIED BY 'YOUR_PASSWORD';"
mysql -e "GRANT ALL PRIVILEGES ON proradius4.* TO 'proradius'@'localhost';"
mysql proradius4 < database/schema.sql
```

#### 3. Setup Python Environment

```bash
python3 -m venv /home/proradius4/venv
source /home/proradius4/venv/bin/activate
pip install -r requirements.txt
```

#### 4. Configure Django

```bash
cp backend/settings.py /home/proradius4/proradius4/settings.py
# Edit settings.py and update:
# - SECRET_KEY
# - DATABASE credentials
# - ALLOWED_HOSTS
```

#### 5. Run Migrations

```bash
cd /home/proradius4
python manage.py migrate
python manage.py createsuperuser
python manage.py collectstatic
```

#### 6. Configure FreeRADIUS

```bash
cp configs/freeradius/sql /etc/freeradius/3.0/mods-available/sql
ln -s /etc/freeradius/3.0/mods-available/sql /etc/freeradius/3.0/mods-enabled/sql
systemctl restart freeradius
```

#### 7. Configure Nginx

```bash
cp configs/nginx/proradius4 /etc/nginx/sites-available/
ln -s /etc/nginx/sites-available/proradius4 /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx
```

#### 8. Start Gunicorn

```bash
cp configs/systemd/proradius4.service /etc/systemd/system/
systemctl daemon-reload
systemctl start proradius4
systemctl enable proradius4
```

## Configuration

### Django Settings

Key settings in `backend/settings.py`:

```python
# Security
SECRET_KEY = 'your-secret-key-here'
DEBUG = False
ALLOWED_HOSTS = ['your-domain.com', 'IP-ADDRESS']

# Database
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.mysql',
        'NAME': 'proradius4',
        'USER': 'proradius',
        'PASSWORD': 'your-password',
        'HOST': '127.0.0.1',
        'PORT': '3306',
    }
}

# Timezone
TIME_ZONE = 'Asia/Beirut'

# Currency
CURRENCY_SYMBOL = 'USD'
TAX_RATE = 0.11  # 11% tax
```

### FreeRADIUS Configuration

Edit `/etc/freeradius/3.0/mods-available/sql`:

```
sql {
    driver = "rlm_sql_mysql"
    server = "localhost"
    port = 3306
    login = "proradius"
    password = "your-password"
    radius_db = "proradius4"

    # Table mappings
    acct_table1 = "khradacct"
    authcheck_table = "radcheck"
    authreply_table = "radreply"
    # ... (see install.sh for complete config)
}
```

### NAS Device Configuration

Add your router in admin panel or directly:

```sql
INSERT INTO khnas (nasname, shortname, type, secret, ip_address)
VALUES ('192.168.1.1', 'Router1', 'mikrotik', 'testing123', '192.168.1.1');
```

## Usage

### Admin Panel

Access at: `http://your-domain/admin`

Default credentials (change immediately):
- **Username**: admin
- **Password**: admin123

### Create Customer

1. Go to **Customers** → **Add Customer**
2. Fill in details:
   - Username (PPPoE login)
   - Password
   - Service Package
   - Contact information
3. System automatically creates RADIUS entries

### Create Service Package

1. Go to **Services** → **Add Package**
2. Define:
   - Download/Upload speeds (kbps)
   - Burst speeds
   - Daily/Monthly quotas (MB)
   - Price and validity
   - Session limits

### Monitor Online Users

1. Go to **Monitoring** → **Online Users**
2. View:
   - Active sessions
   - Connected IPs
   - Session duration
   - Bandwidth usage
3. Disconnect users if needed (CoA)

### Generate Reports

1. Go to **Reports**
2. Select report type:
   - Revenue reports
   - Usage statistics
   - Customer reports
3. Choose date range
4. Export to PDF/Excel

## API Integration

### MikroTik RouterOS

Configure MikroTik to use ProRADIUS:

```
/radius add service=ppp address=YOUR_SERVER_IP secret=testing123
/ppp aaa set use-radius=yes accounting=yes
```

### Custom API

ProRADIUS provides REST API endpoints:

```bash
# Authenticate user
curl -X POST http://your-domain/api/authenticate/ \
  -H "Content-Type: application/json" \
  -d '{"username":"user1","password":"pass123"}'

# Check user status
curl http://your-domain/api/user/user1/status/

# Get online users
curl http://your-domain/api/online-users/
```

## Database Schema

### Key Tables

- **khclient**: Customer accounts (243 customers in production)
- **khreseller**: Reseller accounts with hierarchy
- **servicequota**: Service packages (42 packages)
- **khradacct**: RADIUS accounting logs (515K+ sessions)
- **translog**: Financial transactions (2,587 transactions)
- **khnas**: NAS devices (routers/APs)

See `database/schema.sql` for complete structure.

## Troubleshooting

### RADIUS Not Authenticating

```bash
# Test RADIUS locally
radtest username password 127.0.0.1 1812 testing123

# Check RADIUS logs
tail -f /var/log/freeradius/radius.log

# Verify SQL connection
mysql -u proradius -p proradius4 -e "SELECT * FROM radcheck LIMIT 5;"
```

### Gunicorn Not Starting

```bash
# Check status
systemctl status proradius4

# View logs
journalctl -u proradius4 -f

# Test manually
cd /home/proradius4
source venv/bin/activate
gunicorn --bind 127.0.0.1:8000 proradius4.wsgi:application
```

### High Database Size

```bash
# Check table sizes
mysql proradius4 -e "SELECT table_name,
    ROUND(((data_length + index_length) / 1024 / 1024), 2) AS 'Size (MB)'
    FROM information_schema.TABLES
    WHERE table_schema = 'proradius4'
    ORDER BY (data_length + index_length) DESC;"

# Archive old accounting logs
mysql proradius4 -e "DELETE FROM khradacct WHERE acctstoptime < DATE_SUB(NOW(), INTERVAL 6 MONTH);"

# Clean old Django sessions
python manage.py clearsessions
```

### Performance Optimization

```bash
# Enable MySQL query cache
echo "query_cache_size = 64M" >> /etc/mysql/mysql.conf.d/mysqld.cnf

# Add indexes for common queries
mysql proradius4 < database/indexes.sql

# Enable Redis caching (optional)
pip install django-redis
# Add to settings.py cache configuration
```

## Security Best Practices

1. **Change Default Passwords**: Immediately after installation
2. **Use HTTPS**: Install SSL certificate (Let's Encrypt recommended)
3. **Firewall Rules**: Restrict RADIUS ports to NAS devices only
4. **Database Backups**: Automated daily backups
5. **Update Regularly**: Keep system packages updated
6. **Strong RADIUS Secret**: Use 32+ character random secrets
7. **Disable Django DEBUG**: Always `DEBUG = False` in production
8. **Session Security**: Configure secure cookies for HTTPS

## Backup & Restore

### Database Backup

```bash
# Full backup
mysqldump -u root -p proradius4 > proradius4_backup_$(date +%Y%m%d).sql

# Schema only
mysqldump -u root -p --no-data proradius4 > proradius4_schema.sql

# Automated daily backup
echo "0 2 * * * mysqldump -u root -pPASSWORD proradius4 > /backup/proradius4_\$(date +\%Y\%m\%d).sql" | crontab -
```

### Restore Database

```bash
mysql -u root -p proradius4 < proradius4_backup_20251130.sql
```

### Application Backup

```bash
tar -czf proradius4_app_$(date +%Y%m%d).tar.gz /home/proradius4
```

## Monitoring

### System Health

```bash
# Check all services
systemctl status proradius4 nginx freeradius mysql

# Monitor resource usage
htop

# Check disk space
df -h

# Monitor database connections
mysql -e "SHOW PROCESSLIST;"
```

### Log Files

- Django: `/home/proradius4/logs/django.log`
- Gunicorn: `/home/proradius4/logs/gunicorn-*.log`
- Nginx: `/home/proradius4/logs/nginx-*.log`
- FreeRADIUS: `/var/log/freeradius/radius.log`
- MySQL: `/var/log/mysql/error.log`

## Scaling

### Database Replication

Setup MySQL master-slave replication for read scaling.

### Load Balancing

Use multiple Gunicorn instances behind Nginx load balancer.

### Caching Layer

Implement Redis for session storage and query caching.

### CDN Integration

Serve static files via CDN (CloudFlare, AWS CloudFront).

## Migration from ProRADIUS3

```bash
# Export customers from old system
./scripts/export_customers.sh

# Import to new system
./scripts/import_customers.sh customers_export.csv

# Migrate accounting data
./scripts/migrate_accounting.sh
```

## Contributing

This is a reconstruction based on ProRADIUS4 production system analysis.
Original source code is compiled (.so files) and not available.

## License

This project template is provided for educational and deployment purposes.

## Support

For issues and questions:
- Check logs first
- Review troubleshooting section
- Test with `radtest` for RADIUS issues
- Verify database connections

## Changelog

### Version 4.0 (Reconstructed)
- Complete database schema extracted
- Django settings configured
- FreeRADIUS integration
- Automated installation script
- Bootstrap 4 admin interface
- Multi-tenant reseller support
- IPTV management system
- Comprehensive reporting

## Credits

Based on ProRADIUS4 production system (172.22.22.5)
Analyzed and reconstructed: November 2025
