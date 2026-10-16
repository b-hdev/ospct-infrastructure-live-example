variable "name" {
  description = "The name of the SQS queue"
  type        = string
}

variable "delay_seconds" {
  description = "Number of seconds to delay each message"
  type        = number
  default     = 0
}

variable "max_message_size" {
  description = "Maximum size of each message"
  type        = number
  default     = 262144
}

variable "message_retention_seconds" {
  description = "Number of seconds to retain each message"
  type        = number
  default     = 345600
}

variable "tags" {
  description = "Tags to apply to the SQS queue"
  type        = map(string)
  default     = {}
}
