#!/bin/bash

# Скрипт для развертывания n8n версии 1.113.2 на Ubuntu VPS
# Поддерживает Ubuntu 20.04, 22.04, 24.04 LTS
# Включает поддержку Data Tables (новая функция v1.113.2)
# Автор: Viacheslav Lykov (адаптирован)
# Telegram: https://t.me/JumbleAI
# Youtube: https://www.youtube.com/@ViacheslavLykov
# Версия скрипта: 2.0.0 (для n8n 1.113.2)

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Глобальные переменные
PROJECT_DIR="n8n-compose"
DOMAIN=""
MAIN_DOMAIN=""
SUBDOMAIN=""
SSL_EMAIL=""
ORIGINAL_DIR=""
N8N_VERSION="1.113.2"
DATA_TABLES_SIZE="52428800" # 50MB в байтах (по умолчанию)

# Функции для вывода сообщений
print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_feature() {
    echo -e "${CYAN}🚀 $1${NC}"
}

# Проверка версии Ubuntu
check_ubuntu_version() {
    print_header "Проверка версии Ubuntu"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case $VERSION_ID in
            "20.04"|"22.04"|"24.04")
                print_success "Обнаружена поддерживаемая версия Ubuntu $VERSION_ID LTS"
                ;;
            *)
                print_error "Обнаружена неподдерживаемая версия Ubuntu: $VERSION_ID"
                echo "Поддерживаемые версии: Ubuntu 20.04, 22.04, 24.04 LTS"
                exit 1
                ;;
        esac
    else
        print_error "Не удалось определить версию Ubuntu"
        exit 1
    fi
}

# Показать новые функции версии 1.113.2
show_new_features() {
    print_header "Новые функции n8n 1.113.2"
    print_feature "Data Tables - встроенное хранилище данных (до 50MB)"
    print_feature "Улучшенная производительность workflow"
    print_feature "Новые AI возможности и узлы"
    print_feature "Улучшенный интерфейс управления данными"
    print_feature "Расширенные возможности автоматизации"
    echo
}

# Проверка и установка Docker
install_docker() {
    print_header "Проверка и установка Docker"

    # Проверка наличия Docker
    if command -v docker &>/dev/null; then
        DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)
        print_success "Docker уже установлен: $DOCKER_VERSION"

        # Проверка Docker Compose
        if docker compose version &>/dev/null || docker-compose version &>/dev/null; then
            if docker compose version &>/dev/null; then
                COMPOSE_VERSION=$(docker compose version | cut -d' ' -f4)
                print_success "Docker Compose v2 уже установлен: $COMPOSE_VERSION"
            else
                COMPOSE_VERSION=$(docker-compose version | cut -d' ' -f3)
                print_warning "Обнаружена Docker Compose v1: $COMPOSE_VERSION"
                print_info "Рекомендуется обновить до Docker Compose v2"
            fi
        else
            print_warning "Docker Compose не найден, устанавливаем..."
            install_docker_compose
        fi
    else
        print_warning "Docker не найден, устанавливаем..."
        install_docker_engine
    fi
}

# Установка Docker Engine
install_docker_engine() {
    print_info "Обновление пакетов..."
    apt update && apt upgrade -y

    print_info "Установка необходимых пакетов..."
    apt install -y apt-transport-https ca-certificates curl gnupg lsb-release

    print_info "Добавление ключа Docker..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    print_info "Добавление репозитория Docker..."
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    print_info "Установка Docker Engine..."
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io

    print_info "Запуск Docker..."
    systemctl start docker
    systemctl enable docker

    print_success "Docker успешно установлен"
}

# Установка Docker Compose
install_docker_compose() {
    print_info "Установка Docker Compose v2..."

    # Установка Docker Compose plugin (новый способ)
    apt install -y docker-compose-plugin

    print_success "Docker Compose успешно установлен"
}

