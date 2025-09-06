#!/bin/bash
set -e

echo "------------------------------"
echo "Git Setup"
echo "------------------------------"
git config --global user.name "Auto Bot"
git config --global user.email "auto@bot.com"
mkdir -p links
git fetch origin main
git reset --hard origin/main

echo "------------------------------"
echo "Ensure Playit agent exists"
echo "------------------------------"
AGENT_BIN="./playit-linux-amd64"
if [ ! -f "$AGENT_BIN" ]; then
  wget -q https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-amd64 -O "$AGENT_BIN"
  chmod +x "$AGENT_BIN"
fi

echo "------------------------------"
echo "Restore Playit config if exists"
echo "------------------------------"
mkdir -p ~/.config/playit_gg
aws --endpoint-url=https://s3.filebase.com s3 cp s3://$FILEBASE_BUCKET/playit.toml ~/.config/playit_gg/playit.toml || echo "[Playit] No saved config yet"

echo "------------------------------"
echo "Restore previous claim link"
echo "------------------------------"
if [ ! -f links/playit_claim.txt ]; then
  aws --endpoint-url=https://s3.filebase.com s3 cp s3://$FILEBASE_BUCKET/playit_claim.txt links/playit_claim.txt || echo "[Playit] No saved claim link yet"
fi

echo "------------------------------"
echo "Start Playit agent"
echo "------------------------------"
pkill -f playit-linux-amd64 || true
nohup $AGENT_BIN > playit.log 2>&1 &
sleep 15

echo "------------------------------"
echo "Background loop: Refresh tmate SSH every 15 minutes"
echo "------------------------------"
(
while true; do
  pkill tmate || true
  rm -f /tmp/tmate.sock
  tmate -S /tmp/tmate.sock new-session -d
  tmate -S /tmp/tmate.sock wait tmate-ready 30 || true

  TMATE_SSH=""
  while [ -z "$TMATE_SSH" ]; do
    sleep 2
    TMATE_SSH=$(tmate -S /tmp/tmate.sock display -p '#{tmate_ssh}' || true)
  done

  echo "$TMATE_SSH" > links/ssh.txt
  echo "[INFO] Refreshed SSH: $TMATE_SSH"

  git fetch origin main
  git reset --hard origin/main
  git add links/ssh.txt
  git commit -m "Updated SSH link $(date -u)" || true
  git push origin main || true

  sleep 900  # 15 minutes
done
) &

echo "------------------------------"
echo "Full panel backup every 30 minutes"
echo "------------------------------"
(
mkdir -p panel
while true; do
  echo "[Backup] Starting panel backup at $(date -u)"

  # Add dummy if empty
  if [ -z "$(ls -A panel)" ]; then
    echo "Dummy file" > panel/dummy.txt
  fi

  BACKUP_NAME="panelbackup.zip"
  zip -r "$BACKUP_NAME" panel >/dev/null 2>&1

  echo "[Backup] Uploading $BACKUP_NAME to Filebase..."
  n=0
  until [ $n -ge 3 ]; do
    aws --endpoint-url=https://s3.filebase.com s3 cp "$BACKUP_NAME" s3://$FILEBASE_BUCKET/$BACKUP_NAME && break
    echo "[Backup] Upload attempt $((n+1)) failed, retrying..."
    sleep 30
    n=$((n+1))
  done
  echo "[Backup] Panel backup done ✅"

  echo "[INFO] Sleeping 30 minutes..."
  sleep 1800
done
) &

echo "[INFO] Panel VPS setup complete. Playit + 30min backup + tmate loop running in background."

# Keep script running
tail -f /dev/null
