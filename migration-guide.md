# JuiceBot Migration Guide: Convex to Self-Hosted VPS

## Overview

This guide provides a complete step-by-step approach to migrate your WhatsApp Juice Company Chatbot from Convex to a self-hosted VPS while maintaining full functionality.

## Migration Assessment

### Should You Migrate?

**Pros of Migration:**
- ✅ **Cost Control**: No per-request pricing, predictable monthly costs
- ✅ **Data Ownership**: Complete control over your data and infrastructure
- ✅ **Customization**: Full control over server configuration and optimization
- ✅ **Privacy**: Data stays on your servers, no third-party access
- ✅ **Scalability**: Can optimize for your specific needs and traffic patterns

**Cons of Migration:**
- ❌ **Complexity**: Significant development and infrastructure work
- ❌ **Maintenance**: You're responsible for server management, updates, security
- ❌ **Development Time**: 2-4 weeks of development and testing work
- ❌ **Ongoing Costs**: Server hosting, monitoring, backup storage
- ❌ **Technical Debt**: Need to maintain infrastructure code

**Recommendation**: Migrate if you have:
- Technical expertise or budget for DevOps
- Need for data sovereignty
- High traffic volume (cost savings)
- Custom requirements not supported by Convex

## Pre-Migration Checklist

### 1. Data Export
```bash
# Export your current Convex data
npx convex export --format json --output convex-data.json
```

### 2. Environment Variables
Document all your current environment variables:
- WhatsApp API credentials
- Any third-party integrations
- Custom configurations

### 3. Domain and SSL
- Purchase/configure your domain
- Plan for SSL certificate setup

## Phase 1: Infrastructure Setup (Week 1)

### 1.1 VPS Selection and Setup

**Recommended VPS Specs:**
- **CPU**: 2-4 cores
- **RAM**: 4-8GB
- **Storage**: 50-100GB SSD
- **OS**: Ubuntu 22.04 LTS
- **Provider**: DigitalOcean, Linode, Vultr, or AWS EC2

**VPS Setup Commands:**
```bash
# Connect to your VPS
ssh root@your-server-ip

# Create a non-root user
adduser juicebot
usermod -aG sudo juicebot
su - juicebot

# Update system
sudo apt update && sudo apt upgrade -y
```

### 1.2 Install Required Software

```bash
# Install Node.js 20.x
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install PM2 for process management
npm install -g pm2

# Install Nginx
sudo apt install nginx -y

# Install PostgreSQL
sudo apt install postgresql postgresql-contrib -y

# Install SSL certificate tools
sudo apt install certbot python3-certbot-nginx -y
```

### 1.3 Database Setup

```bash
# Access PostgreSQL
sudo -u postgres psql

# Create database and user
CREATE DATABASE juicebot;
CREATE USER juicebot_user WITH PASSWORD 'your_secure_password';
GRANT ALL PRIVILEGES ON DATABASE juicebot TO juicebot_user;
\q

# Test connection
psql -h localhost -U juicebot_user -d juicebot
```

## Phase 2: Backend Migration (Week 2-3)

### 2.1 Project Structure

```
/var/www/juicebot/
├── backend/
│   ├── src/
│   │   ├── routes/
│   │   ├── services/
│   │   ├── middleware/
│   │   ├── database/
│   │   └── utils/
│   ├── package.json
│   └── ecosystem.config.js
├── frontend/
│   ├── src/
│   ├── dist/
│   └── package.json
├── .env
└── deploy.sh
```

### 2.2 Database Schema Migration

The new schema normalizes the Convex document structure:

**Key Changes:**
- Arrays become separate tables (order_items, chat_session_items)
- Proper foreign key relationships
- Indexes for performance
- Triggers for automatic timestamps

