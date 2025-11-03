# ============ Stage 1: 基础环境 + MongoDB + Python ============
FROM ubuntu:22.04 AS base

# 避免交互式安装提示
ENV DEBIAN_FRONTEND=noninteractive

# 安装系统依赖：git, python3, pip, venv, wget, gnupg, mongodb
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git \
        python3.10 \
        python3.10-venv \
        python3-pip \
        wget \
        gnupg \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# 安装 MongoDB Community Edition (v7.0 最新稳定)
RUN wget -qO - https://www.mongodb.org/static/pgp/server-7.0.asc | apt-key add - && \
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list && \
    apt-get update && \
    apt-get install -y mongodb-org && \
    rm -rf /var/lib/apt/lists/*

# 安装 MongoDB Database Tools（导出/导入）
RUN wget https://fastdl.mongodb.org/tools/db/mongodb-database-tools-ubuntu2204-x86_64-100.9.4.deb && \
    dpkg -i mongodb-database-tools-ubuntu2204-x86_64-100.9.4.deb && \
    rm mongodb-database-tools-ubuntu2204-x86_64-100.9.4.deb

# 设置工作目录
WORKDIR /app

# 复制项目代码（包括 .git, .gitmodules）
COPY . .

# 更新子模块
RUN git submodule update --init --recursive

# 创建并激活虚拟环境
RUN python3.10 -m venv .venv
ENV PATH="/app/.venv/bin:$PATH"

# 升级 pip
RUN pip install --upgrade pip

# 安装 Python 依赖（优先 requirements.txt）
RUN pip install -r requirements.txt || pip install -r requirements_freeze.txt

# 安装 Playwright + Chromium
RUN pip install playwright && \
    playwright install chromium --with-deps && \
    playwright install-deps

# ============ Stage 2: 运行时配置 ============
FROM base AS runtime

# 复制配置模板
RUN cp config_example.json config.json || echo "Warning: config_example.json not found, using default config.json if exists"

# 暴露 Flask 端口
EXPOSE 5000

# 启动脚本：初始化 MongoDB + 创建用户 + 启动服务
COPY <<'EOF' /start.sh
#!/bin/bash
set -e

# 启动 MongoDB
mongod --fork --logpath /var/log/mongodb.log --dbpath /data/db

# 等待 MongoDB 启动
until mongosh --eval "db.adminCommand('ismaster')" >/dev/null 2>&1; do
  echo "Waiting for MongoDB to start..."
  sleep 2
done

# 创建默认用户（仅首次运行）
if [ ! -f /data/.user_created ]; then
  echo "Creating default admin user..."
  python UserManagerConsole.py <<INPUT
add
admin
admin123
admin123
y
INPUT
  touch /data/.user_created
fi

# 启动两个服务
echo "Starting IntelligenceHubLauncher and ServiceEngine..."
python IntelligenceHubLauncher.py &
python ServiceEngine.py

# 保持容器运行
wait
EOF

RUN chmod +x /start.sh

# 创建数据目录
VOLUME /data/db

# 启动
CMD ["/start.sh"]