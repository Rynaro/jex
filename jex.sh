#!/bin/bash
# jex.sh - Jekyll Docker Execution Script
# Usage: ./jex.sh [command] [args...]

set -o pipefail  # Ensures pipeline failures are properly handled

# ======================================================
# CONFIGURATION
# ======================================================

JEX_VERSION="1.1.0"
JEX_DIR="${HOME}/.jex"
JEX_CONFIG="${JEX_DIR}/config"
JEX_LOG="${JEX_DIR}/jex.log"
DEFAULT_DOCKER_IMAGE="jekyll-site"
DEFAULT_JEKYLL_PORT=4000

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ======================================================
# LOGGING UTILITIES
# ======================================================

# Log message to log file with timestamp
function log() {
  local level="$1"
  shift
  local message="$*"
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  echo -e "[${timestamp}] [${level}] ${message}" >> "${JEX_LOG}"
}

function log_info() {
  log "INFO" "$@"
}

function log_error() {
  log "ERROR" "$@"
}

function log_warn() {
  log "WARN" "$@"
}

# ======================================================
# CORE UTILITIES
# ======================================================

# Create the jex directory structure if it doesn't exist
function ensure_jex_dir() {
  if [ ! -d "${JEX_DIR}" ]; then
    mkdir -p "${JEX_DIR}"
    mkdir -p "${JEX_DIR}/templates"
    touch "${JEX_LOG}"

    # Create default config if it doesn't exist
    if [ ! -f "${JEX_CONFIG}" ]; then
      cat > "${JEX_CONFIG}" << EOF
DOCKER_IMAGE="${DEFAULT_DOCKER_IMAGE}"
JEKYLL_PORT=${DEFAULT_JEKYLL_PORT}
# Default user/group IDs (will be overridden at runtime)
USER_ID=$(id -u)
GROUP_ID=$(id -g)
EOF
    fi

    # Create Dockerfile template
    cat > "${JEX_DIR}/templates/Dockerfile" << 'EOF'
FROM ruby:3.2-slim

# Install dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    nodejs \
    npm \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /site

# Install Jekyll and Bundler
RUN gem install jekyll bundler webrick

# Expose port 4000 for Jekyll server
EXPOSE 4000

# Add volume for site content
VOLUME /site

# Command to run when container starts
# Using webrick since it's no longer bundled with Ruby 3.0+
CMD ["sh", "-c", "if [ ! -f Gemfile ]; then jekyll new . --force; fi && bundle install && bundle exec jekyll serve --host 0.0.0.0 --livereload"]
EOF

    # Create gitignore template
    cat > "${JEX_DIR}/templates/gitignore" << 'EOF'
_site/
.sass-cache/
.jekyll-cache/
.jekyll-metadata
.bundle/
vendor/
.DS_Store
EOF
    log_info "JEX directory structure created at ${JEX_DIR}"
  fi
}

# Function to display command execution
function run_cmd() {
  local cmd="$1"
  local log_only="${2:-false}"

  if [ "$log_only" != "true" ]; then
    echo -e "${YELLOW}> $cmd${NC}"
  fi

  log_info "Executing command: $cmd"

  local output
  if output=$(eval "$cmd" 2>&1); then
    if [ -n "$output" ] && [ "$log_only" != "true" ]; then
      echo "$output"
    fi
    return 0
  else
    local exit_code=$?
    log_error "Command failed with exit code $exit_code: $cmd"
    if [ "$log_only" != "true" ]; then
      echo -e "${RED}Command failed with exit code $exit_code${NC}" >&2
      echo "$output" >&2
    fi
    return $exit_code
  fi
}

# Function to show error message and exit
function error_exit() {
  log_error "$1"
  echo -e "${RED}ERROR: $1${NC}" >&2
  exit 1
}

# Check prerequisites
function check_prerequisites() {
  local missing=false

  if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}ERROR: Docker is not installed or not in PATH${NC}" >&2
    log_error "Docker not found in PATH"
    missing=true
  fi

  if $missing; then
    error_exit "Please install missing prerequisites and try again."
  fi
}