# Проверка существующих контейнеров n8n
check_existing_containers() {
    print_header "Проверка существующих контейнеров n8n"

    # Проверка запущенных контейнеров
    if docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | grep -q n8n; then
        print_warning "Обнаружены существующие контейнеры n8n:"
        docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | grep n8n

        read -p "Хотите остановить и удалить существующие контейнеры? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_info "Останавливаем существующие контейнеры..."
            docker stop $(docker ps -aq --filter "name=n8n") 2>/dev/null || true
            docker rm $(docker ps -aq --filter "name=n8n") 2>/dev/null || true
            print_success "Существующие контейнеры остановлены и удалены"
        fi
    else
        print_success "Существующие контейнеры n8n не найдены"
    fi

    # Проверка Docker volumes
    if docker volume ls | grep -q n8n; then
        print_warning "Обнаружены существующие volumes n8n:"
        docker volume ls | grep n8n

        read -p "Хотите сохранить существующие volumes? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Удаляем существующие volumes..."
            docker volume rm $(docker volume ls -q | grep n8n) 2>/dev/null || true
            print_success "Существующие volumes удалены"
        fi
    else
        print_success "Существующие volumes n8n не найдены"
    fi

    # Проверка существующих SSL сертификатов
    if [ -d "$PROJECT_DIR" ] && [ -f "$PROJECT_DIR/letsencrypt/acme.json" ]; then
        print_warning "Обнаружены существующие SSL сертификаты в $PROJECT_DIR/letsencrypt/"
        read -p "Хотите сохранить существующие сертификаты? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Удаляем существующие сертификаты..."
            rm -rf "$PROJECT_DIR/letsencrypt"
            print_success "Существующие сертификаты удалены"
        else
            print_info "Существующие сертификаты будут сохранены"
        fi
    fi
}

