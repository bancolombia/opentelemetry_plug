defmodule OtelResourceDynatrace do
  @moduledoc """
  Extra metadata for Dynatrace
  This module has been created based on the documentation available at: https://docs.dynatrace.com/docs/ingest-from/extend-dynatrace/extend-data
  """
  require Logger

  @behaviour :otel_resource_detector

  def get_resource(_) do
    Logger.info("Getting dynatrace extra metadata")
    metadata = read_file("/var/lib/dynatrace/enrichment/dt_metadata.properties")
    metadata2 = read_file(read_file("dt_metadata_e617c525669e072eebe3d0f08212e8f2.properties"))
    metadata3 = read_file("/var/lib/dynatrace/enrichment/dt_host_metadata.properties")
    attributes = get_attributes(metadata ++ metadata2 ++ metadata3)

    filtered_attributes =
      Enum.uniq_by(attributes, fn {id, _value} -> id end)
      |> Enum.filter(fn {id, _value} -> id != :error end)

    :otel_resource.create(filtered_attributes)
  end

  defp read_file(file_name) do
    try do
      {:ok, String.split(File.read!(file_name), "\n")}
    rescue
      File.Error ->
        {:error, "File not found"}
    end
    |> unwrap_lines()
  end

  defp unwrap_lines({:ok, content}), do: content
  defp unwrap_lines({:error, _}), do: []

  defp get_attributes(metadata) do
    Enum.map(metadata, fn line ->
      if String.length(line) > 0 do
        [key, value] = String.split(line, "=")
        {key, value}
      else
        {:error, "EOF"}
      end
    end)
  end
end
