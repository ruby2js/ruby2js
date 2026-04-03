import Config

# Use Req as the HTTP client for ExAws (S3 storage)
# This line is stripped at build time if the app doesn't use Active Storage
config :ex_aws, http_client: ExAws.Request.Req