# Настройка домена и SSL
setup_domain_ssl() {
    print_header "Настройка домена и SSL"

    # Запрос домена
    read -p "Введите ваш домен (например: n8n.example.com): " DOMAIN
    if [ -z "$DOMAIN" ]; then
        print_error "Домен не может быть пустым"
        exit 1
    fi

    # Проверка формата домена
    if [[ ! $DOMAIN =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        print_error "Неверный формат домена: $DOMAIN"
        exit 1
    fi

    # Запрос email для SSL
    read -p "Введите email для Let's Encrypt сертификата: " SSL_EMAIL
    if [ -z "$SSL_EMAIL" ]; then
        print_error "Email не может быть пустым"
        exit 1
    fi

    # Проверка формата email
    if [[ ! $SSL_EMAIL =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        print_error "Неверный формат email: $SSL_EMAIL"
        exit 1
    fi

    # Настройка размера Data Tables
    read -p "Размер хранилища Data Tables в MB (по умолчанию 50): " TABLES_SIZE_INPUT
    if [ -z "$TABLES_SIZE_INPUT" ]; then
        TABLES_SIZE_INPUT=50
    fi

    # Конвертация в байты (MB * 1024 * 1024)
    DATA_TABLES_SIZE=$((TABLES_SIZE_INPUT * 1024 * 1024))

    print_success "Домен: $DOMAIN"
    print_success "Email: $SSL_EMAIL"
    print_success "Размер Data Tables: ${TABLES_SIZE_INPUT}MB"

    # Извлечение субдомена и основного домена
    if [[ $DOMAIN =~ ^([^.]+)\.(.*)$ ]]; then
        SUBDOMAIN="${BASH_REMATCH[1]}"
        MAIN_DOMAIN="${BASH_REMATCH[2]}"
    else
        SUBDOMAIN="n8n"
        MAIN_DOMAIN="$DOMAIN"
    fi

    print_info "Субдомен: $SUBDOMAIN"
    print_info "Основной домен: $MAIN_DOMAIN"
}

# Создание конфигурационных файлов
create_config_files() {
    print_header "Создание конфигурационных файлов для n8n $N8N_VERSION"

    # Создание директории для проекта
    if [ -d "$PROJECT_DIR" ]; then
        print_warning "Директория $PROJECT_DIR уже существует"
        read -p "Хотите перезаписать файлы? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Пропускаем создание файлов"
            return
        fi
    else
        mkdir -p "$PROJECT_DIR"
    fi

    cd "$PROJECT_DIR"

    # Создание .env файла с поддержкой Data Tables
    print_info "Создание .env файла с поддержкой Data Tables..."
    cat > .env << EOF
# Конфигурация n8n версии $N8N_VERSION
DOMAIN_NAME=$MAIN_DOMAIN
SUBDOMAIN=$SUBDOMAIN
SSL_EMAIL=$SSL_EMAIL
N8N_VERSION=$N8N_VERSION

# Часовой пояс (можно изменить)
GENERIC_TIMEZONE=Europe/Moscow

# Data Tables конфигурация (новая функция v1.113.2)
N8N_DATA_TABLES_MAX_SIZE_BYTES=$DATA_TABLES_SIZE

# Производительность и безопасность
N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
N8N_RUNNERS_ENABLED=true
NODE_ENV=production

# База данных (по умолчанию SQLite, для PostgreSQL раскомментируйте)
# DB_TYPE=postgresdb
# DB_POSTGRESDB_HOST=postgres
# DB_POSTGRESDB_PORT=5432
# DB_POSTGRESDB_DATABASE=n8n
# DB_POSTGRESDB_USER=n8n
# DB_POSTGRESDB_PASSWORD=secure_password_here

# Дополнительные настройки для улучшенной производительности
N8N_LOG_LEVEL=info
N8N_LOG_OUTPUT=console
EXECUTIONS_PROCESS=main
EXECUTIONS_MODE=regular
QUEUE_BULL_REDIS_HOST=redis
QUEUE_BULL_REDIS_PORT=6379
EOF

    # Создание docker-compose.yml с фиксированной версией и Redis для производительности
    print_info "Создание docker-compose.yml для n8n $N8N_VERSION..."
    cat > docker-compose.yml << 'EOF'
name: n8n
services:
  traefik:
    image: "traefik:v3.0"
    restart: always
    command:
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.mytlschallenge.acme.tlschallenge=true"
      - "--certificatesresolvers.mytlschallenge.acme.email=${SSL_EMAIL}"
      - "--certificatesresolvers.mytlschallenge.acme.storage=/letsencrypt/acme.json"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - traefik_data:/letsencrypt
      - /var/run/docker.sock:/var/run/docker.sock:ro
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.traefik.rule=Host(`traefik.${DOMAIN_NAME}`)"
      - "traefik.http.routers.traefik.entrypoints=websecure"
      - "traefik.http.routers.traefik.tls.certresolver=mytlschallenge"
      - "traefik.http.routers.traefik.service=api@internal"
      - "traefik.http.middlewares.traefik.headers.SSLRedirect=true"

  redis:
    image: redis:7-alpine
    restart: always
    volumes:
      - redis_data:/data
    command: redis-server --appendonly yes
    labels:
      - "traefik.enable=false"

  n8n:
    image: docker.n8n.io/n8nio/n8n:${N8N_VERSION}
    restart: always
    depends_on:
      - redis
    ports:
      - "127.0.0.1:5678:5678"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n.rule=Host(`${SUBDOMAIN}.${DOMAIN_NAME}`)"
      - "traefik.http.routers.n8n.tls=true"
      - "traefik.http.routers.n8n.entrypoints=web,websecure"
      - "traefik.http.routers.n8n.tls.certresolver=mytlschallenge"
      - "traefik.http.middlewares.n8n.headers.SSLRedirect=true"
      - "traefik.http.middlewares.n8n.headers.STSSeconds=315360000"
      - "traefik.http.middlewares.n8n.headers.browserXSSFilter=true"
      - "traefik.http.middlewares.n8n.headers.contentTypeNosniff=true"
      - "traefik.http.middlewares.n8n.headers.forceSTSHeader=true"
      - "traefik.http.middlewares.n8n.headers.SSLHost=${DOMAIN_NAME}"
      - "traefik.http.middlewares.n8n.headers.STSIncludeSubdomains=true"
      - "traefik.http.middlewares.n8n.headers.STSPreload=true"
      - "traefik.http.routers.n8n.middlewares=n8n@docker"
    environment:
      - N8N_VERSION=${N8N_VERSION}
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=${N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS}
      - N8N_HOST=${SUBDOMAIN}.${DOMAIN_NAME}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - N8N_RUNNERS_ENABLED=${N8N_RUNNERS_ENABLED}
      - NODE_ENV=${NODE_ENV}
      - WEBHOOK_URL=https://${SUBDOMAIN}.${DOMAIN_NAME}/
      - GENERIC_TIMEZONE=${GENERIC_TIMEZONE}
      - TZ=${GENERIC_TIMEZONE}

      # Data Tables конфигурация (v1.113.2)
      - N8N_DATA_TABLES_MAX_SIZE_BYTES=${N8N_DATA_TABLES_MAX_SIZE_BYTES}

      # Database configuration
      - DB_TYPE=${DB_TYPE:-sqlite}
      - DB_POSTGRESDB_HOST=${DB_POSTGRESDB_HOST}
      - DB_POSTGRESDB_PORT=${DB_POSTGRESDB_PORT}
      - DB_POSTGRESDB_DATABASE=${DB_POSTGRESDB_DATABASE}
      - DB_POSTGRESDB_USER=${DB_POSTGRESDB_USER}
      - DB_POSTGRESDB_PASSWORD=${DB_POSTGRESDB_PASSWORD}

      # Redis configuration for better performance
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379

      # Logging
      - N8N_LOG_LEVEL=${N8N_LOG_LEVEL}
      - N8N_LOG_OUTPUT=${N8N_LOG_OUTPUT}
      - EXECUTIONS_PROCESS=${EXECUTIONS_PROCESS}
      - EXECUTIONS_MODE=${EXECUTIONS_MODE}
    volumes:
      - n8n_data:/home/node/.n8n
      - ./local-files:/files
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:5678/healthz || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  # Раскомментируйте для использования PostgreSQL
  # postgres:
  #   image: postgres:15
  #   restart: always
  #   environment:
  #     - POSTGRES_DB=${DB_POSTGRESDB_DATABASE}
  #     - POSTGRES_USER=${DB_POSTGRESDB_USER}
  #     - POSTGRES_PASSWORD=${DB_POSTGRESDB_PASSWORD}
  #   volumes:
  #     - postgres_data:/var/lib/postgresql/data
  #   labels:
  #     - "traefik.enable=false"

volumes:
  n8n_data:
  traefik_data:
  redis_data:
  # postgres_data:
EOF

    # Создание директории для локальных файлов
    mkdir -p local-files

    # Создание README файла с информацией о Data Tables
    print_info "Создание README файла..."
    cat > README.md << EOF
# n8n $N8N_VERSION Installation

## Новые функции версии $N8N_VERSION

### 🗄️ Data Tables
- **Встроенное хранилище данных** прямо в n8n
- **Размер**: до ${TABLES_SIZE_INPUT}MB (настраивается)
- **Типы данных**: строки, числа, даты
- **Использование**: сохранение данных между выполнениями workflow

### 🚀 Как использовать Data Tables

1. **Создание таблицы**: 
   - В интерфейсе n8n: Overview → Data tables → Create Data table
   - Или из canvas'а: Create workflow → Create Data table

2. **Добавление узла Data Table**:
   - Операции: Get, Insert, Update, Upsert, Delete
   - Условная логика: If Row Exists/Does Not Exist

### ⚙️ Конфигурация

- **Домен**: https://${SUBDOMAIN}.${MAIN_DOMAIN}
- **Traefik Dashboard**: https://traefik.${MAIN_DOMAIN}
- **Data Tables лимит**: ${TABLES_SIZE_INPUT}MB

### 📚 Полезные команды

\`\`\`bash
# Просмотр логов
docker compose logs -f

# Обновление
docker compose pull && docker compose up -d

# Остановка
docker compose down

# Перезапуск
docker compose restart
\`\`\`

### 🔗 Документация
- [Data Tables](https://docs.n8n.io/data/data-tables/)
- [Data Table Node](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.datatable/)
EOF

    # Проверяем, что файлы созданы корректно
    if [ -f "docker-compose.yml" ] && [ -f ".env" ]; then
        print_success "Конфигурационные файлы созданы в директории $PROJECT_DIR"

        # Проверка синтаксиса docker-compose.yml
        if docker compose config --quiet 2>/dev/null; then
            print_success "Синтаксис docker-compose.yml корректен"
        else
            print_warning "Предупреждение: возможны проблемы с синтаксисом docker-compose.yml"
        fi
    else
        print_error "Ошибка: не удалось создать конфигурационные файлы"
        exit 1
    fi

    # Возвращаемся в исходную директорию
    cd "$ORIGINAL_DIR" || {
        print_warning "Не удалось вернуться в исходную директорию: $ORIGINAL_DIR"
    }
}

# Проверка конфигурационных файлов
check_config_files() {
    print_info "Проверка конфигурационных файлов..."

    # Проверка docker-compose.yml
    if [ ! -f "docker-compose.yml" ]; then
        print_error "Файл docker-compose.yml не найден"
        return 1
    fi

    # Проверка синтаксиса docker-compose.yml
    if ! docker compose config --quiet 2>/dev/null; then
        print_error "Ошибка в синтаксисе docker-compose.yml"
        print_info "Проверьте файл docker-compose.yml на ошибки"
        return 1
    else
        print_success "docker-compose.yml корректен"
    fi

    # Проверка .env файла
    if [ ! -f ".env" ]; then
        print_error "Файл .env не найден"
        return 1
    fi

    print_success "Все конфигурационные файлы найдены и корректны"
    return 0
}

# Запуск сервисов
start_services() {
    print_header "Запуск сервисов n8n $N8N_VERSION"

    # Проверяем и создаем директорию если нужно
    if [ ! -d "$PROJECT_DIR" ]; then
        print_error "Директория $PROJECT_DIR не найдена"
        exit 1
    fi

    cd "$PROJECT_DIR"

    # Проверяем конфигурационные файлы
    if ! check_config_files; then
        exit 1
    fi

    print_info "Загрузка образов Docker..."
    docker compose pull

    print_info "Запуск Docker Compose..."
    docker compose up -d

    print_info "Ожидание запуска сервисов (это может занять 2-3 минуты)..."
    sleep 30

    # Проверка статуса
    if docker compose ps | grep -q "Up"; then
        print_success "Сервисы успешно запущены!"

        # Получение внешнего IP для информации
        EXTERNAL_IP=$(curl -s ifconfig.me 2>/dev/null || echo "не удалось определить")

        print_header "🎉 Информация о развертывании n8n $N8N_VERSION"
        print_feature "n8n доступен: https://${SUBDOMAIN}.${MAIN_DOMAIN}"
        print_feature "Traefik dashboard: https://traefik.${MAIN_DOMAIN}"
        print_feature "Data Tables: Встроенное хранилище до ${TABLES_SIZE_INPUT}MB"
        echo -e "${BLUE}ℹ Внешний IP сервера: $EXTERNAL_IP${NC}"
        echo -e "${YELLOW}⚠ Убедитесь, что DNS записи указывают на этот IP${NC}"
        echo -e "${YELLOW}⚠ Первый запуск может занять несколько минут${NC}"
        echo -e "${CYAN}🚀 Попробуйте новые Data Tables в разделе Overview → Data tables${NC}"
    else
        print_error "Ошибка запуска сервисов"
        print_info "Проверьте логи:"
        docker compose logs
        exit 1
    fi
}

# Настройка автозапуска
setup_autostart() {
    print_header "Настройка автозапуска"

    # Создание systemd сервиса для автозапуска
    cat > /etc/systemd/system/n8n.service << EOF
[Unit]
Description=n8n $N8N_VERSION Workflow Automation with Data Tables
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$ORIGINAL_DIR/$PROJECT_DIR
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable n8n
    # Запускаем сервис сразу для проверки
    if systemctl start n8n 2>/dev/null; then
        print_success "Сервис n8n запущен"
    else
        print_warning "Не удалось автоматически запустить сервис n8n. Проверьте логи: journalctl -u n8n -e"
    fi

    print_success "Автозапуск настроен"
    print_info "Сервисы будут автоматически запускаться при перезагрузке сервера"
}

# Основная функция
main() {
    # Проверка прав root
    if [ "$EUID" -ne 0 ]; then
        print_error "Этот скрипт должен быть запущен с правами root (sudo)"
        exit 1
    fi

    print_header "Установка n8n $N8N_VERSION на Ubuntu VPS"
    print_info "Скрипт поддерживает Ubuntu 20.04, 22.04, 24.04 LTS"
    show_new_features
    echo

    # Сохраняем исходную директорию
    ORIGINAL_DIR=$(pwd)

    # Выполнение шагов
    check_ubuntu_version
    install_docker
    check_existing_containers
    setup_domain_ssl
    create_config_files
    start_services
    setup_autostart

    print_header "🎉 Установка n8n $N8N_VERSION завершена!"
    print_success "n8n с Data Tables успешно развернут на вашем сервере"
    print_info "Не забудьте настроить DNS записи для домена"
    print_info "Используйте 'docker compose logs -f' в директории $PROJECT_DIR для просмотра логов"
    print_feature "Попробуйте новые Data Tables: Overview → Data tables в интерфейсе n8n"
}

# Обработка аргументов командной строки
case "${1:-}" in
    --help|-h)
        echo "Скрипт для развертывания n8n $N8N_VERSION на Ubuntu VPS"
        echo ""
        echo "Использование: $0 [опции]"
        echo ""
        echo "Опции:"
        echo "  --help, -h          Показать эту справку"
        echo "  --version, -v       Показать версию скрипта"
        echo "  --update            Обновить n8n до версии $N8N_VERSION"
        echo "  --stop              Остановить все сервисы n8n"
        echo "  --restart           Перезапустить сервисы n8n"
        echo "  --check             Проверить конфигурационные файлы"
        echo "  --logs              Показать логи n8n"
        echo ""
        echo "Новые функции v$N8N_VERSION:"
        echo "  • Data Tables - встроенное хранилище данных"
        echo "  • Улучшенная производительность"
        echo "  • Расширенные AI возможности"
        echo ""
        exit 0
        ;;
    --version|-v)
        echo "n8n Installation Script v2.0.0"
        echo "Для n8n версии $N8N_VERSION с Data Tables"
        echo "Поддерживает Ubuntu 20.04, 22.04, 24.04 LTS"
        exit 0
        ;;
    --update)
        print_header "Обновление n8n до версии $N8N_VERSION"
        ORIGINAL_DIR=$(pwd)
        if [ -d "n8n-compose" ]; then
            cd n8n-compose
            if [ ! -f "docker-compose.yml" ]; then
                print_error "Файл docker-compose.yml не найден в директории n8n-compose"
                exit 1
            fi
            # Обновляем .env файл для новой версии если нужно
            if ! grep -q "N8N_VERSION=$N8N_VERSION" .env 2>/dev/null; then
                print_info "Обновление конфигурации для версии $N8N_VERSION..."
                sed -i "s/N8N_VERSION=.*/N8N_VERSION=$N8N_VERSION/" .env
                if ! grep -q "N8N_DATA_TABLES_MAX_SIZE_BYTES" .env; then
                    echo "N8N_DATA_TABLES_MAX_SIZE_BYTES=$DATA_TABLES_SIZE" >> .env
                fi
            fi
            docker compose pull
            docker compose up -d
            print_success "n8n обновлен до версии $N8N_VERSION с поддержкой Data Tables"
        else
            print_error "Директория n8n-compose не найдена"
            exit 1
        fi
        cd "$ORIGINAL_DIR" 2>/dev/null || true
        exit 0
        ;;
    --stop)
        print_header "Остановка n8n"
        ORIGINAL_DIR=$(pwd)
        if [ -d "n8n-compose" ]; then
            cd n8n-compose
            if [ ! -f "docker-compose.yml" ]; then
                print_error "Файл docker-compose.yml не найден в директории n8n-compose"
                exit 1
            fi
            docker compose down
            print_success "n8n остановлен"
        else
            print_error "Директория n8n-compose не найдена"
            exit 1
        fi
        cd "$ORIGINAL_DIR" 2>/dev/null || true
        exit 0
        ;;
    --restart)
        print_header "Перезапуск n8n"
        ORIGINAL_DIR=$(pwd)
        if [ -d "n8n-compose" ]; then
            cd n8n-compose
            if [ ! -f "docker-compose.yml" ]; then
                print_error "Файл docker-compose.yml не найден в директории n8n-compose"
                exit 1
            fi
            docker compose restart
            print_success "n8n перезапущен"
        else
            print_error "Директория n8n-compose не найдена"
            exit 1
        fi
        cd "$ORIGINAL_DIR" 2>/dev/null || true
        exit 0
        ;;
    --logs)
        print_header "Логи n8n"
        ORIGINAL_DIR=$(pwd)
        if [ -d "n8n-compose" ]; then
            cd n8n-compose
            if [ ! -f "docker-compose.yml" ]; then
                print_error "Файл docker-compose.yml не найден в директории n8n-compose"
                exit 1
            fi
            docker compose logs -f --tail=100
        else
            print_error "Директория n8n-compose не найдена"
            exit 1
        fi
        cd "$ORIGINAL_DIR" 2>/dev/null || true
        exit 0
        ;;
    --check)
        print_header "Проверка конфигурации"
        ORIGINAL_DIR=$(pwd)
        if [ -d "n8n-compose" ]; then
            cd n8n-compose
            if check_config_files; then
                print_success "Конфигурация корректна"
                print_info "Версия образа n8n: $(grep 'image.*n8n:' docker-compose.yml | cut -d':' -f3 || echo 'не определена')"
                if grep -q "N8N_DATA_TABLES_MAX_SIZE_BYTES" .env; then
                    TABLES_SIZE=$(grep "N8N_DATA_TABLES_MAX_SIZE_BYTES" .env | cut -d'=' -f2)
                    TABLES_SIZE_MB=$((TABLES_SIZE / 1024 / 1024))
                    print_info "Размер Data Tables: ${TABLES_SIZE_MB}MB"
                fi
            else
                print_error "Найдены ошибки в конфигурации"
                exit 1
            fi
        else
            print_error "Директория n8n-compose не найдена"
            exit 1
        fi
        cd "$ORIGINAL_DIR" 2>/dev/null || true
        exit 0
        ;;
    *)
        main
        ;;
esac
