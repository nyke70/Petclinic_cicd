# Regional certificate for the ALB's HTTPS listener.
resource "aws_acm_certificate" "alb" {
  count             = local.use_custom_domain ? 1 : 0
  domain_name       = local.fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront always requires its certificate in us-east-1.
resource "aws_acm_certificate" "cloudfront" {
  count             = local.use_custom_domain ? 1 : 0
  provider          = aws.us_east_1
  domain_name       = local.fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# ACM issues the same DNS validation CNAME for both certs (same domain, same
# account), so both certificate_validation resources share one set of
# Route53 records instead of each creating their own (which collides).
locals {
  cert_validation_records = local.use_custom_domain ? {
    primary = {
      name   = one(aws_acm_certificate.alb[0].domain_validation_options).resource_record_name
      type   = one(aws_acm_certificate.alb[0].domain_validation_options).resource_record_type
      record = one(aws_acm_certificate.alb[0].domain_validation_options).resource_record_value
    }
  } : {}
}

resource "aws_route53_record" "cert_validation" {
  for_each = local.cert_validation_records

  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "alb" {
  count                   = local.use_custom_domain ? 1 : 0
  certificate_arn         = aws_acm_certificate.alb[0].arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

resource "aws_acm_certificate_validation" "cloudfront" {
  count                   = local.use_custom_domain ? 1 : 0
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.cloudfront[0].arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}