**Migration Steps:**
```bash
# Run the schema
psql -h localhost -U juicebot_user -d juicebot -f backend/src/database/schema.sql

# Import existing data (if any)
psql -h localhost -U juicebot_user -d juicebot -c "\copy categories FROM 'categories.csv' CSV HEADER"
```

### 2.3 API Endpoints Migration

**Convex Functions → Express Routes:**

| Convex Function | Express Route | Method |
|----------------|---------------|---------|
| `api.products.getActiveCategories` | `/api/products/categories` | GET |
| `api.orders.createOrder` | `/api/orders` | POST |
| `api.whatsapp.processWhatsAppMessage` | `/whatsapp/webhook` | POST |

**Authentication Migration:**
- Replace Convex Auth with JWT-based authentication
- Implement password hashing with bcrypt
- Add middleware for route protection

### 2.4 WhatsApp Integration

**Webhook Configuration:**
```javascript
// Replace Convex HTTP actions with Express routes
app.post('/whatsapp/webhook', async (req, res) => {
  // Process WhatsApp message
  const result = await processWhatsAppMessage(req.body);
  
  // Send response back to WhatsApp
  await sendWhatsAppResponse(result);
  
  res.status(200).send('OK');
});
```

**Key Differences:**
- Direct database queries instead of Convex context
- Manual transaction management
- Explicit error handling

## Phase 3: Frontend Migration (Week 3-4)

### 3.1 API Client Migration

**Replace Convex Client:**
```javascript
// Old (Convex)
import { useQuery, useMutation } from "convex/react";
import { api } from "../convex/_generated/api";

const products = useQuery(api.products.getAllProducts);

// New (REST API)
import { useState, useEffect } from "react";

const [products, setProducts] = useState([]);
useEffect(() => {
  fetch('/api/products')
    .then(res => res.json())
    .then(data => setProducts(data));
}, []);
```

### 3.2 Authentication Migration

**Replace Convex Auth:**
```javascript
// Old (Convex Auth)
import { useAuthActions } from "@convex-dev/auth/react";

// New (JWT)
import { login, logout } from "../services/auth";

const handleLogin = async (credentials) => {
  const token = await login(credentials);
  localStorage.setItem('token', token);
};
```

### 3.3 Real-time Updates

**Replace Convex Real-time:**
```javascript
// Old (Convex real-time)
const orders = useQuery(api.orders.getAllOrders);

// New (Polling or WebSocket)
const [orders, setOrders] = useState([]);

useEffect(() => {
  const interval = setInterval(() => {
    fetchOrders().then(setOrders);
  }, 5000);
  
  return () => clearInterval(interval);
}, []);
```

## Phase 4: Deployment and Testing (Week 4)

### 4.1 Production Deployment

```bash
# Run deployment script
chmod +x deploy.sh
./deploy.sh

# Or manual deployment
cd /var/www/juicebot
npm install
npm run build
pm2 start ecosystem.config.js
```

### 4.2 SSL Certificate Setup

```bash
# Get SSL certificate
sudo certbot --nginx -d your-domain.com

# Auto-renewal
sudo crontab -e
# Add: 0 12 * * * /usr/bin/certbot renew --quiet
```

### 4.3 WhatsApp Webhook Configuration

1. **Update WhatsApp Business API settings:**
   - Webhook URL: `https://your-domain.com/whatsapp/webhook`
   - Verify Token: Your configured token

2. **Test webhook:**
   ```bash
   curl -X POST https://your-domain.com/whatsapp/webhook \
     -H "Content-Type: application/json" \
     -d '{"test": "message"}'
   ```

### 4.4 Monitoring and Logging

```bash
# PM2 monitoring
pm2 monit
pm2 logs

# Nginx logs
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log

# Application logs
tail -f /var/www/juicebot/logs/combined.log
```

## Phase 5: Data Migration (If Applicable)

### 5.1 Export Convex Data

```bash
# Export all data
npx convex export --format json --output convex-data.json
```

### 5.2 Transform and Import

