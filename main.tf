locals {
  flattened_frontend_configs = merge([
    for lb_key, lb in var.load_balancers : {
      for cfg_key, cfg in lb.frontend_configs :
      "${lb_key}.${cfg_key}" => merge(cfg, {
        lb_key = lb_key
      })
    }
  ]...)

  flattened_rules = merge([
    for lb_key, lb in var.load_balancers : {
      for rule_key, rule in lb.lb_settings.rules :
      "${lb_key}.${rule_key}" => merge(rule, {
        lb_key = lb_key
      })
    }
  ]...)

  flattened_probes = merge([
    for lb_key, lb in var.load_balancers : {
      for probe_key, probe in lb.lb_settings.probes :
      "${lb_key}.${probe_key}" => merge(probe, {
        lb_key = lb_key
      })
    }
  ]...)
}

resource "azurerm_public_ip" "pips" {
  for_each            = local.flattened_frontend_configs
  name                = each.value.pip_name
  location            = data.azurerm_resource_group.rg[var.load_balancers[each.value.lb_key].resource_group_name].location
  resource_group_name = data.azurerm_resource_group.rg[var.load_balancers[each.value.lb_key].resource_group_name].name
  allocation_method   = "Static"
  sku                 = "Standard"

  lifecycle {
    create_before_destroy = true
  }
}

resource "azurerm_lb" "lb" {
  for_each            = var.load_balancers
  name                = each.value.lb_settings.name
  location            = data.azurerm_resource_group.rg[each.value.resource_group_name].location
  resource_group_name = data.azurerm_resource_group.rg[each.value.resource_group_name].name
  sku                 = "Standard"
  tags                = each.value.tags

  dynamic "frontend_ip_configuration" {
    for_each = each.value.frontend_configs
    content {
      name                 = frontend_ip_configuration.value.config_name
      public_ip_address_id = azurerm_public_ip.pips["${each.key}.${frontend_ip_configuration.key}"].id
    }
  }
}

resource "azurerm_lb_backend_address_pool" "backend" {
  for_each        = var.load_balancers
  loadbalancer_id = azurerm_lb.lb[each.key].id
  name            = each.value.lb_settings.backend_pool_name
}

resource "azurerm_lb_probe" "probe" {
  for_each        = local.flattened_probes
  loadbalancer_id = azurerm_lb.lb[each.value.lb_key].id
  name            = each.value.name
  port            = each.value.port
}

resource "terraform_data" "rule_frontend_ref" {
  for_each = local.flattened_rules
  input    = each.value.frontend_ip_configuration_name
}

resource "azurerm_lb_rule" "rules" {
  for_each                       = local.flattened_rules
  loadbalancer_id                = azurerm_lb.lb[each.value.lb_key].id
  name                           = each.value.name
  protocol                       = each.value.protocol
  frontend_port                  = each.value.frontend_port
  backend_port                   = each.value.backend_port
  frontend_ip_configuration_name = each.value.frontend_ip_configuration_name
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.backend[each.value.lb_key].id]
  probe_id                       = each.value.probe_key != null ? azurerm_lb_probe.probe["${each.value.lb_key}.${each.value.probe_key}"].id : null

  lifecycle {
    replace_triggered_by = [
      terraform_data.rule_frontend_ref[each.key]
    ]
  }
}
