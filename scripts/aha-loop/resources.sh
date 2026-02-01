#!/bin/bash
# Aha Loop Resources - System Resource Access Utilities
# Provides helper functions for AI to access host system resources
#
# Usage:
#   source scripts/aha-loop/resources.sh
#   docker_run "nginx:latest" "my-container"
#   docker_exec "my-container" "ls -la"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"

# Load configuration
load_resource_config() {
  if [ -f "$CONFIG_FILE" ]; then
    DOCKER_ENABLED=$(jq -r '.resources.docker.enabled // true' "$CONFIG_FILE")
    NETWORK_ENABLED=$(jq -r '.resources.network.enabled // true' "$CONFIG_FILE")
    UNLIMITED_COMPUTE=$(jq -r '.resources.unlimitedCompute // true' "$CONFIG_FILE")
  else
    DOCKER_ENABLED=true
    NETWORK_ENABLED=true
    UNLIMITED_COMPUTE=true
  fi
}

load_resource_config

#######################################
# DOCKER UTILITIES
#######################################

# Check if Docker is available
docker_available() {
  if [ "$DOCKER_ENABLED" != "true" ]; then
    echo "Docker is disabled in config"
    return 1
  fi
  
  if ! command -v docker &> /dev/null; then
    echo "Docker is not installed"
    return 1
  fi
  
  if ! docker info &> /dev/null; then
    echo "Docker daemon is not running"
    return 1
  fi
  
  return 0
}

# Run a Docker container
# Usage: docker_run IMAGE [NAME] [OPTIONS...]
docker_run() {
  if ! docker_available; then
    return 1
  fi
  
  local image="$1"
  local name="${2:-}"
  shift 2 || shift 1
  local options="$@"
  
  if [ -n "$name" ]; then
    echo "Starting container '$name' from image '$image'..."
    docker run -d --name "$name" $options "$image"
  else
    echo "Starting container from image '$image'..."
    docker run -d $options "$image"
  fi
}

# Execute command in running container
# Usage: docker_exec CONTAINER COMMAND...
docker_exec() {
  if ! docker_available; then
    return 1
  fi
  
  local container="$1"
  shift
  local command="$@"
  
  echo "Executing in '$container': $command"
  docker exec "$container" $command
}

# Stop and remove container
# Usage: docker_cleanup CONTAINER
docker_cleanup() {
  if ! docker_available; then
    return 1
  fi
  
  local container="$1"
  
  echo "Stopping container '$container'..."
  docker stop "$container" 2>/dev/null || true
  docker rm "$container" 2>/dev/null || true
}

# List running containers
docker_list() {
  if ! docker_available; then
    return 1
  fi
  
  docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
}

# Build Docker image
# Usage: docker_build TAG [DOCKERFILE] [CONTEXT]
docker_build() {
  if ! docker_available; then
    return 1
  fi
  
  local tag="$1"
  local dockerfile="${2:-Dockerfile}"
  local context="${3:-.}"
  
  echo "Building image '$tag' from '$dockerfile'..."
  docker build -t "$tag" -f "$dockerfile" "$context"
}

#######################################
# PROCESS UTILITIES
#######################################

# Run command in background
# Usage: background_run COMMAND... 
# Returns: PID of background process
background_run() {
  local command="$@"
  
  echo "Starting background process: $command"
  nohup $command > /tmp/bg-$$.log 2>&1 &
  local pid=$!
  echo "Started with PID: $pid"
  echo $pid
}

# Check if process is running
# Usage: process_running PID
process_running() {
  local pid="$1"
  kill -0 "$pid" 2>/dev/null
}

# Kill process
# Usage: process_kill PID
process_kill() {
  local pid="$1"
  
  if process_running "$pid"; then
    echo "Killing process $pid..."
    kill "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null
  else
    echo "Process $pid not running"
  fi
}

#######################################
# NETWORK UTILITIES
#######################################

# Check if URL is reachable
# Usage: network_check URL
network_check() {
  if [ "$NETWORK_ENABLED" != "true" ]; then
    echo "Network is disabled in config"
    return 1
  fi
  
  local url="$1"
  
  if curl -s --head --connect-timeout 5 "$url" > /dev/null; then
    echo "URL reachable: $url"
    return 0
  else
    echo "URL not reachable: $url"
    return 1
  fi
}

# Download file
# Usage: network_download URL [OUTPUT]
network_download() {
  if [ "$NETWORK_ENABLED" != "true" ]; then
    echo "Network is disabled in config"
    return 1
  fi
  
  local url="$1"
  local output="${2:-}"
  
  if [ -n "$output" ]; then
    echo "Downloading $url to $output..."
    curl -L -o "$output" "$url"
  else
    echo "Downloading $url..."
    curl -L -O "$url"
  fi
}

# Make HTTP request
# Usage: network_request METHOD URL [DATA]
network_request() {
  if [ "$NETWORK_ENABLED" != "true" ]; then
    echo "Network is disabled in config"
    return 1
  fi
  
  local method="$1"
  local url="$2"
  local data="${3:-}"
  
  if [ -n "$data" ]; then
    curl -X "$method" -H "Content-Type: application/json" -d "$data" "$url"
  else
    curl -X "$method" "$url"
  fi
}

#######################################
# FILE SYSTEM UTILITIES
#######################################

# Create temporary directory for exploration
# Usage: create_temp_workspace [NAME]
# Returns: Path to temp directory
create_temp_workspace() {
  local name="${1:-explore}"
  local temp_dir=$(mktemp -d -t "aha-loop-${name}-XXXXXX")
  echo "Created temp workspace: $temp_dir"
  echo "$temp_dir"
}

# Clean up temporary workspace
# Usage: cleanup_temp_workspace PATH
cleanup_temp_workspace() {
  local path="$1"
  
  if [[ "$path" == /tmp/aha-loop-* ]]; then
    echo "Cleaning up: $path"
    rm -rf "$path"
  else
    echo "Refusing to delete non-temp path: $path"
    return 1
  fi
}

# Get available disk space (GB)
disk_space() {
  local path="${1:-$PROJECT_ROOT}"
  df -BG "$path" | awk 'NR==2 {print $4}' | tr -d 'G'
}

# Get available memory (MB)
memory_available() {
  free -m | awk 'NR==2 {print $7}'
}

#######################################
# RESOURCE SUMMARY
#######################################

# Print resource summary
resource_summary() {
  echo "========================================"
  echo "  Resource Summary"
  echo "========================================"
  echo ""
  echo "Configuration:"
  echo "  Docker enabled: $DOCKER_ENABLED"
  echo "  Network enabled: $NETWORK_ENABLED"
  echo "  Unlimited compute: $UNLIMITED_COMPUTE"
  echo ""
  echo "System:"
  echo "  Available disk: $(disk_space)GB"
  echo "  Available memory: $(memory_available)MB"
  echo "  CPU cores: $(nproc)"
  echo ""
  
  if docker_available 2>/dev/null; then
    echo "Docker:"
    echo "  Status: Available"
    echo "  Running containers: $(docker ps -q | wc -l)"
  else
    echo "Docker: Not available"
  fi
  echo ""
  echo "========================================"
}

# If script is run directly (not sourced), show summary
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  resource_summary
fi
