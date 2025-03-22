# JEX - Jekyll Easy eXecution

![Jekyll](https://img.shields.io/badge/Jekyll-CC0000?style=for-the-badge&logo=Jekyll&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)

A command-line utility to streamline Jekyll development using Docker, removing the need to install Ruby and Jekyll directly on your machine.

## Features

- 🚀 **Easy setup** - Initialize new Jekyll projects with a single command
- 🐳 **Docker-based** - No need to install Ruby or Jekyll on your host machine
- 🔄 **Live reload** - Instantly see your changes in the browser
- 📝 **Content management** - Easily create new blog posts with proper formatting
- 🔧 **Flexible configuration** - Run commands inside the container
- 🔒 **Proper permissions** - Files created with your user's ownership

## Prerequisites

- Docker installed on your system
- Bash shell

## Installation

1. Download the script:

```bash
curl -o jex.sh https://raw.githubusercontent.com/Rynaro/jex/main/jex.sh
```

2. Make it executable:

```bash
chmod +x jex.sh
```

3. Optionally, move it to a directory in your PATH:

```bash
sudo mv jex.sh /usr/local/bin/jex
```

## Getting Started

### Creating a new Jekyll site

```bash
./jex.sh init
```

This will:
- Create a Dockerfile for Jekyll
- Initialize a new Jekyll project
- Set up proper file permissions

### Start the Jekyll server

```bash
./jex.sh serve
```

Your site will be available at http://localhost:4000

### Run in background (detached mode)

```bash
./jex.sh serve-detached
```

## Usage

```
USAGE:
  ./jex.sh [command] [args...]

AVAILABLE COMMANDS:
  init               Initialize a new Jekyll project in current directory
  serve              Start Jekyll server with live reload
  serve-detached     Run Jekyll server in background
  stop               Stop detached Jekyll server
  new-post "Title"   Create a new Jekyll post
  exec "command"     Execute a command inside the Jekyll container
  add-gem gem_name   Install a new gem
  open               Open Jekyll site in browser
  fix-permissions    Fix file permissions in the project
  build-image        Build the Jekyll Docker image
  clean              Clean up Jekyll Docker containers
  clean-all          Clean up all Jekyll Docker resources
  version            Show version information
  help               Display this help information
```

## Managing Content

### Creating a new blog post

```bash
./jex.sh new-post "My Awesome Post"
```

This creates a new markdown file in the `_posts` directory with proper Jekyll front matter.

### Adding a gem to your project

```bash
./jex.sh add-gem jekyll-seo-tag
```

## Customization

JEX stores configuration in `~/.jex/config` and templates in `~/.jex/templates/`.

You can edit the Dockerfile in `~/.jex/templates/Dockerfile` to customize your Jekyll environment.

## Troubleshooting

### File permission issues

If you encounter permission issues, run:

```bash
./jex.sh fix-permissions
```

### Container issues

To clean up all Jekyll containers:

```bash
./jex.sh clean
```

To remove all Jekyll resources (containers and image):

```bash
./jex.sh clean-all
```

## Examples

```bash
# Create a new Jekyll site
./jex.sh init

# Create a new blog post
./jex.sh new-post "My First Jekyll Post"

# Run a custom command in the container
./jex.sh exec "bundle update"

# Install a new Jekyll plugin
./jex.sh add-gem jekyll-sitemap
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- [Jekyll](https://jekyllrb.com/) - The static site generator
- [Docker](https://www.docker.com/) - Container platform
