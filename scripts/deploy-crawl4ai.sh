#!/bin/bash
# Crawl4AI deployment script - free, open-source web scraper
# No API key required for basic scraping

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# Check prerequisites
for cmd in python3 pip curl; do
    if ! command -v "$cmd" &> /dev/null; then
        log_error "$cmd not found"
        exit 1
    fi
done

log_info "Installing Crawl4AI..."

# Create virtual environment
CRAWL4AI_DIR="/opt/crawl4ai"
mkdir -p "$CRAWL4AI_DIR"
cd "$CRAWL4AI_DIR"

# Create venv if not exists
if [[ ! -d "$CRAWL4AI_DIR/venv" ]]; then
    log_info "Creating Python virtual environment..."
    python3 -m venv venv
fi

# Activate venv
source "$CRAWL4AI_DIR/venv/bin/activate"

# Upgrade pip
log_info "Upgrading pip..."
pip install --upgrade pip 2>/dev/null || true

# Install crawl4ai
log_info "Installing crawl4ai..."
pip install crawl4ai 2>&1 | tail -5

# Verify installation
if ! python -c "import crawl4ai" 2>/dev/null; then
    log_error "Crawl4AI installation failed"
    exit 1
fi

# Get version
CRAWL4AI_VERSION=$(python -c "import crawl4ai; print(crawl4ai.__version__)" 2>/dev/null || echo "unknown")
log_info "Crawl4AI installed: $CRAWL4AI_VERSION"

# Create API server script
cat > "$CRAWL4AI_DIR/api-server.py" << 'EOF'
#!/usr/bin/env python3
"""
Simple REST API server for Crawl4AI
Provides /scrape endpoint that returns markdown
"""

import asyncio
import json
import argparse
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
from crawl4ai import AsyncWebCrawler

class CrawlHandler(BaseHTTPRequestHandler):

    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"status": "ok", "service": "crawl4ai"}')
        elif self.path.startswith('/scrape'):
            # Parse URL parameter
            parsed = urlparse(self.path)
            params = parse_qs(parsed.query)
            url = params.get('url', [None])[0]

            if not url:
                self.send_response(400)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(b'{"error": "url parameter required"}')
                return

            # Run async crawl - create fresh event loop for each request
            try:
                result = self.run_crawl(url)
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps(result).encode())
            except Exception as e:
                self.send_response(500)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode())
        else:
            self.send_response(404)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"error": "not found"}')

    def run_crawl(self, url):
        """Run crawl in a fresh event loop (HTTPServer is sync, not async)"""
        async def crawl():
            async with AsyncWebCrawler() as crawler:
                result = await crawler.arun(url=url)
                return {
                    "success": result.success,
                    "url": url,
                    "markdown": result.markdown[:5000] if result.success and result.markdown else None,
                    "html": result.html[:5000] if result.success and result.html else None,
                    "error": str(result.error) if hasattr(result, 'error') and result.error else None
                }
        # Create new event loop for this request (HTTPServer is sync)
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        try:
            return loop.run_until_complete(crawl())
        finally:
            loop.close()

    def log_message(self, format, *args):
        print(f"[API] {format % args}")

def run_server(port: int):
    """Run sync HTTP server"""
    server = HTTPServer(('0.0.0.0', port), CrawlHandler)
    print(f"Crawl4AI API server running on port {port}")
    print(f"Endpoints:")
    print(f"  GET /health - Health check")
    print(f"  GET /scrape?url=<url> - Scrape URL to markdown")
    server.serve_forever()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Crawl4AI API Server')
    parser.add_argument('--port', type=int, default=8002, help='Port to listen on')
    args = parser.parse_args()
    run_server(args.port)
EOF

chmod +x "$CRAWL4AI_DIR/api-server.py"

# Create systemd service
cat > /etc/systemd/system/crawl4ai.service << EOF
[Unit]
Description=Crawl4AI Web Scraper API
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$CRAWL4AI_DIR
Environment="PATH=$CRAWL4AI_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=$CRAWL4AI_DIR/venv/bin/python $CRAWL4AI_DIR/api-server.py --port 8002
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start service
log_info "Starting Crawl4AI service..."
systemctl daemon-reload
systemctl enable crawl4ai.service
systemctl restart crawl4ai.service

# Wait for startup
sleep 3

# Check health
if curl -s http://localhost:8002/health >/dev/null 2>&1; then
    log_info "Crawl4AI deployed successfully!"
    SERVER_IP=$(hostname -I | awk '{print $1}')
    echo ""
    echo "========================================="
    echo "  Crawl4AI Self-Hosted Web Scraper"
    echo "========================================="
    echo ""
    echo "API:      http://$SERVER_IP:8002"
    echo ""
    echo "Endpoints:"
    echo "  Health:  curl http://localhost:8002/health"
    echo "  Scrape:  curl 'http://localhost:8002/scrape?url=https://example.com'"
    echo ""
    echo "Example usage in Python:"
    echo "  import asyncio"
    echo "  from crawl4ai import AsyncWebCrawler"
    echo "  async def scrape():"
    echo "      async with AsyncWebCrawler() as crawler:"
    echo "          result = await crawler.arun(url='https://example.com')"
    echo "          print(result.markdown)"
    echo "  asyncio.run(scrape())"
    echo ""
else
    log_warn "Crawl4AI may need more time to start..."
    systemctl status crawl4ai.service --no-pager || true
fi