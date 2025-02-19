terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  token     = var.yc_token
  cloud_id  = var.yc_cloud_id
  folder_id = var.yc_folder_id
  zone      = "ru-central1-a"
}

# Создание VPC
resource "yandex_vpc_network" "network" {
  name = "my-network"
}

# Приватная подсеть для веб-серверов и Elasticsearch
resource "yandex_vpc_subnet" "private_subnet" {
  name           = "private-subnet"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = ["192.168.10.0/24"]
  folder_id = var.yc_folder_id
  route_table_id = yandex_vpc_route_table.rt.id
}

# Публичная подсеть для Zabbix, Kibana, Bastion и балансировщика
resource "yandex_vpc_subnet" "public_subnet" {
  name           = "public-subnet"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = ["192.168.20.0/24"]
  folder_id = var.yc_folder_id
}

# NAT-шлюз для исходящего интернета
resource "yandex_vpc_gateway" "nat_gateway" {
  name = "nat-gateway"
  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "rt" {
  name = "nat-route-table"
  network_id = yandex_vpc_network.network.id
  folder_id = var.yc_folder_id

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat_gateway.id
  }
}

# Security Group для веб-серверов и Elasticsearch
resource "yandex_vpc_security_group" "private_sg" {
  name        = "private-security-group"
  network_id  = yandex_vpc_network.network.id

  ingress {
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = ["192.168.20.0/24"] # Разрешаем SSH только из публичной подсети
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security Group для Zabbix, Kibana, Bastion
resource "yandex_vpc_security_group" "public_sg" {
  name        = "public-security-group"
  network_id  = yandex_vpc_network.network.id

  ingress {
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = ["0.0.0.0/0"] # Разрешаем SSH из любого места
  }

  ingress {
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"] # Разрешаем HTTP из любого места
  }

  ingress {
    protocol       = "TCP"
    port           = 443
    v4_cidr_blocks = ["0.0.0.0/0"] # Разрешаем HTTPS из любого места
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security Group для балансировщика
resource "yandex_vpc_security_group" "alb_sg" {
  name        = "alb-sg"
  network_id  = yandex_vpc_network.network.id

  egress {
    protocol       = "ANY"
    description    = "any"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 1
    to_port        = 65535
  }

  ingress {
    protocol       = "TCP"
    description    = "ext-http"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  ingress {
    protocol       = "TCP"
    description    = "ext-https"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }

  ingress {
    protocol          = "TCP"
    description       = "healthchecks"
    predefined_target = "loadbalancer_healthchecks"
    port              = 30080
  }
}

# Бастион-хост (прерываемый)
resource "yandex_compute_instance" "bastion" {
  name        = "bastion"
  hostname    = "bastion"
  zone = "ru-central1-a"
  folder_id = var.yc_folder_id
  service_account_id = var.yc_service_account_id
  platform_id = "standard-v3"
    
    resources {
    core_fraction = 20
    cores  = 2
    memory = 4
  }

  scheduling_policy {
    preemptible = true # Прерываемая машина
  }

  boot_disk {
    initialize_params {
      image_id = "fd8sk333i8jmpouraqok" # Ubuntu 22.04
      type     = "network-hdd"
      size     = 10
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.public_subnet.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.public_sg.id]
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_ed25519.pub")}" # Используем ed25519
  }
}

# Веб-сервер web_a
resource "yandex_compute_instance" "web_a" {
  name        = "web-a"
  hostname    = "web-a"
  zone = "ru-central1-a"
  folder_id = var.yc_folder_id
  service_account_id = var.yc_service_account_id
  platform_id = "standard-v3"
    
    resources {
    core_fraction = 20
    cores  = 2
    memory = 4
  }

  scheduling_policy {
    preemptible = true # Прерываемая машина
  }

  boot_disk {
    initialize_params {
      image_id = "fd8sk333i8jmpouraqok" # Ubuntu 22.04
      type     = "network-hdd"
      size     = 10
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.private_subnet.id
    nat                = false
    security_group_ids = [yandex_vpc_security_group.private_sg.id]
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_ed25519.pub")}"
  }
}

# Веб-сервер web_b
resource "yandex_compute_instance" "web_b" {
  name        = "web-b"
  hostname    = "web-b"
  zone = "ru-central1-a"
  folder_id = var.yc_folder_id
  service_account_id = var.yc_service_account_id
  platform_id = "standard-v3"
    
    resources {
    core_fraction = 20
    cores  = 2
    memory = 4
  }

  scheduling_policy {
    preemptible = true # Прерываемая машина
  }

  boot_disk {
    initialize_params {
      image_id = "fd8sk333i8jmpouraqok" # Ubuntu 22.04
      type     = "network-hdd"
      size     = 10
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.private_subnet.id
    nat                = false
    security_group_ids = [yandex_vpc_security_group.private_sg.id]
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_ed25519.pub")}" # Используем ed25519
  }
}

# Zabbix Server (прерываемый)
resource "yandex_compute_instance" "zabbix" {
  name        = "zabbix"
  hostname    = "zabbix"
  zone = "ru-central1-a"
  folder_id = var.yc_folder_id
  service_account_id = var.yc_service_account_id
  platform_id = "standard-v3"
    
    resources {
    core_fraction = 20
    cores  = 2
    memory = 4
  }

  scheduling_policy {
    preemptible = true # Прерываемая машина
  }

  boot_disk {
    initialize_params {
      image_id = "fd8sk333i8jmpouraqok" # Ubuntu 22.04
      type     = "network-hdd"
      size     = 10
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.public_subnet.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.public_sg.id]
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_ed25519.pub")}" # Используем ed25519
  }
}

# Elasticsearch (прерываемый)
resource "yandex_compute_instance" "elasticsearch" {
  name        = "elasticsearch"
  hostname        = "elasticsearch"
  zone = "ru-central1-a"
  folder_id = var.yc_folder_id
  service_account_id = var.yc_service_account_id
  platform_id = "standard-v3"
    
    resources {
    core_fraction = 20
    cores  = 2
    memory = 4
  }

  scheduling_policy {
    preemptible = true # Прерываемая машина
  }

  boot_disk {
    initialize_params {
      image_id = "fd8sk333i8jmpouraqok" # Ubuntu 22.04
      type     = "network-hdd"
      size     = 10
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.private_subnet.id
    nat                = false
    security_group_ids = [yandex_vpc_security_group.private_sg.id]
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_ed25519.pub")}" # Используем ed25519
  }
}

# Kibana (прерываемый)
resource "yandex_compute_instance" "kibana" {
  name        = "kibana"
  hostname        = "kibana"
  zone = "ru-central1-a"
  folder_id = var.yc_folder_id
  service_account_id = var.yc_service_account_id
  platform_id = "standard-v3"
    
    resources {
    core_fraction = 20
    cores  = 2
    memory = 4
  }

  scheduling_policy {
    preemptible = true # Прерываемая машина
  }

  boot_disk {
    initialize_params {
      image_id = "fd8sk333i8jmpouraqok" # Ubuntu 22.04
      type     = "network-hdd"
      size     = 10
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.public_subnet.id
    nat               = true
    security_group_ids = [yandex_vpc_security_group.alb_sg.id]
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_ed25519.pub")}" # Используем ed25519
  }
}

# Target Group для балансировщика
resource "yandex_alb_target_group" "web" {
  name = "web-target-group"

  target {
    subnet_id  = yandex_vpc_subnet.private_subnet.id
    ip_address = yandex_compute_instance.web_a.network_interface.0.ip_address
  }

  target {
    subnet_id  = yandex_vpc_subnet.private_subnet.id
    ip_address = yandex_compute_instance.web_b.network_interface.0.ip_address
  }
}

# Backend Group для балансировщика
resource "yandex_alb_backend_group" "web" {
  name = "web-backend-group"
  
  http_backend {
    name             = "web-backend"
    weight           = 1
    port             = 80
    target_group_ids = [yandex_alb_target_group.web.id]
    healthcheck {
      timeout  = "10s"
      interval = "2s"
      http_healthcheck {
        path = "/"
      }
    }
  }
}

# HTTP Router для балансировщика
resource "yandex_alb_http_router" "web" {
  name = "web-router"
}

resource "yandex_alb_virtual_host" "web" {
  name           = "web-virtual-host"
  http_router_id = yandex_alb_http_router.web.id
  route {
    name = "web-route"
    http_route {
      http_route_action {
        backend_group_id = yandex_alb_backend_group.web.id
      }
    }
  }
}

# Application Load Balancer
resource "yandex_alb_load_balancer" "web" {
  name               = "web-balancer"
  network_id         = yandex_vpc_network.network.id
  security_group_ids = [yandex_vpc_security_group.alb_sg.id]

  allocation_policy {
    location {
      zone_id   = "ru-central1-a"
      subnet_id = yandex_vpc_subnet.public_subnet.id
    }
  }

  listener {
    name = "web-listener"
    endpoint {
      address {
        external_ipv4_address {
        }
      }
      ports = [80]
    }
    http {
      handler {
        http_router_id = yandex_alb_http_router.web.id
      }
    }
  }
}

# Резервное копирование (снапшоты)
resource "yandex_compute_snapshot_schedule" "backup" {
  name           = "backup-schedule"
  schedule_policy {
    expression = "0 2 * * *" # Ежедневно в 2:00
  }

  snapshot_spec {
    description = "Daily backup"
  }

  retention_period = "168h" # 7 дней

  disk_ids = [
    yandex_compute_instance.web_a.boot_disk[0].disk_id,
    yandex_compute_instance.web_b.boot_disk[0].disk_id,
    yandex_compute_instance.zabbix.boot_disk[0].disk_id,
    yandex_compute_instance.elasticsearch.boot_disk[0].disk_id,
    yandex_compute_instance.kibana.boot_disk[0].disk_id,
  ]
}
