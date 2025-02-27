defmodule TestOtelResourceDynatrace do
  use ExUnit.Case, async: false
  import Mock

  alias OtelResourceDynatrace

  describe "get_resource/1" do
    test "returns resource with correct attributes" do
      with_mock File, read!: fn _ -> "key1=value1\nkey2=value2" end do
        resource = OtelResourceDynatrace.get_resource(nil)
        assert resource == :otel_resource.create([{"key1", "value1"}, {"key2", "value2"}])
      end
    end

    test "handles missing files gracefully" do
      with_mock File, read!: fn _ -> raise File.Error, message: "File not found" end do
        resource = OtelResourceDynatrace.get_resource(nil)
        assert resource == :otel_resource.create([])
      end
    end

    test "filters out duplicate keys" do
      with_mock File, read!: fn _ -> "key1=value1\nkey1=value2" end do
        resource = OtelResourceDynatrace.get_resource(nil)
        assert resource == :otel_resource.create([{"key1", "value1"}])
      end
    end

    test "filters out error attributes" do
      with_mock File, read!: fn _ -> "key1=value1\n" end do
        resource = OtelResourceDynatrace.get_resource(nil)
        assert resource == :otel_resource.create([{"key1", "value1"}])
      end
    end
  end
end
