# Server Avengers Deployment Guide on AWS

## Overview
This guide provides step-by-step instructions to deploy Server Avengers on Amazon Web Services (AWS) using EC2, RDS, and related services.

---

## Architecture

```
Internet
    ↓
Route 53 (DNS)
    ↓
CloudFront (CDN - Optional)
    ↓
Elastic Load Balancer (ALB/NLB - Optional)
    ↓
EC2 Instance (Web Server + PHP)
    ↓
RDS Database (MySQL/PostgreSQL)
    ↓
S3 Bucket (File Uploads & Backups)
```

---

## Prerequisites

- AWS Account with billing enabled
- Basic knowledge of AWS services
- Domain name (optional but recommended)
- SSH client (PuTTY, Git Bash, or native SSH)

---

## Step 1: Create RDS Database Instance

### 1.1 Create RDS Instance

1. **Go to AWS Console** → Search for **RDS**
2. Click **Create Database**
3. Select **Standard Create** and configure:

```
Engine Options:
- Choose: MySQL 8.0 (or PostgreSQL 14+)
- Edition: Community

DB Instance Class:
- db.t3.micro (Free tier eligible)

Storage:
- Storage Type: General Purpose (gp2)
- Allocated Storage: 20 GB
- Enable Storage Auto Scaling: Yes

Availability & Durability:
- Multi-AZ: No (for dev/test)
- Yes (for production)

Connectivity:
- VPC: Default VPC
- Publicly Accessible: Yes (for setup only)
- VPC Security Group: Create new (rosariosis-db-sg)
- Database Port: 3306 (MySQL) or 5432 (PostgreSQL)

Database Authentication:
- Authentication: Password authentication

Initial Database Configuration:
- DB Instance Identifier: rosariosis-db
- Master Username: rosariosis_admin
- Master Password: [Create strong password - 16+ chars]
- Initial Database Name: rosariosis
```

4. Click **Create Database** and wait for it to be available (5-10 minutes)

### 1.2 Configure RDS Security Group

1. Go to **EC2 → Security Groups**
2. Find **rosariosis-db-sg**
3. Add Inbound Rule:
   - Type: MySQL/Aurora
   - Source: 0.0.0.0/0 (Restrict to your IP for production)
   - Port: 3306

---

## Step 2: Create EC2 Instance (Web Server)

### 2.1 Launch EC2 Instance

1. **Go to AWS Console** → **EC2 Dashboard**
2. Click **Launch Instance**
3. Configure:

```
Name: rosariosis-web-server

AMI (Amazon Machine Image):
- Ubuntu Server 22.04 LTS
- or Amazon Linux 2

Instance Type:
- t3.micro (Free tier)
- or t3.small for better performance

Key Pair:
- Create new key pair: rosariosis-key
- Save .pem file securely

Network Settings:
- VPC: Default VPC
- Auto-assign public IP: Enable
- Security Group: Create new (rosariosis-web-sg)

Storage:
- EBS Volume: 30 GB
- Volume Type: gp2

Advanced:
- IAM instance profile: Create role with S3 access (optional)
```

### 2.2 Configure Web Server Security Group

1. Go to **EC2 → Security Groups**
2. Find **rosariosis-web-sg**
3. Add Inbound Rules:
   - Type: SSH, Port: 22, Source: Your IP
   - Type: HTTP, Port: 80, Source: 0.0.0.0/0
   - Type: HTTPS, Port: 443, Source: 0.0.0.0/0

---

## Step 3: Connect to EC2 and Install Software

### 3.1 Connect via SSH

```bash
# On Windows (Git Bash or PowerShell)
ssh -i "rosariosis-key.pem" ubuntu@<EC2-PUBLIC-IP>

# On Mac/Linux
chmod 400 rosariosis-key.pem
ssh -i rosariosis-key.pem ubuntu@<EC2-PUBLIC-IP>
```

### 3.2 Update System and Install Dependencies

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install Apache, PHP, and Extensions
sudo apt install -y apache2 php8.1 php8.1-{mysql,pgsql,pdo,gettext,intl,mbstring,gd,curl,xml,zip,cli}

# Install MySQL Client (for RDS connection)
sudo apt install -y mysql-client

# Install Composer (optional, for dependencies)
sudo apt install -y composer

# Start Apache
sudo systemctl start apache2
sudo systemctl enable apache2
```

### 3.3 Enable PHP Modules

```bash
# Enable Apache rewrite module
sudo a2enmod rewrite
sudo systemctl restart apache2
```

### 3.4 Configure PHP

```bash
# Edit PHP configuration
sudo nano /etc/php/8.1/apache2/php.ini

# Find and update these settings:
# max_upload_size = 64M
# post_max_size = 64M
# memory_limit = 256M

# Restart Apache
sudo systemctl restart apache2
```

---

## Step 4: Download and Configure Server Avengers

### 4.1 Clone Server Avengers Repository

```bash
# Navigate to web root
cd /var/www/html

