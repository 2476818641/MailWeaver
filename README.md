# Automated Mail Server Deployment Tool

[English](#english) | [中文](#中文)

---

## <a name="english"></a>English

> **Note:** The English version of this README was generated with the assistance of Google Gemini. As the author is not a native English speaker, there might be some phrasing inaccuracies. The [Chinese version](#中文) is the original and most accurate reference.

This project provides an interactive shell script designed to simplify the process of deploying a mail server on a Docker-enabled host. It does not create new mail server software but acts as a "glue script" to integrate mature open-source projects (like Mailu) and a lightweight DIY stack, offering a one-click deployment experience for users with different needs.

### Features

*   **Interactive Wizard**: Automatically generates all necessary configuration files through a simple command-line Q&A.
*   **Two Deployment Options**:
    1.  **Mailu (Recommended)**: Deploys the full-featured Mailu mail suite, which includes a modern web administration panel and API. Ideal for scenarios requiring management of multiple users, domains, or a graphical interface.
    2.  **DIY Mail Server**: Deploys a lightweight mail server composed of core components like Postfix, Dovecot, and Roundcube. Suitable for learning, personal use, or as an SMTP relay for applications.
*   **Docker-Based**: All services run in containers, providing environment isolation and simplifying management and migration.
*   **Automated**: The script handles tedious tasks such as configuration generation, directory creation, and service orchestration.
*   **Complete Management Tools**: Built-in scripts for user management, backup, logs, and monitoring.
*   **Security Enhanced**: SQL injection protection, password strength validation, and error handling.

### Design Philosophy

This project aims to be a "binder" and "launcher" for different mail server solutions. We stand on the shoulders of giants (Mailu, Postfix, Dovecot, Docker, etc.) and focus on simplifying the initial, most error-prone "zero-to-one" deployment phase. It is not intended for advanced users seeking extreme customization but is perfect for developers and enthusiasts who want to quickly set up a functional and reliable mail server.

### Prerequisites

Before running this script, please ensure you have:

1.  A clean server (Debian / Ubuntu is recommended).
2.  **`git`**, **`docker`**, and **`docker-compose`** properly installed.
3.  Your own domain name, with the ability to modify its DNS records.
4.  **Outbound traffic on port 25 is not blocked** on your server. You can confirm this with your VPS provider.

### Quick Start

The entire installation process involves just a few simple steps:

**1. Clone this repository**

```bash
git clone https://github.com/bbttca23/MailWeaver.git
cd MailWeaver
```

**2. Run the main installer script**

```bash
chmod +x master_installer.sh
./master_installer.sh
```

**3. Follow the wizard**

The script will start an interactive menu. Simply choose the solution you want (Mailu or DIY) and answer a few questions about your domain and configuration.

### Management Commands

After installation, you can manage your mail server using these commands:

```bash
# DIY Solution - User Management (in build/ directory)
cd build
./mail-admin.sh add        # Add email user
./mail-admin.sh delete     # Delete email user
./mail-admin.sh list       # List all users
./mail-admin.sh passwd     # Change password
./mail-admin.sh toggle     # Enable/Disable user
./mail-admin.sh logs       # View logs
./mail-admin.sh status     # View service status
./mail-admin.sh restart    # Restart services

# Backup & Restore
./backup.sh backup         # Create backup
./backup.sh restore <file> # Restore from backup
./backup.sh list           # List available backups

# View Logs
./logs.sh                  # View all logs
./logs.sh postfix 200      # View Postfix logs (last 200 lines)

# Service Status
./status.sh                # View all services status

# Uninstall
./uninstall.sh diy         # Uninstall DIY mail server
./uninstall.sh mailu       # Uninstall Mailu
```

### Project Structure

```
.
├── master_installer.sh     # Main entry script
├── install_diy.sh          # Dedicated installer for the DIY solution
├── mail-admin.sh           # User management tool for the DIY solution
├── uninstall.sh            # Uninstall script
├── backup.sh               # Backup and restore tool
├── logs.sh                 # Log viewer
├── status.sh               # Service status checker
├── lib/
│   └── common.lib.sh       # Common function library
├── templates/              # Directory for all templates
│   └── mailu/
│       ├── docker-compose.yml.template
│       └── mailu.env.template
├── postfix/                # DIY: Dockerfile for Postfix
├── dovecot/                # DIY: Dockerfile for Dovecot
├── roundcube/              # DIY: Dockerfile for Roundcube and Nginx template
└── README.md               # This file
```

### License

This project is licensed under the [MIT License](LICENSE).

---

## <a name="中文"></a>中文

本项目提供一个交互式的 Shell 脚本，旨在简化在支持 Docker 的服务器上部署邮件服务器的流程。它本身不创造新的邮件服务软件，而是作为一套"胶水"脚本，将成熟的开源项目（如 Mailu）和一套轻量级的 DIY 组件整合在一起，为不同需求的用户提供一键式部署体验。

### 特点

*   **交互式向导**: 通过简单的命令行问答，自动生成所有必要的配置文件。
*   **两种方案可选**:
    1.  **Mailu (推荐)**: 部署功能齐全、带现代化 Web 管理后台和 API 的 Mailu 邮件套件。适合需要管理多用户、多域名或希望有图形化界面的场景。
    2.  **DIY 邮件服务器**: 部署一个由 Postfix, Dovecot, Roundcube 等核心组件构成的轻量级邮件服务器。适合学习、个人使用或作为应用的 SMTP 中继。
*   **基于 Docker**: 所有服务都运行在容器中，实现了环境隔离，便于管理和迁移。
*   **自动化**: 脚本负责处理配置生成、目录创建、服务编排等繁琐工作。
*   **完整管理工具**: 内置用户管理、备份、日志、状态监控脚本。
*   **安全增强**: SQL 注入防护、密码强度验证、完善的错误处理。

### 设计哲学

本项目旨在作为不同邮件服务器解决方案的"粘合剂"和"启动器"。我们站在巨人（Mailu, Postfix, Dovecot, Docker 等）的肩膀上，专注于简化最初的、最容易出错的"从零到一"的部署阶段。它不适合寻求极致定制化的高级用户，但非常适合希望快速搭建一个可用、可靠邮件服务的开发者和系统爱好者。

### 先决条件

在运行此脚本之前，请确保你拥有：

1.  一台纯净的服务器（推荐 Debian / Ubuntu）。
2.  **`git`**, **`docker`** 和 **`docker-compose`** 已正确安装。
3.  一个你自己的域名，并且你可以修改它的 DNS 记录。
4.  服务器的 **25 端口出站流量未被封锁**。你可以联系你的 VPS 提供商确认这一点。

### 快速开始

整个安装过程只需要几个简单的步骤：

**1. 克隆本项目仓库**

```bash
git clone https://github.com/bbttca23/MailWeaver.git
cd MailWeaver
```

**2. 运行主安装脚本**

```bash
chmod +x master_installer.sh
./master_installer.sh
```

**3. 跟随向导**

脚本会启动一个交互式菜单。你只需要根据提示选择你想要的方案（Mailu 或 DIY），并回答几个关于你的域名和配置的问题即可。

### 管理命令

安装完成后，可以使用以下命令管理邮件服务器：

```bash
# DIY 方案 - 用户管理 (在 build 目录下)
cd build
./mail-admin.sh add        # 添加邮箱用户
./mail-admin.sh delete     # 删除邮箱用户
./mail-admin.sh list       # 列出所有用户
./mail-admin.sh passwd     # 修改密码
./mail-admin.sh toggle     # 启用/禁用用户
./mail-admin.sh logs       # 查看日志
./mail-admin.sh status     # 查看服务状态
./mail-admin.sh restart    # 重启服务

# 备份与恢复
./backup.sh backup         # 创建备份
./backup.sh restore <文件> # 恢复备份
./backup.sh list           # 列出可用备份

# 查看日志
./logs.sh                  # 查看所有日志
./logs.sh postfix 200      # 查看 Postfix 日志 (最近200行)

# 服务状态
./status.sh                # 查看所有服务状态

# 卸载
./uninstall.sh diy         # 卸载 DIY 邮件服务器
./uninstall.sh mailu       # 卸载 Mailu
```

### 项目结构

```
.
├── master_installer.sh     # 主入口脚本
├── install_diy.sh          # DIY 方案的专用安装器
├── mail-admin.sh           # DIY 方案的用户管理工具
├── uninstall.sh            # 卸载脚本
├── backup.sh               # 备份恢复工具
├── logs.sh                 # 日志查看器
├── status.sh               # 服务状态检查
├── lib/
│   └── common.lib.sh       # 公共函数库
├── templates/              # 存放所有模板文件
│   └── mailu/
│       ├── docker-compose.yml.template
│       └── mailu.env.template
├── postfix/                # DIY: Postfix 的 Dockerfile
├── dovecot/                # DIY: Dovecot 的 Dockerfile
├── roundcube/              # DIY: Roundcube 的 Dockerfile 和 Nginx 模板
└── README.md               # 本说明文件
```
/



### 许可证

本项目采用 [MIT 许可证](LICENSE)。