# Function to fix permissions of files
function fix_permissions() {
  local dir=${1:-.}
  local USER_ID=$(id -u)
  local GROUP_ID=$(id -g)

  echo -e "${YELLOW}Fixing file permissions in $dir...${NC}"
  log_info "Fixing file permissions in $dir"

  # Check if we need sudo (if files are owned by root)
  if [ -f "$dir/_config.yml" ] && [ $(stat -c "%u" "$dir/_config.yml") -ne $USER_ID ]; then
    # Try with sudo
    if command -v sudo >/dev/null 2>&1; then
      run_cmd "sudo chown -R $USER_ID:$GROUP_ID $dir"
    else
      log_warn "Some files owned by root, but sudo not available"
      echo -e "${RED}Warning: Some files may be owned by root. Unable to use sudo to fix.${NC}"
      echo -e "${YELLOW}You may need to manually run: chown -R $(id -un):$(id -gn) $dir${NC}"
    fi
  else
    # No need for sudo
    run_cmd "chown -R $USER_ID:$GROUP_ID $dir"
  fi
}

# Function to fix bundler permissions
function fix_bundler_permissions() {
  local dir=${1:-.}
  local USER_ID=$(id -u)
  local GROUP_ID=$(id -g)

  echo -e "${YELLOW}Fixing bundler permissions in $dir...${NC}"
  log_info "Fixing bundler permissions in $dir"

  # Create .bundle directory if it doesn't exist
  mkdir -p "$dir/.bundle"

  # Set correct permissions for .bundle directory
  run_cmd "chown -R $USER_ID:$GROUP_ID $dir/.bundle"
  run_cmd "chmod -R 755 $dir/.bundle"
}

# Load config and set defaults if values are missing
function load_config() {
  # Set defaults
  DOCKER_IMAGE="${DEFAULT_DOCKER_IMAGE}"
  JEKYLL_PORT="${DEFAULT_JEKYLL_PORT}"
  USER_ID=$(id -u)
  GROUP_ID=$(id -g)

  # Load from config if it exists
  if [ -f "${JEX_CONFIG}" ]; then
    log_info "Loading configuration from ${JEX_CONFIG}"
    source "${JEX_CONFIG}"
  else
    log_warn "Config file not found, using defaults"
  fi
}

# Validate input parameters
function validate_param() {
  local param="$1"
  local param_name="$2"
  local error_msg="$3"

  if [ -z "$param" ]; then
    error_exit "${error_msg:-"Missing required parameter: $param_name"}"
  fi
}

# ======================================================
# IMAGE DOMAIN
# ======================================================

# Build the Docker image
function image_build() {
  local force="${1:-false}"

  echo -e "${BLUE}Building Jekyll Docker image...${NC}"
  log_info "Building Jekyll Docker image: $DOCKER_IMAGE"

  # Check if image already exists
  if [ "$force" != "true" ] && docker image inspect "$DOCKER_IMAGE" >/dev/null 2>&1; then
    echo -e "${YELLOW}Image $DOCKER_IMAGE already exists. Use 'build-image --force' to rebuild.${NC}"
    return 0
  fi

  # Check for Dockerfile
  if [ ! -f "Dockerfile" ]; then
    echo -e "${YELLOW}Dockerfile not found. Using template...${NC}"
    cp "${JEX_DIR}/templates/Dockerfile" Dockerfile
  fi

  run_cmd "docker build -t $DOCKER_IMAGE ."

  if [ $? -eq 0 ]; then
    echo -e "${GREEN}Image built successfully!${NC}"
  else
    error_exit "Failed to build Docker image."
  fi
}

# Remove Docker image 
function image_remove() {
  echo -e "${RED}Warning: This will remove the Jekyll Docker image.${NC}"
  echo -e "${YELLOW}Do you want to continue? (y/n)${NC}"
  read -r answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    log_info "Removing Docker image: $DOCKER_IMAGE"
    run_cmd "docker rmi $DOCKER_IMAGE"
    echo -e "${GREEN}Image removed.${NC}"
  else
    log_info "Image removal canceled by user"
    echo -e "${BLUE}Operation canceled.${NC}"
  fi
}

# ======================================================
# CONTAINER DOMAIN
# ======================================================

# Check if container exists
function container_exists() {
  local name="$1"
  docker ps -a --format '{{.Names}}' | grep -q "^${name}$"
  return $?
}

