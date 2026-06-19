# Rewrite Notes

# Group Rules, Provisioned Outside of Application Repos

We'll only ever start using this if we create rulesets in the infra repo for projects to use

```hcl
group_rules = optional(
  list(object({
    name            = string,
    arn             = string,
    priority        = number,
    override_action = string,
    excluded_rules  = list(string)
    })
), []),
```

# Proper IP Set Loops

It's not possible to delete the aws_wafv2_ip_set resource whilst it's in a rule, which is why we currently have a fixed named blacklist, even when it's empty.

Variables:

```hcl
  ...
  blocked_ips = optional(map(object({
    ip_list  = list(string),
    priority = number
    })),
  null)
...
```

```hcl
locals {
blocked_ips       = var.firewall_configuration != null ? (var.firewall_configuration.blocked_ips != null ? var.firewall_configuration.blocked_ips : {}) : {}
}
```

In action:

```hcl
resource "aws_wafv2_ip_set" "blacklist" {
  # for_each = local.blocked_ips
  # for_each = var.firewall_configuration.blocked_ips != null ? var.firewall_configuration.blocked_ips : {}
  name               = "${var.application_name}-blocked"
  description        = "Set of blocked IPs for ${var.application_name}"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = var.firewall_configuration.blocked_ips
}

ip_sets_rule = local.blocked_ips == null ? [] : [for this_rule, these_values in local.blocked_ips :
  {
    name          = "${var.application_name}-${this_rule}",
    priority      = these_values.priority,
    ip_set_arn    = aws_wafv2_ip_set.this[this_rule].arn,
    action        = "block",
    response_code = 403
  }
]
```

# Supporting Resources Permissions

The `var.lambdas{}.role_arn` field controls what permissions the Lambda has. This is usually set to whatever `var.role_arn` is set to in the TFC workspace, but this poses problems here.

If we set it to include all supporting resources in the application's namespace, it'll mean all the Lambdas in the application will have those permissions, not just the ones that need it.
