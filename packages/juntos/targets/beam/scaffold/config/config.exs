import Config

# Use Req as the HTTP client for ExAws (S3 storage)
config :ex_aws, http_client: ExAws.Request.Req
