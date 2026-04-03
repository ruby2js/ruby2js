defmodule JuntosBeam.Database do
  @moduledoc """
  Database bridge for QuickBEAM.
  Handles __db_query, __db_execute, __db_init, __db_close calls from JS.
  Supports SQLite (via sqlite-napi addon) and PostgreSQL (via Postgrex).
  """

  require Logger

  @compile {:no_warn_undefined, Postgrex}

  # Build QuickBEAM handler map for database operations via Postgrex
  def postgrex_handlers do
    %{
      "__db_init" => fn [config] ->
        start_postgrex(config)
        :ok
      end,

      "__db_query" => fn [sql, params] ->
        case Postgrex.query(JuntosBeam.DB, sql, params) do
          {:ok, %{rows: rows, columns: columns}} ->
            Enum.map(rows, fn row ->
              columns |> Enum.zip(row) |> Map.new()
            end)

          {:error, err} ->
            raise "PostgreSQL error: #{Exception.message(err)}"
        end
      end,

      "__db_execute" => fn [sql, params] ->
        case Postgrex.query(JuntosBeam.DB, sql, params) do
          {:ok, %{num_rows: count, rows: rows, columns: columns}} ->
            result = %{"changes" => count}

            # Include rows if RETURNING clause was used
            if rows && length(rows) > 0 && columns do
              mapped = Enum.map(rows, fn row ->
                columns |> Enum.zip(row) |> Map.new()
              end)
              Map.put(result, "rows", mapped)
            else
              result
            end

          {:error, err} ->
            raise "PostgreSQL error: #{Exception.message(err)}"
        end
      end,

      "__db_close" => fn _args ->
        # Connection pool is managed by the supervisor; nothing to do
        :ok
      end
    }
  end

  defp start_postgrex(config) do
    url = config["url"] || System.get_env("DATABASE_URL")

    opts =
      if url do
        # Parse DATABASE_URL into Postgrex options
        uri = URI.parse(url)
        userinfo = String.split(uri.userinfo || "", ":")
        [
          hostname: uri.host,
          port: uri.port || 5432,
          database: String.trim_leading(uri.path || "/juntos_dev", "/"),
          username: Enum.at(userinfo, 0),
          password: Enum.at(userinfo, 1)
        ]
      else
        [
          hostname: config["host"] || "localhost",
          port: config["port"] || 5432,
          database: config["database"] || "juntos_dev",
          username: config["user"] || config["username"] || System.get_env("USER"),
          password: config["password"],
          pool_size: config["pool"] || 10
        ]
      end

    opts = Keyword.merge(opts, name: JuntosBeam.DB)

    case Postgrex.start_link(opts) do
      {:ok, _pid} ->
        Logger.info("Connected to PostgreSQL: #{opts[:database] || url}")
        :ok

      {:error, reason} ->
        raise "Failed to connect to PostgreSQL: #{inspect(reason)}"
    end
  end
end