# Clone Server Avengers
sudo git clone https://gitlab.com/francoisjacquet/rosariosis.git
sudo mv rosariosis/* .
sudo rm -rf rosariosis

# Change permissions
sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 755 /var/www/html
```

### 4.2 Create config.inc.php

```bash
# Copy sample configuration
sudo cp config.inc.sample.php config.inc.php

# Edit configuration
sudo nano config.inc.php
```

### 4.3 Update config.inc.php with RDS Details

Find RDS endpoint and port from AWS Console → RDS → Databases → rosariosis-db

```php
<?php

// Database Settings
$DatabaseType = 'mysql';  // or 'postgresql'

// Get RDS Endpoint from AWS Console
// Format: rosariosis-db.xxxxxxxxxxxx.us-east-1.rds.amazonaws.com
$DatabaseServer = 'rosariosis-db.xxxxxxxxxxxx.us-east-1.rds.amazonaws.com';

$DatabaseUsername = 'rosariosis_admin';
$DatabasePassword = 'your_strong_password_here';
$DatabaseName = 'rosariosis';
$DatabasePort = 3306;  // 5432 for PostgreSQL

// Paths
$DatabaseDumpPath = '/usr/bin/mysqldump';
// $DatabaseDumpPath = '/usr/bin/pg_dump';  // For PostgreSQL
$wkhtmltopdfPath = '';

// School Year
$DefaultSyear = '2025';

// Email Notifications
$RosarioNotifyAddress = 'admin@yourdomain.com';
$RosarioErrorsAddress = 'errors@yourdomain.com';

// Locales
$RosarioLocales = [ 'en_US.utf8' ];

// Optional: Enable HTTPS
// define( 'ROSARIO_FORCE_HTTPS', true );

// Optional: Debug mode (disable in production)
// define( 'ROSARIO_DEBUG', false );

?>
```

---

## Step 5: Import Database Schema

### 5.1 Connect to RDS and Create User

```bash
# Connect to RDS MySQL
mysql -h rosariosis-db.xxxxxxxxxxxx.us-east-1.rds.amazonaws.com \
      -u rosariosis_admin -p rosariosis

# In MySQL console:
mysql> SET GLOBAL log_bin_trust_function_creators=1;

mysql> CREATE USER 'rosariosis_user'@'%' IDENTIFIED BY 'app_password_here';
mysql> GRANT ALL PRIVILEGES ON rosariosis.* TO 'rosariosis_user'@'%';
mysql> FLUSH PRIVILEGES;
mysql> EXIT;
```

### 5.2 Import Database Dump

```bash
# From EC2 instance, navigate to RosarioSIS directory
cd /var/www/html

# Import MySQL schema
mysql -h rosariosis-db.xxxxxxxxxxxx.us-east-1.rds.amazonaws.com \
      -u rosariosis_admin -p rosariosis < rosariosis_mysql.sql

# Or for PostgreSQL
psql -h rosariosis-db.xxxxxxxxxxxx.us-east-1.rds.amazonaws.com \
     -U rosariosis_admin -d rosariosis < rosariosis.sql
```

### 5.3 Verify Database

```bash
mysql -h rosariosis-db.xxxxxxxxxxxx.us-east-1.rds.amazonaws.com \
      -u rosariosis_admin -p rosariosis -e "SHOW TABLES;"
```

---

## Step 6: Configure Web Server

### 6.1 Create Apache Virtual Host

```bash
sudo nano /etc/apache2/sites-available/rosariosis.conf
```

Add this configuration:

```apache
<VirtualHost *:80>
    ServerName yourdomain.com
    ServerAlias www.yourdomain.com
    ServerAdmin admin@yourdomain.com
    
    DocumentRoot /var/www/html
    
    <Directory /var/www/html>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog ${APACHE_LOG_DIR}/rosariosis_error.log
    CustomLog ${APACHE_LOG_DIR}/rosariosis_access.log combined
    
    # Enable Gzip compression
    <IfModule mod_deflate.c>
        AddOutputFilterByType DEFLATE text/plain
        AddOutputFilterByType DEFLATE text/html
        AddOutputFilterByType DEFLATE text/xml
        AddOutputFilterByType DEFLATE text/css
        AddOutputFilterByType DEFLATE application/xml
        AddOutputFilterByType DEFLATE application/xhtml+xml
        AddOutputFilterByType DEFLATE application/rss+xml
        AddOutputFilterByType DEFLATE application/javascript
        AddOutputFilterByType DEFLATE application/x-javascript
    </IfModule>
</VirtualHost>
```

### 6.2 Enable Virtual Host and Rewrite Module

```bash
# Enable site
sudo a2ensite rosariosis.conf

# Disable default site
sudo a2dissite 000-default.conf

# Verify Apache configuration
sudo apache2ctl configtest

# Restart Apache
sudo systemctl restart apache2
```

---

## Step 7: Set up SSL/TLS with Let's Encrypt

### 7.1 Install Certbot

```bash
sudo apt install -y certbot python3-certbot-apache
```

### 7.2 Generate SSL Certificate

```bash
sudo certbot --apache -d yourdomain.com -d www.yourdomain.com

# Select options:
# - Enter email
# - Agree to terms
# - Choose HTTPS redirect
```

### 7.3 Auto-Renew Certificate

```bash
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer
```

---

## Step 8: Set Up File Backups (Optional)

### 8.1 Create S3 Bucket

1. Go to **S3 → Buckets**
2. Click **Create Bucket**
   - Name: rosariosis-backups-{account-id}
   - Region: Same as RDS
   - Block public access: Yes
3. Create bucket

### 8.2 Create Backup Script

```bash
# Create backup directory
sudo mkdir -p /var/backups/rosariosis

# Create backup script
sudo nano /usr/local/bin/rosariosis-backup.sh
```

```bash
#!/bin/bash

BACKUP_DIR="/var/backups/rosariosis"
DB_HOST="rosariosis-db.xxxxxxxxxxxx.us-east-1.rds.amazonaws.com"
DB_USER="rosariosis_admin"
DB_PASSWORD="your_password"
DB_NAME="rosariosis"
S3_BUCKET="rosariosis-backups-123456789"
DATE=$(date +"%Y-%m-%d_%H-%M-%S")

# Backup database
mysqldump -h $DB_HOST -u $DB_USER -p$DB_PASSWORD $DB_NAME > \
  $BACKUP_DIR/db_backup_$DATE.sql

# Compress backup
gzip $BACKUP_DIR/db_backup_$DATE.sql

# Upload to S3
aws s3 cp $BACKUP_DIR/db_backup_$DATE.sql.gz \
  s3://$S3_BUCKET/db_backups/

# Clean old local backups (keep last 7 days)
find $BACKUP_DIR -name "db_backup_*.sql.gz" -mtime +7 -delete

echo "Backup completed: db_backup_$DATE.sql.gz"
```

### 8.3 Schedule Backup with Cron

```bash
# Make script executable
sudo chmod +x /usr/local/bin/rosariosis-backup.sh

# Edit crontab
sudo crontab -e

# Add this line (backup daily at 2 AM)
0 2 * * * /usr/local/bin/rosariosis-backup.sh >> /var/log/rosariosis-backup.log 2>&1
```

---

## Step 9: Access RosarioSIS

### Visit Application

1. Open browser and navigate to:
   - http://yourdomain.com (if DNS configured)
   - http://{EC2-PUBLIC-IP} (direct IP)

2. Log in with:
   - **Username**: admin
   - **Password**: admin

3. **Change default password immediately**

---

## Step 10: Enable Monitoring and Logging

### 10.1 CloudWatch Monitoring

1. Go to **CloudWatch → Dashboards**
2. Create dashboard and add:
   - EC2 CPU Utilization
   - EC2 Network In/Out
   - RDS Database Connections
   - RDS CPU Utilization

### 10.2 Enable RDS Enhanced Monitoring

1. Go to **RDS → Databases → rosariosis-db**
2. Click **Modify**
3. Enable **Enhanced Monitoring**
4. Choose monitoring role: Create new

---

## Troubleshooting

### Can't Connect to Database

```bash
# Test connection from EC2
mysql -h rosariosis-db.xxxxxxxxxxxx.us-east-1.rds.amazonaws.com \
      -u rosariosis_admin -p rosariosis -e "SELECT 1;"

# Check RDS security group inbound rules
# Make sure MySQL port 3306 is allowed from EC2 security group
```

### Permission Denied Errors

```bash
# Fix permissions
sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 755 /var/www/html
sudo systemctl restart apache2
```

### PHP Extensions Missing

```bash
# Check installed extensions
php -m

# Install missing extension
sudo apt install -y php8.1-{extension-name}
sudo systemctl restart apache2
```

---

## Production Best Practices

1. **Enable Multi-AZ** for RDS (automatic failover)
2. **Use Elastic IP** for EC2 instance
3. **Enable backups** for RDS (automated daily)
4. **Use ALB** for load balancing (if scaling)
5. **Enable VPC encryption** for data in transit
6. **Use Secrets Manager** for sensitive credentials
7. **Enable CloudTrail** for audit logging
8. **Set up CloudWatch alarms** for critical metrics
9. **Use Auto Scaling Groups** for horizontal scaling
10. **Implement WAF** (Web Application Firewall)

---

## Cost Optimization

- Use **t3.micro** EC2 for development
- Use **db.t3.micro** RDS for development
- Enable **RDS automatic backups** (35 days retention)
- Use **CloudFront** for static content delivery
- Set up **Reserved Instances** for long-term savings
- Monitor **CloudWatch** for unused resources

---

## Additional Resources

- [AWS EC2 Documentation](https://docs.aws.amazon.com/ec2/)
- [AWS RDS Documentation](https://docs.aws.amazon.com/rds/)
- [RosarioSIS Official Site](https://www.rosariosis.org)
- [RosarioSIS Docker Repository](https://gitlab.com/francoisjacquet/docker-rosariosis/)

---

## Support

For issues with Server Avengers:
- [Server Avengers Documentation](https://www.serveravengers.org)
- [GitLab Issues](https://gitlab.com/francoisjacquet/rosariosis/-/issues)

For AWS support:
- [AWS Support Center](https://console.aws.amazon.com/support/)
