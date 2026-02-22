#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# deploy.sh — Automated Cloud Run deployment for Arqivon backend
# Usage: ./deploy.sh [--project PROJECT_ID] [--region REGION]
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
PROJECT_ID="${PROJECT_ID:-arqivon-inc}"
REGION="${REGION:-us-central1}"
SERVICE_NAME="arqivon-backend"
SECRET_NAME="GEMINI_API_KEY"
MIN_INSTANCES=1
MAX_INSTANCES=10
MEMORY="512Mi"
CPU=1
TIMEOUT=3600
CONCURRENCY=100

# ── Parse CLI args ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT_ID="$2"; shift 2 ;;
    --region)  REGION="$2";     shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# ── Preflight checks ────────────────────────────────────────────────────────
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Arqivon — Automated Cloud Run Deployment               ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Project:  $PROJECT_ID"
echo "  Region:   $REGION"
echo "  Service:  $SERVICE_NAME"
echo ""

# Check gcloud is installed
if ! command -v gcloud &>/dev/null; then
  echo "❌ gcloud CLI not found. Install: https://cloud.google.com/sdk/docs/install"
  exit 1
fi

# Check we're in the right directory  
if [[ ! -f "backend/Dockerfile" ]]; then
  echo "❌ Run this script from the Arqivon root directory (where backend/ exists)"
  exit 1
fi

# Set project
echo "→ Setting gcloud project to $PROJECT_ID..."
gcloud config set project "$PROJECT_ID" --quiet

# ── Verify Secret exists ────────────────────────────────────────────────────
echo "→ Verifying Secret Manager secret '$SECRET_NAME'..."
if ! gcloud secrets describe "$SECRET_NAME" --project="$PROJECT_ID" &>/dev/null; then
  echo "❌ Secret '$SECRET_NAME' not found in project $PROJECT_ID."
  echo "   Create it: gcloud secrets create $SECRET_NAME --replication-policy=automatic"
  echo "   Then add a version: echo -n 'YOUR_KEY' | gcloud secrets versions add $SECRET_NAME --data-file=-"
  exit 1
fi
echo "  ✓ Secret '$SECRET_NAME' exists"

# ── Deploy to Cloud Run ─────────────────────────────────────────────────────
echo ""
echo "→ Building & deploying to Cloud Run..."
echo "  (this may take 2-5 minutes)"
echo ""

cd backend

gcloud run deploy "$SERVICE_NAME" \
  --source . \
  --region "$REGION" \
  --allow-unauthenticated \
  --set-secrets="${SECRET_NAME}=${SECRET_NAME}:latest" \
  --max-instances="$MAX_INSTANCES" \
  --min-instances="$MIN_INSTANCES" \
  --no-cpu-throttling \
  --timeout="$TIMEOUT" \
  --concurrency="$CONCURRENCY" \
  --memory="$MEMORY" \
  --cpu="$CPU" \
  --project="$PROJECT_ID" \
  --quiet

cd ..

# ── Get service URL ─────────────────────────────────────────────────────────
SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --format="value(status.url)")

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  ✅ Deployment successful!                               ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Service URL: $SERVICE_URL"
echo "  Health:      $SERVICE_URL/health"
echo ""
echo "  WebSocket:   wss://$(echo "$SERVICE_URL" | sed 's|https://||')/ws"
echo ""

# ── Verify health endpoint ──────────────────────────────────────────────────
echo "→ Checking health endpoint..."
HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "$SERVICE_URL/health" || echo "000")
if [[ "$HEALTH" == "200" ]]; then
  echo "  ✓ Health check passed (HTTP 200)"
else
  echo "  ⚠ Health check returned HTTP $HEALTH (service may still be starting)"
fi

echo ""
echo "Done! Update app/lib/config/constants.dart with the service URL if changed."
