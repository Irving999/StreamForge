resource "aws_sqs_queue" "processing" {
  name                       = local.processing_queue_name
  visibility_timeout_seconds = 600
  max_message_size           = 1048576
}

resource "aws_sqs_queue" "processing_dlq" {
  name                      = local.processing_dlq_queue_name
  message_retention_seconds = 1209600
  max_message_size          = 1048576
}

resource "aws_sqs_queue_redrive_policy" "processing" {
  queue_url = aws_sqs_queue.processing.id

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.processing_dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "processing_dlq" {
  queue_url = aws_sqs_queue.processing_dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.processing.arn]
  })
}