# Start Jekyll server with live reload
function container_serve() {
  echo -e "${BLUE}Starting Jekyll server with live reload...${NC}"
  log_info "Starting Jekyll server with live reload on port ${JEKYLL_PORT}"

  local USER_ID=$(id -u)
  local GROUP_ID=$(id -g)

  # Check if container already exists
  if container_exists "jekyll-container"; then
    echo -e "${YELLOW}Container 'jekyll-container' already exists. Stopping it first...${NC}"
    container_stop
  fi

  # Check if port is already in use
  if lsof -Pi :${JEKYLL_PORT} -sTCP:LISTEN -t >/dev/null ; then
    error_exit "Port ${JEKYLL_PORT} is already in use. Please change the port in ${JEX_CONFIG} or stop the service using this port."
  fi

  run_cmd "docker run --rm -v $(pwd):/site -u $USER_ID:$GROUP_ID -p ${JEKYLL_PORT}:4000 $DOCKER_IMAGE"

  if [ $? -ne 0 ]; then
    error_exit "Failed to start Jekyll server."
  fi
}

# Run Jekyll server in background
function container_serve_detached() {
  echo -e "${BLUE}Starting Jekyll server in detached mode...${NC}"
  log_info "Starting Jekyll server in detached mode on port ${JEKYLL_PORT}"

  local USER_ID=$(id -u)
  local GROUP_ID=$(id -g)

  # Check if container already exists
  if container_exists "jekyll-container"; then
    echo -e "${YELLOW}Container 'jekyll-container' already exists. Stopping it first...${NC}"
    container_stop
  fi

  # Check if port is already in use
  if lsof -Pi :${JEKYLL_PORT} -sTCP:LISTEN -t >/dev/null ; then
    error_exit "Port ${JEKYLL_PORT} is already in use. Please change the port in ${JEX_CONFIG} or stop the service using this port."
  fi

  run_cmd "docker run -d --name jekyll-container -v $(pwd):/site -u $USER_ID:$GROUP_ID -p ${JEKYLL_PORT}:4000 $DOCKER_IMAGE"

  if [ $? -eq 0 ]; then
    echo -e "${GREEN}Server running at http://localhost:${JEKYLL_PORT}${NC}"
    echo -e "${YELLOW}To stop server: ./jex.sh stop${NC}"
  else
    error_exit "Failed to start Jekyll server in detached mode."
  fi
}

# Stop detached Jekyll server
function container_stop() {
  echo -e "${BLUE}Stopping Jekyll server...${NC}"
  log_info "Stopping Jekyll server"

  if ! container_exists "jekyll-container"; then
    echo -e "${YELLOW}No running Jekyll container found.${NC}"
    return 0
  fi

  run_cmd "docker stop jekyll-container && docker rm jekyll-container"

  if [ $? -eq 0 ]; then
    echo -e "${GREEN}Server stopped successfully.${NC}"
  else
    error_exit "Failed to stop Jekyll server."
  fi
}

# Run a command inside the Jekyll container
function container_exec() {
  validate_param "$1" "command" "Please provide a command to execute"

  # Get current user and group IDs
  local USER_ID=$(id -u)
  local GROUP_ID=$(id -g)

  # Ensure bundler permissions are correct before executing command
  fix_bundler_permissions "$(pwd)"

  echo -e "${BLUE}Executing command in Jekyll container...${NC}"
  log_info "Executing command in Jekyll container: $1"

  run_cmd "docker run --rm -v $(pwd):/site -u $USER_ID:$GROUP_ID $DOCKER_IMAGE sh -c \"$1\""

  if [ $? -ne 0 ]; then
    error_exit "Command execution failed."
  fi
}

# Clean up all Jekyll Docker containers
function container_clean() {
  echo -e "${RED}Warning: This will remove all Jekyll containers.${NC}"
  echo -e "${YELLOW}Do you want to continue? (y/n)${NC}"
  read -r answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    log_info "Cleaning up Jekyll containers"
    run_cmd "docker stop jekyll-container 2>/dev/null || true"
    run_cmd "docker rm jekyll-container 2>/dev/null || true"
    echo -e "${GREEN}Containers cleaned up.${NC}"
  else
    log_info "Container cleanup canceled by user"
    echo -e "${BLUE}Clean up canceled.${NC}"
  fi
}

