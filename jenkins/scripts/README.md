# Jenkins Master Setup

Docker Compose configurations for running a Jenkins master server with optional Docker-in-Docker support.

## 📋 Contents

- `docker-compose.yml` - Basic Jenkins master setup
- `docker-compose.dind.yml` - Jenkins with Docker-in-Docker (for building Docker images)
- `plugins.txt` - Pre-installed plugins list
- `backup.sh` - Backup script
- `restore.sh` - Restore script
- `.env.example` - Environment variables template

## 🚀 Quick Start

### 1. Setup Environment

```bash
cd master
cp .env.example .env
# Edit .env with your preferences
```

### 2. Start Jenkins

**Basic setup (recommended):**
```bash
docker compose up -d
```

**With Docker-in-Docker (for building Docker images):**
```bash
docker compose -f docker-compose.dind.yml up -d
```

### 3. Access Jenkins

Open your browser:
```
http://localhost:8080
```

### 4. Initial Setup

1. Get the initial admin password:
   ```bash
   docker exec jenkins-master cat /var/jenkins_home/secrets/initialAdminPassword
   ```

2. Enter the password in the web UI
3. Install suggested plugins (or use custom plugins from `plugins.txt`)
4. Create admin user
5. Configure Jenkins URL

## ⚙️ Configuration

### Environment Variables (.env)

| Variable | Description | Default |
|----------|-------------|---------|
| `JENKINS_VERSION` | Jenkins version (lts/latest) | `lts` |
| `JENKINS_HOME` | Data directory | `./jenkins-home` |
| `HTTP_PORT` | Web UI port | `8080` |
| `AGENT_PORT` | Agent connection port | `50000` |
| `JAVA_OPTS` | JVM options | `-Xmx2g -Xms512m` |
| `TZ` | Timezone | `UTC` |

### Pre-install Plugins

Edit `plugins.txt` to add plugins:
```
git
workflow-aggregator
docker-workflow
blueocean
```

Then mount it in docker-compose.yml:
```yaml
volumes:
  - ./plugins.txt:/usr/share/jenkins/ref/plugins.txt
```

## 📊 Docker-in-Docker Setup

Use `docker-compose.dind.yml` when you need to:
- Build Docker images in pipelines
- Run Docker commands in jobs
- Test containers in CI/CD

**Start with DinD:**
```bash
docker compose -f docker-compose.dind.yml up -d
```

**In your Jenkinsfile:**
```groovy
pipeline {
    agent any
    stages {
        stage('Build') {
            steps {
                sh 'docker build -t myapp:latest .'
                sh 'docker run myapp:latest'
            }
        }
    }
}
```

## 💾 Backup & Restore

### Create Backup

```bash
# Backup (hot, without stopping Jenkins)
./backup.sh

# Backup (cold, stops Jenkins first - recommended for production)
./backup.sh --stop
```

Backups are stored in `./backups/` with timestamp.

### List Backups

```bash
./restore.sh list
```

### Restore from Backup

```bash
# Restore latest backup
./restore.sh latest

# Restore specific backup
./restore.sh backups/jenkins_backup_20240101_120000.tar.gz
```

⚠️ **Warning:** Restore will stop Jenkins and overwrite current data!

## 🔧 Common Operations

### View Logs

```bash
docker logs -f jenkins-master
```

### Restart Jenkins

```bash
docker compose restart
```

### Stop Jenkins

```bash
docker compose down
```

### Update Jenkins

```bash
docker compose pull
docker compose up -d
```

### Access Jenkins CLI

```bash
# Download CLI
docker exec jenkins-master cat /var/jenkins_home/jenkins-cli.jar > jenkins-cli.jar

# Run command
java -jar jenkins-cli.jar -s http://localhost:8080 -auth admin:password help
```

## 🔐 Security

### Change Admin Password

1. Login to Jenkins web UI
2. Go to: Manage Jenkins → Manage Users
3. Click on admin user → Configure → Change password

### Enable HTTPS (Reverse Proxy)

Use nginx or traefik as reverse proxy:

```nginx
server {
    listen 443 ssl;
    server_name jenkins.example.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Firewall Rules

```bash
# Allow web UI (if using HTTPS, only open 443)
sudo ufw allow 8080/tcp

# Allow agent connections
sudo ufw allow 50000/tcp
```

## 🐛 Troubleshooting

### Jenkins won't start

```bash
# Check logs
docker logs jenkins-master

# Check permissions
ls -la jenkins-home/

# Fix permissions (Linux)
sudo chown -R 1000:1000 jenkins-home/
```

### Port already in use

```bash
# Check what's using the port
sudo lsof -i :8080

# Change port in .env
HTTP_PORT=9090
```

### Out of memory

```bash
# Increase Java heap in .env
JAVA_OPTS=-Xmx4g -Xms1g

# Restart
docker compose restart
```

### Can't connect agents

1. Verify agent port is open:
   ```bash
   telnet localhost 50000
   ```

2. Check Jenkins URL configuration:
   - Manage Jenkins → Configure System → Jenkins URL

3. Use WebSocket protocol (recommended):
   - Already configured in your agent installer

## 📝 Pipeline Example

```groovy
pipeline {
    agent { label 'my-agent' }
    
    environment {
        DOCKER_CREDENTIALS = credentials('docker-hub')
    }
    
    stages {
        stage('Checkout') {
            steps {
                git 'https://github.com/example/repo.git'
            }
        }
        
        stage('Build') {
            steps {
                sh 'make build'
            }
        }
        
        stage('Test') {
            steps {
                sh 'make test'
            }
        }
        
        stage('Deploy') {
            when {
                branch 'main'
            }
            steps {
                sh 'make deploy'
            }
        }
    }
    
    post {
        always {
            junit 'test-results/*.xml'
        }
        success {
            slackSend channel: '#ci', message: "Build ${env.BUILD_NUMBER} succeeded"
        }
        failure {
            slackSend channel: '#ci', message: "Build ${env.BUILD_NUMBER} failed"
        }
    }
}
```

## 🔗 Connecting Agents

Use the agent installer you already have:

```bash
cd ../
./install.sh
# Or on Windows: .\install.ps1
```

Point it to your Jenkins master:
- Jenkins URL: `http://localhost:8080` (or your domain)
- Agent Name: Create node in Jenkins UI first
- Secret: Copy from node configuration page

## 📚 Resources

- [Jenkins Documentation](https://www.jenkins.io/doc/)
- [Jenkins Docker Image](https://github.com/jenkinsci/docker)
- [Jenkins Plugins](https://plugins.jenkins.io/)
- [Pipeline Syntax](https://www.jenkins.io/doc/book/pipeline/syntax/)

## 🎯 Next Steps

1. ✅ Start Jenkins master
2. ✅ Complete initial setup
3. ✅ Install recommended plugins
4. ✅ Create agent nodes in Jenkins UI
5. ✅ Run the agent installer on your machines
6. ✅ Create your first pipeline
7. ✅ Setup backup schedule (cron job)

---

**Need help?** Check the main [README](../README.md) or open an issue!
