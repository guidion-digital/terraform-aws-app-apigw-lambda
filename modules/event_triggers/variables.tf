variable "lambda_name" {
  description = "The name for the Lambda"
}

variable "lambda_arn" {
  description = "ARN of the Lambda we're attaching events to"
}

variable "function_name" {
  description = "The name of the Lambda function"
}

variable "sqs_triggers" {
  description = "List of SQS ARNs to attach to the Lambda"
  type        = list(string)
  default     = []
}

variable "cloudwatch_schedule" {
  description = "Schedule for the Cloudwatch Event"
  type        = string
  default     = null
}

variable "cloudwatch_pattern" {
  description = "Pattern for the Cloudwatch Event"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
}