# ======================================================
# PROJECT DOMAIN
# ======================================================

# Initialize a new Jekyll project
function project_init() {
  echo -e "${BLUE}Initializing new Jekyll project...${NC}"
  log_info "Initializing new Jekyll project in $(pwd)"

  # Create Dockerfile if it doesn't exist
  if [ ! -f "Dockerfile" ]; then
    echo -e "${YELLOW}Creating Dockerfile...${NC}"
    cp "${JEX_DIR}/templates/Dockerfile" Dockerfile
  fi

  # Create .gitignore if it doesn't exist
  if [ ! -f ".gitignore" ]; then
    echo -e "${YELLOW}Creating .gitignore...${NC}"
    cp "${JEX_DIR}/templates/gitignore" .gitignore
  fi

  # Build image if it doesn't exist
  if ! docker image inspect $DOCKER_IMAGE >/dev/null 2>&1; then
    image_build
  fi

  # Create a new Jekyll site directly in the current directory
  # We'll run Jekyll as the current user to ensure correct file ownership
  local USER_ID=$(id -u)
  local GROUP_ID=$(id -g)

  run_cmd "docker run --rm -v $(pwd):/site -u $USER_ID:$GROUP_ID $DOCKER_IMAGE sh -c \"jekyll new . --force && bundle install\"" 

  # If files are still created as root, fix ownership
  if [ -f "_config.yml" ] && [ $(stat -c "%u" _config.yml) -ne $USER_ID ]; then
    echo -e "${YELLOW}Fixing file ownership...${NC}"
    run_cmd "sudo chown -R $USER_ID:$GROUP_ID ."
  fi

  echo -e "${GREEN}Jekyll project initialized successfully!${NC}"
  echo -e "${YELLOW}To start your Jekyll server, run:${NC}"
  echo -e "./jex.sh serve"
  echo -e "\n${GREEN}You can access your site at:${NC} http://localhost:${JEKYLL_PORT}"
}

