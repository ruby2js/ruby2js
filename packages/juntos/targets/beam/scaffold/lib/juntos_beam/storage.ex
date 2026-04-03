defmodule JuntosBeam.Storage do
  @moduledoc """
  S3 storage bridge for QuickBEAM.
  Handles __storage_* calls from JS Active Storage adapter.
  Uses ExAws.S3 for S3-compatible object storage (AWS S3, R2, Tigris, MinIO).
  """

  require Logger

  @doc """
  Build QuickBEAM handler map for storage operations via ExAws.S3.
  """
  def s3_handlers do
    %{
      "__storage_upload" => fn [key, base64_data, content_type] ->
        binary = Base.decode64!(base64_data)

        result =
          ExAws.S3.put_object(bucket(), key, binary, content_type: content_type)
          |> ExAws.request!(ex_aws_config())

        case result do
          %{status_code: code} when code in 200..299 -> :ok
          other -> raise "S3 upload failed: #{inspect(other)}"
        end
      end,

      "__storage_download" => fn [key] ->
        result =
          ExAws.S3.get_object(bucket(), key)
          |> ExAws.request(ex_aws_config())

        case result do
          {:ok, %{body: body}} -> Base.encode64(body)
          {:error, {:http_error, 404, _}} -> nil
          {:error, reason} -> raise "S3 download failed: #{inspect(reason)}"
        end
      end,

      "__storage_url" => fn [key, expires_in] ->
        config = ex_aws_config()

        {:ok, url} =
          ExAws.S3.presigned_url(config, :get, bucket(), key,
            expires_in: expires_in || 3600
          )

        url
      end,

      "__storage_delete" => fn [key] ->
        ExAws.S3.delete_object(bucket(), key)
        |> ExAws.request(ex_aws_config())

        :ok
      end,

      "__storage_exists" => fn [key] ->
        case ExAws.S3.head_object(bucket(), key) |> ExAws.request(ex_aws_config()) do
          {:ok, _} -> true
          {:error, {:http_error, 404, _}} -> false
          {:error, reason} -> raise "S3 exists check failed: #{inspect(reason)}"
        end
      end
    }
  end

  defp bucket do
    System.get_env("S3_BUCKET") || System.get_env("AWS_S3_BUCKET") ||
      raise "S3 bucket not configured. Set S3_BUCKET or AWS_S3_BUCKET environment variable."
  end

  defp ex_aws_config do
    config = [
      region: System.get_env("AWS_REGION", "us-east-1"),
      access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
      secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY")
    ]

    case System.get_env("AWS_ENDPOINT_URL") do
      nil -> config
      endpoint ->
        uri = URI.parse(endpoint)
        config ++
          [
            scheme: "#{uri.scheme}://",
            host: uri.host,
            port: uri.port
          ]
    end
  end
end