```javascript
// Transform script
const convexData = require('./convex-data.json');

// Transform categories
const categories = convexData.categories.map(cat => ({
  name: cat.name,
  description: cat.description,
  is_active: cat.isActive
}));

// Transform products
const products = convexData.products.map(prod => ({
  name: prod.name,
  description: prod.description,
  price: prod.price,
  category_id: prod.categoryId,
  ingredients: prod.ingredients
}));

// Import to PostgreSQL
// Use COPY commands or INSERT statements
```

## Testing Checklist

### Functional Testing
- [ ] User authentication (login/logout)
- [ ] Product management (CRUD operations)
- [ ] Order management
- [ ] WhatsApp bot responses
- [ ] Admin dashboard functionality

### Performance Testing
- [ ] Database query performance
- [ ] API response times
- [ ] Concurrent user handling
- [ ] WhatsApp webhook processing

### Security Testing
- [ ] Authentication and authorization
- [ ] Input validation
- [ ] SQL injection prevention
- [ ] XSS protection
- [ ] Rate limiting

### Integration Testing
- [ ] WhatsApp Business API integration
- [ ] Database connectivity
- [ ] SSL certificate validation
- [ ] Backup and restore procedures

## Maintenance and Monitoring

### Daily Monitoring
```bash
# Check application status
pm2 status
pm2 logs --lines 100

# Check database
psql -h localhost -U juicebot_user -d juicebot -c "SELECT count(*) FROM orders;"

# Check disk space
df -h
```

### Weekly Maintenance
```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Restart services
pm2 restart all
sudo systemctl restart nginx

# Check SSL certificate
sudo certbot certificates
```

### Monthly Tasks
- Review and rotate logs
- Update application dependencies
- Review security patches
- Test backup and restore procedures

## Troubleshooting Common Issues

### Database Connection Issues
```bash
# Check PostgreSQL status
sudo systemctl status postgresql

# Check connection
psql -h localhost -U juicebot_user -d juicebot

# Check logs
sudo tail -f /var/log/postgresql/postgresql-*.log
```

### WhatsApp Webhook Issues
```bash
# Check webhook logs
tail -f /var/www/juicebot/logs/combined.log | grep whatsapp

# Test webhook manually
curl -X POST https://your-domain.com/whatsapp/webhook \
  -H "Content-Type: application/json" \
  -d '{"object":"whatsapp_business_account","entry":[{"changes":[{"value":{"messages":[{"from":"1234567890","text":{"body":"test"}}]}}]}]}'
```

### Performance Issues
```bash
# Check system resources
htop
free -h
df -h

# Check database performance
psql -h localhost -U juicebot_user -d juicebot -c "SELECT * FROM pg_stat_activity;"
```

## Cost Comparison

### Convex Pricing (Estimated)
- **Free Tier**: 1M function calls/month
- **Paid Tier**: $0.50 per 1M function calls
- **Estimated Monthly Cost**: $50-200 (depending on usage)

### VPS Pricing (Estimated)
- **VPS Hosting**: $20-50/month
- **Domain**: $10-15/year
- **SSL Certificate**: Free (Let's Encrypt)
- **Backup Storage**: $5-10/month
- **Total Monthly Cost**: $25-60

**Break-even**: 2-6 months depending on usage

## Conclusion

This migration provides:
- **Complete control** over your infrastructure
- **Cost savings** for high-traffic applications
- **Data sovereignty** and privacy
- **Customization** capabilities

The migration requires significant upfront work but results in a more robust, scalable, and cost-effective solution for your WhatsApp juice company chatbot.

## Support and Resources

- **Documentation**: [Express.js](https://expressjs.com/), [PostgreSQL](https://www.postgresql.org/docs/)
- **Community**: Stack Overflow, GitHub discussions
- **Monitoring**: PM2, Nginx, PostgreSQL monitoring tools
- **Backup**: Automated daily backups with retention policies 