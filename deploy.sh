#!/bin/bash

# JuiceBot VPS Deployment Script
# This script sets up the complete application on a VPS

set -e  # Exit on any error

echo "🍹 JuiceBot VPS Deployment Script"
echo "=================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root"
   exit 1
fi

# Update system
print_status "Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Install Node.js 20.x
print_status "Installing Node.js 20.x..."
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install PM2 globally
print_status "Installing PM2 process manager..."
npm install -g pm2

# Install Nginx
print_status "Installing Nginx..."
sudo apt install nginx -y

# Install PostgreSQL
print_status "Installing PostgreSQL..."
sudo apt install postgresql postgresql-contrib -y

# Install SSL certificate tools
print_status "Installing SSL certificate tools..."
sudo apt install certbot python3-certbot-nginx -y

# Create application directory
print_status "Creating application directory..."
sudo mkdir -p /var/www/juicebot
sudo chown $USER:$USER /var/www/juicebot

# Clone or copy application files
print_status "Setting up application files..."
cd /var/www/juicebot

# Create environment file
print_status "Creating environment configuration..."
cat > .env << 'EOF'
# Database
DATABASE_URL=postgresql://juicebot_user:your_secure_password@localhost:5432/juicebot

# WhatsApp API
WHATSAPP_VERIFY_TOKEN=your_verify_token
WHATSAPP_ACCESS_TOKEN=your_access_token
WHATSAPP_PHONE_NUMBER_ID=your_phone_number_id

# JWT Secret
JWT_SECRET=your_jwt_secret_key

# Server
PORT=3000
NODE_ENV=production
FRONTEND_URL=https://your-domain.com
EOF

print_warning "Please edit .env file with your actual credentials!"

# Setup PostgreSQL database
print_status "Setting up PostgreSQL database..."
sudo -u postgres psql << 'EOF'
CREATE DATABASE juicebot;
CREATE USER juicebot_user WITH PASSWORD 'your_secure_password';
GRANT ALL PRIVILEGES ON DATABASE juicebot TO juicebot_user;
\q
EOF

# Install application dependencies
print_status "Installing application dependencies..."
npm install

# Run database migrations
print_status "Running database migrations..."
npm run migrate

# Build frontend
print_status "Building frontend..."
cd frontend
npm install
npm run build
cd ..

# Setup PM2 ecosystem
print_status "Setting up PM2 configuration..."
cat > ecosystem.config.js << 'EOF'
module.exports = {
  apps: [{
    name: 'juicebot-backend',
    script: 'src/server.js',
    instances: 'max',
    exec_mode: 'cluster',
    env: {
      NODE_ENV: 'production',
      PORT: 3000
    },
    error_file: './logs/err.log',
    out_file: './logs/out.log',
    log_file: './logs/combined.log',
    time: true
  }]
};
EOF

# Create logs directory
mkdir -p logs

# Setup Nginx configuration
print_status "Setting up Nginx configuration..."
sudo tee /etc/nginx/sites-available/juicebot << 'EOF'
server {
    listen 80;
    server_name your-domain.com www.your-domain.com;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied expired no-cache no-store private must-revalidate auth;
    gzip_types text/plain text/css text/xml text/javascript application/x-javascript application/xml+rss;

    # Frontend static files
    location / {
        root /var/www/juicebot/frontend/dist;
        try_files $uri $uri/ /index.html;
        
        # Cache static assets
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
    }

    # API proxy
    location /api/ {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }

    # WhatsApp webhook
    location /whatsapp/ {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Health check
    location /health {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

# Enable the site
sudo ln -sf /etc/nginx/sites-available/juicebot /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Test Nginx configuration
sudo nginx -t

# Start services
print_status "Starting services..."
pm2 start ecosystem.config.js
pm2 save
pm2 startup

# Enable Nginx
sudo systemctl enable nginx
sudo systemctl restart nginx

# Setup firewall
print_status "Setting up firewall..."
sudo ufw allow ssh
sudo ufw allow 'Nginx Full'
sudo ufw --force enable

# Setup SSL certificate (optional)
read -p "Do you want to set up SSL certificate with Let's Encrypt? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Enter your domain name: " domain_name
    sudo certbot --nginx -d $domain_name
fi

# Setup automatic backups
print_status "Setting up automatic backups..."
sudo mkdir -p /var/backups/juicebot
sudo chown $USER:$USER /var/backups/juicebot

# Create backup script
cat > /var/backups/juicebot/backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/var/backups/juicebot"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/juicebot_$DATE.sql"

# Database backup
pg_dump juicebot > $BACKUP_FILE

# Compress backup
gzip $BACKUP_FILE

# Keep only last 7 days of backups
find $BACKUP_DIR -name "*.sql.gz" -mtime +7 -delete

echo "Backup completed: $BACKUP_FILE.gz"
EOF

chmod +x /var/backups/juicebot/backup.sh

# Add backup to crontab
(crontab -l 2>/dev/null; echo "0 2 * * * /var/backups/juicebot/backup.sh") | crontab -

print_status "Deployment completed successfully!"
echo
print_status "Next steps:"
echo "1. Edit .env file with your actual credentials"
echo "2. Update Nginx configuration with your domain"
echo "3. Configure WhatsApp Business API webhook"
echo "4. Test the application"
echo
print_status "Useful commands:"
echo "- View logs: pm2 logs"
echo "- Restart app: pm2 restart juicebot-backend"
echo "- Monitor: pm2 monit"
echo "- Backup: /var/backups/juicebot/backup.sh"
echo
print_status "Your application should be running at:"
echo "- Frontend: http://your-domain.com"
echo "- API: http://your-domain.com/api"
echo "- WhatsApp webhook: http://your-domain.com/whatsapp/webhook" 