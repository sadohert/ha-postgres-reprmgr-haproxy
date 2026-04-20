# --- Network Load Balancer (Internal) ---

resource "aws_lb" "ha_postgres" {
  name               = "ha-postgres-nlb"
  internal           = true # Critical: Allow external access for user's laptop
  load_balancer_type = "network"
  subnets            = local.selected_subnets

  enable_cross_zone_load_balancing = true

  tags = merge(local.common_tags, {
    Name = "ha-postgres-nlb"
  })
}

# --- Target Groups ---

# 1. Write Target Group (Port 5000) -> Master
resource "aws_lb_target_group" "pg_write" {
  name     = "ha-postgres-write-tg-tcp"
  port     = 5000
  protocol = "TCP"
  preserve_client_ip = "false"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    protocol            = "HTTP"
    port                = 8008          # pgchk.py port
    path                = "/master"     # Only healthy on Primary
    interval            = 10
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name = "ha-postgres-write-tg"
  }
}

# 2. Read Target Group (Port 5001) -> Replicas
resource "aws_lb_target_group" "pg_read" {
  name     = "ha-postgres-read-tg-tcp"
  port     = 5001
  protocol = "TCP"
  preserve_client_ip = "false"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    protocol            = "HTTP"
    port                = 8008          # pgchk.py port
    path                = "/replica"    # Healthy on Standbys
    interval            = 10
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name = "ha-postgres-read-tg"
  }
}

# --- Listeners ---

resource "aws_lb_listener" "pg_write" {
  load_balancer_arn = aws_lb.ha_postgres.arn
  port              = 5000
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.pg_write.arn
  }
}

resource "aws_lb_listener" "pg_read" {
  load_balancer_arn = aws_lb.ha_postgres.arn
  port              = 5001
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.pg_read.arn
  }
}

# --- Attachments ---

# Attach ALL nodes to BOTH target groups.
# The Health Checks determine routing logic dynamically.

# Attach Primary to both (it handles both write and read if needed, though pgchk controls routing)
resource "aws_lb_target_group_attachment" "primary_write" {
  target_group_arn = aws_lb_target_group.pg_write.arn
  target_id        = aws_instance.primary.id
  port             = 5000
}

resource "aws_lb_target_group_attachment" "primary_read" {
  target_group_arn = aws_lb_target_group.pg_read.arn
  target_id        = aws_instance.primary.id
  port             = 5001
}

# Attach Standbys to both
resource "aws_lb_target_group_attachment" "standby_write" {
  count            = 2
  target_group_arn = aws_lb_target_group.pg_write.arn
  target_id        = aws_instance.standbys[count.index].id
  port             = 5000
}

resource "aws_lb_target_group_attachment" "standby_read" {
  count            = 2
  target_group_arn = aws_lb_target_group.pg_read.arn
  target_id        = aws_instance.standbys[count.index].id
  port             = 5001
}

# --- DC2 Network Load Balancer ---

resource "aws_lb" "ha_postgres_dc2" {
  count              = var.dc2_enabled ? 1 : 0
  name               = "ha-postgres-dc2-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = local.selected_subnets

  enable_cross_zone_load_balancing = true

  tags = merge(local.common_tags, {
    Name = "ha-postgres-dc2-nlb"
  })
}

resource "aws_lb_target_group" "dc2_pg_write" {
  count    = var.dc2_enabled ? 1 : 0
  name     = "ha-postgres-dc2-write-tg"
  port     = 5000
  protocol = "TCP"
  preserve_client_ip = "false"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    protocol            = "HTTP"
    port                = 8008
    path                = "/master"
    interval            = 10
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name = "ha-postgres-dc2-write-tg"
  }
}

resource "aws_lb_target_group" "dc2_pg_read" {
  count    = var.dc2_enabled ? 1 : 0
  name     = "ha-postgres-dc2-read-tg"
  port     = 5001
  protocol = "TCP"
  preserve_client_ip = "false"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    protocol            = "HTTP"
    port                = 8008
    path                = "/replica"
    interval            = 10
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name = "ha-postgres-dc2-read-tg"
  }
}

resource "aws_lb_listener" "dc2_pg_write" {
  count             = var.dc2_enabled ? 1 : 0
  load_balancer_arn = aws_lb.ha_postgres_dc2[0].arn
  port              = 5000
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dc2_pg_write[0].arn
  }
}

resource "aws_lb_listener" "dc2_pg_read" {
  count             = var.dc2_enabled ? 1 : 0
  load_balancer_arn = aws_lb.ha_postgres_dc2[0].arn
  port              = 5001
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dc2_pg_read[0].arn
  }
}

resource "aws_lb_target_group_attachment" "dc2_upstream_write" {
  count            = var.dc2_enabled ? 1 : 0
  target_group_arn = aws_lb_target_group.dc2_pg_write[0].arn
  target_id        = aws_instance.dc2_upstream[0].id
  port             = 5000
}

resource "aws_lb_target_group_attachment" "dc2_upstream_read" {
  count            = var.dc2_enabled ? 1 : 0
  target_group_arn = aws_lb_target_group.dc2_pg_read[0].arn
  target_id        = aws_instance.dc2_upstream[0].id
  port             = 5001
}

resource "aws_lb_target_group_attachment" "dc2_standby_write" {
  count            = var.dc2_enabled ? 2 : 0
  target_group_arn = aws_lb_target_group.dc2_pg_write[0].arn
  target_id        = aws_instance.dc2_standbys[count.index].id
  port             = 5000
}

resource "aws_lb_target_group_attachment" "dc2_standby_read" {
  count            = var.dc2_enabled ? 2 : 0
  target_group_arn = aws_lb_target_group.dc2_pg_read[0].arn
  target_id        = aws_instance.dc2_standbys[count.index].id
  port             = 5001
}
