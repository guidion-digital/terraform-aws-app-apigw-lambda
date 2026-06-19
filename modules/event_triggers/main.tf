# Cloudwatch Events
#
resource "aws_cloudwatch_event_rule" "schedule" {
  count = var.cloudwatch_schedule != null ? 1 : 0

  name                = "${var.function_name}-schedule"
  description         = "Schedule for ${var.function_name} Lambda"
  schedule_expression = var.cloudwatch_schedule
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "schedule" {
  count = var.cloudwatch_schedule != null ? 1 : 0

  rule      = one(aws_cloudwatch_event_rule.schedule).name
  target_id = var.function_name
  arn       = var.lambda_arn
}

resource "aws_cloudwatch_event_rule" "pattern" {
  count = var.cloudwatch_pattern != null ? 1 : 0

  name          = "${var.function_name}-pattern"
  description   = "Event pattern for ${var.function_name} Lambda"
  event_pattern = var.cloudwatch_pattern
  tags          = var.tags
}

resource "aws_cloudwatch_event_target" "pattern" {
  count = var.cloudwatch_pattern != null ? 1 : 0

  rule      = one(aws_cloudwatch_event_rule.pattern).name
  target_id = var.function_name
  arn       = var.lambda_arn
}

resource "aws_lambda_permission" "events_bridge_pattern" {
  count = var.cloudwatch_pattern != null ? 1 : 0

  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = var.function_name
  principal     = "events.amazonaws.com"
  source_arn    = one(aws_cloudwatch_event_rule.pattern).arn
}

resource "aws_lambda_permission" "events_bridge_schedule" {
  count = var.cloudwatch_schedule != null ? 1 : 0

  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = var.function_name
  principal     = "events.amazonaws.com"
  source_arn    = one(aws_cloudwatch_event_rule.schedule).arn
}

### Other event source triggers
#
resource "aws_lambda_event_source_mapping" "sqs" {
  for_each = toset(var.sqs_triggers)

  event_source_arn = each.value
  function_name    = var.lambda_arn
  enabled          = true
  batch_size       = 1
}