# Create a new Jekyll post
function project_new_post() {
  validate_param "$1" "post_title" "Please provide a post title"

  # Format date and title for filename
  local date=$(date +%Y-%m-%d)
  local title_slug=$(echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')
  local filename="_posts/$date-$title_slug.md"

  # Create _posts directory if it doesn't exist
  if [ ! -d "_posts" ]; then
    mkdir -p _posts
  fi

  # Create the post file with front matter
  echo -e "${BLUE}Creating new post: $filename${NC}"
  log_info "Creating new post: $filename"

  cat > "$filename" << EOF
---
layout: post
title: "$1"
date: $date $(date +%H:%M:%S) +0000
categories: blog
---

Write your post content here.
EOF

  echo -e "${GREEN}Post created successfully!${NC}"
  echo -e "${YELLOW}Edit this file: $filename${NC}"
}

# Install a new gem
function project_add_gem() {
  validate_param "$1" "gem_name" "Please provide a gem name"

  echo -e "${BLUE}Adding gem: $1${NC}"
  log_info "Adding gem: $1"

  container_exec "bundle add $1"

  if [ $? -eq 0 ]; then
    echo -e "${GREEN}Gem added successfully!${NC}"
    echo -e "${YELLOW}Remember to restart your Jekyll server for changes to take effect.${NC}"
  fi
}

# Open Jekyll site in browser
function project_open() {
  echo -e "${BLUE}Opening Jekyll site in browser...${NC}"
  log_info "Opening Jekyll site in browser: http://localhost:${JEKYLL_PORT}"

  # Check if server is running
  if ! lsof -Pi :${JEKYLL_PORT} -sTCP:LISTEN -t >/dev/null ; then
    echo -e "${YELLOW}Jekyll server doesn't appear to be running on port ${JEKYLL_PORT}.${NC}"
    echo -e "${YELLOW}Would you like to start it now? (y/n)${NC}"
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      container_serve_detached
    else
      return 1
    fi
  fi

  if [[ "$OSTYPE" == "darwin"* ]]; then
    open "http://localhost:${JEKYLL_PORT}"
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    xdg-open "http://localhost:${JEKYLL_PORT}"
  else
    echo -e "${YELLOW}Please open http://localhost:${JEKYLL_PORT} in your browser${NC}"
  fi
}

# Add fix-permissions command
function project_fix_permissions() {
  fix_permissions "${1:-.}"
}

# ======================================================
# HELP & INFO DOMAIN
# ======================================================

# Display version information
function show_version() {
  echo -e "${BLUE}jex (Jekyll Execution Script) v${JEX_VERSION}${NC}"
  echo -e "A utility for managing Jekyll projects with Docker"
}

# Display help information
function show_help() {
  show_version
  echo -e "\n${BOLD}USAGE:${NC}"
  echo -e "  ./jex.sh [command] [args...]"

  echo -e "\n${BOLD}AVAILABLE COMMANDS:${NC}"
  echo -e "  ${GREEN}init${NC}               Initialize a new Jekyll project in current directory"
  echo -e "  ${GREEN}serve${NC}              Start Jekyll server with live reload"
  echo -e "  ${GREEN}serve-detached${NC}     Run Jekyll server in background"
  echo -e "  ${GREEN}stop${NC}               Stop detached Jekyll server"
  echo -e "  ${GREEN}new-post${NC} \"Title\"    Create a new Jekyll post"
  echo -e "  ${GREEN}exec${NC} \"command\"     Execute a command inside the Jekyll container"
  echo -e "  ${GREEN}add-gem${NC} gem_name   Install a new gem"
  echo -e "  ${GREEN}open${NC}               Open Jekyll site in browser"
  echo -e "  ${GREEN}fix-permissions${NC}    Fix file permissions in the project"
  echo -e "  ${GREEN}build-image${NC}        Build the Jekyll Docker image"
  echo -e "  ${GREEN}build-image${NC} --force Build the Jekyll Docker image (force rebuild)"
  echo -e "  ${GREEN}clean${NC}              Clean up Jekyll Docker containers"
  echo -e "  ${GREEN}clean-all${NC}          Clean up all Jekyll Docker resources"
  echo -e "  ${GREEN}version${NC}            Show version information"
  echo -e "  ${GREEN}help${NC}               Display this help information"

  echo -e "\n${BOLD}EXAMPLES:${NC}"
  echo -e "  ./jex.sh init                 # Create a new Jekyll site"
  echo -e "  ./jex.sh new-post \"My Post\"   # Create a new blog post"
  echo -e "  ./jex.sh serve                # Start the Jekyll server"
  echo -e "  ./jex.sh exec \"bundle update\" # Run a command in the container"

  echo -e "\n${BOLD}CONFIG:${NC}"
  echo -e "  Configuration file location: ${JEX_CONFIG}"
  echo -e "  Current settings:"
  echo -e "    Docker Image: ${DOCKER_IMAGE}"
  echo -e "    Jekyll Port:  ${JEKYLL_PORT}"
}

# ======================================================
# MAIN EXECUTION
# ======================================================

# Ensure jex directory exists
ensure_jex_dir

# Load config
load_config

# Check prerequisites
check_prerequisites

# Parse command
COMMAND=$1
shift || true

case $COMMAND in
  # Image domain
  "build-image")
    if [ "$1" == "--force" ]; then
      image_build true
    else
      image_build
    fi
    ;;

  # Container domain
  "serve")
    container_serve
    ;;
  "serve-detached")
    container_serve_detached
    ;;
  "stop")
    container_stop
    ;;
  "exec")
    container_exec "$*"
    ;;

  # Project domain
  "init")
    project_init
    ;;
  "new-post")
    project_new_post "$*"
    ;;
  "add-gem")
    project_add_gem "$1"
    ;;
  "open")
    project_open
    ;;
  "fix-permissions")
    project_fix_permissions "$1"
    ;;

  # Cleanup
  "clean")
    container_clean
    ;;
  "clean-all")
    container_clean
    image_remove
    ;;

  # Help and info
  "version")
    show_version
    ;;
  "help"|"--help"|"-h"|"")
    show_help
    ;;
  *)
    error_exit "Unknown command: $COMMAND\nRun './jex.sh help' to see available commands."
    ;;
esac

exit 0
