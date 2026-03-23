# RoBot API Server Deployment Guide

## Quick Deploy to Railway (Recommended)

1. **Sign up** at [railway.app](https://railway.app) (GitHub login works)

2. **Create a new project** → Deploy from GitHub repo

3. **Add your code** to GitHub:
   ```bash
   git init
   git add .
   git commit -m "Initial commit"
   git push origin main
   ```

4. **Deploy on Railway**:
   - Railway will auto-detect the Node.js app
   - Deploys with one click
   - Gets a URL like: `https://robot-api.up.railway.app`

5. **Update the plugin**:
   - Open `/home/mord/Documents/RoBot-Dev/RoBot/RoBot.lua`
   - Change line 22:
     ```lua
     local API_BASE_URL = "https://robot-api.up.railway.app/api"
     ```

## Alternative: Render.com

1. **Sign up** at [render.com](https://render.com)

2. **New Web Service** → Connect GitHub repo

3. **Settings**:
   - Build Command: `npm install`
   - Start Command: `node server.js`

4. **Get URL** and update plugin same as above

## Alternative: Fly.io

```bash
# Install flyctl
curl -L https://fly.io/install.sh | sh

# Login
fly auth login

# Launch
fly launch --name robot-api

# Deploy
fly deploy
```

## Important Notes

- **Free tier limits**: Railway/Render have monthly usage limits
- **Sleep mode**: Free tiers sleep after inactivity (~15 min delay on first request)
- **CORS**: Already enabled in `server.js` for Roblox requests
- **Persistent storage**: Templates are read-only JSON files, no database needed

## After Deployment

Test your API is working:
```bash
curl https://your-url.railway.app/api/health
```

Response should be:
```json
{"status":"ok","templatesCount":52}
```

Then distribute the plugin with the updated API URL!
